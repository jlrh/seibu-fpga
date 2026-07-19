/*  Empire City: 1931 (Seibu, 1986) — MCU 68705P5 (protección ACTIVA). Wrapper de jtframe_6805mcu.
    Patrón: cores/kunio, cores/flstory (mismo módulo 6805). Réplica EXACTA de los handlers del .cpp
    (stfight.cpp _68705_port_a/b/c_w, _68705_port_b_r, mcu_w):
      · main escribe nibble en 0xc600 -> cpu_to_mcu_data (4b) + cpu_to_mcu_empty=0.
      · port B in  = { coin[1:0]@7:6, 1'b0, empty@4, data[3:0] }.
      · port B out bit5=0 -> ACK: cpu_to_mcu_empty=1.
      · port A out = parte alta de la dir de sample ADPCM (se latchea <<9 al soltar el reset del MSM).
      · port C out bit0/1 = moneda válida (flanco de bajada -> pulso coin_valid, el main baja coin_state).
      · port C out bit2   = reset del MSM5205 (adpcm_rst); al bajar, el módulo adpcm latchea la dir.
      · port C out bit3   = NMI al main (0 = asserted -> mcu_nmi_n).
      · IRQ del 68705 = VCK/2 del MSM5205 (viene del módulo adpcm, corre siempre). timer interno sin usar.
    GPLv3 — crédito a jotego/JTFRAME. */
module empirecity_mcu(
    input             rst, clk, cen3,
    // main -> MCU (0xc600)
    input      [ 7:0] cpu2mcu,
    input             mcu_we,
    // MCU -> main
    output            mcu_nmi_n,
    output reg [ 1:0] coin_valid,   // pulso al validar moneda (main baja coin_state[n])
    // cabina
    input      [ 1:0] coin,
    // ADPCM
    output     [ 7:0] adpcm_start,  // port A (parte alta; el secuenciador hace <<9)
    output            adpcm_rst,    // port C bit2
    input             mcu_irq,      // VCK/2 del MSM5205 (del módulo adpcm)
    // firmware BRAM (0x800)
    output     [10:0] rom_addr,
    input      [ 7:0] rom_data
);
`ifndef NOMAIN
wire [7:0] pa_out, pb_out, mcu_db;
wire [3:0] pc_out;
wire [12:0] mcu_ab;
wire        mcu_wr;
reg  [3:0] c2m_data;
reg        c2m_empty;
reg  [7:0] pcout_r;      // réplica de m_port_c_out del driver (init 0xff = NMI alto, ADPCM en reset)
reg        nmin_r, arst_r;

// ⭐⭐ CONFORMADOR DE PULSO DE MONEDA ("coin mech") — el fix del bug del coin (2026-07-17).
// El botón crudo de MiSTer es una entrada que el HW real NUNCA produce: el firmware MIDE la anchura de
// la línea de coin y, si se queda baja > ~0.35 s, decide "stuck coin" -> NMI + `bra $218` = MCU COLGADO
// PARA SIEMPRE (ni monedas ni voces hasta reset). El porqué completo, en empirecity_coinmech.v.
wire [1:0] coin_mech;

empirecity_coinmech u_coinmech(
    .rst      ( rst       ),
    .clk      ( clk       ),
    .cen      ( cen3      ),
    .coin_btn ( coin      ),   // botón de jtframe (activo-bajo)
    .coin_mech( coin_mech )    // pulso de 133 ms por pulsación -> lo que el MCU cree que es el mecanismo
);

wire [7:0] pb_in = { coin_mech[1:0], 1'b0, c2m_empty, c2m_data };  // {coin,0,empty,data}
// ACK del MCU = ESCRITURA de port B (latch @addr=1) con bit5=0 (réplica de _68705_port_b_w). NO por nivel:
// pb_out[5] es entrada (DDR=0) y vale 0 constante -> el nivel borraría el comando al instante (bug).
wire pb_ack = mcu_wr && (mcu_ab==13'd1) && !mcu_db[5];
// ⭐ Escritura al REGISTRO DE DATOS de port C (dir 0x02): es la ÚNICA vez que el driver llama a
// _68705_port_c_w. NMI/coin/adpcm se derivan del VALOR ESCRITO, NO del pc_out combinacional de jtframe.
// Motivo: el firmware pone DDRC=0xff (0x114) ANTES de escribir el dato 0x0f (0x11c); con pc_latch=0 al
// reset, pc_out=(latch&ddr)|(in&~ddr) cae a 0 en esa ventana -> pc_out[3]=0 -> NMI ESPURIO que
// interrumpía el RAM-test (E010 aún = patrón 0x55) -> jump-table del NMI iba al handler equivocado
// (0x2204 en vez de 0x00B4) -> nunca copiaba la paleta -> pantalla negra. (GOTCHA nuevo.)
wire pc_wr = mcu_wr && cen3 && (mcu_ab==13'd2);
assign adpcm_start = pa_out;
assign adpcm_rst   = arst_r;         // bit2 del último dato escrito a port C (init 1 = reset)
assign mcu_nmi_n   = nmin_r;         // bit3=1 -> CLEAR (nmi_n alto); bit3=0 -> ASSERT

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        c2m_data <= 4'd0; c2m_empty <= 1'b1; coin_valid <= 2'b00;
        pcout_r <= 8'hff; nmin_r <= 1'b1; arst_r <= 1'b1;
    end else begin
        coin_valid <= 2'b00;                 // pulso de 1 ciclo
        // handshake con el main
        if( mcu_we )        begin c2m_data <= cpu2mcu[3:0]; c2m_empty <= 1'b0; end
        else if( pb_ack )   c2m_empty <= 1'b1;          // ACK del MCU (escribe port B, bit5=0)
        // port C: réplica EXACTA de _68705_port_c_w (sólo en la escritura del dato)
        if( pc_wr ) begin
            if( pcout_r[0] && !mcu_db[0] ) coin_valid[0] <= 1'b1;  // flanco de bajada -> moneda válida
            if( pcout_r[1] && !mcu_db[1] ) coin_valid[1] <= 1'b1;
            arst_r  <= mcu_db[2];            // bit2 = reset MSM5205 (el módulo adpcm latchea al bajar)
            nmin_r  <= mcu_db[3];            // bit3 = NMI al main
            pcout_r <= mcu_db;
        end
    end
end

`ifdef SIMULATION
// traza de ARRANQUE del MCU: primeros fetches CRUDOS desde reset + estado del IRQ temprano.
reg [10:0] ra_p; integer nra=0, nw=0;
always @(posedge clk) if(cen3 && !rst) begin
    if( rom_addr!=ra_p && nra<40 ) begin
        $display("[MCU] fetch addr=%h data=%h irq=%b", rom_addr, rom_data, mcu_irq); nra=nra+1;
    end
    ra_p <= rom_addr;
    if( mcu_wr && mcu_ab<13'd10 && nw<30 ) begin
        $display("[MCU] wr reg%0d = %h", mcu_ab, mcu_db); nw=nw+1;
    end
end
// ---- DIAG COIN (Fase 5): qué VE el MCU en port B y qué SACA por port C ----
reg [1:0] cin_p=2'b11, cmech_p=2'b11;
integer n_pcwr=0;
always @(posedge clk) if(!rst) begin
    if( coin != cin_p )
        $display("[MCU-COIN] BOTON coin %b -> %b (0=pulsado)", cin_p, coin);
    cin_p <= coin;
    // lo que VE el MCU tras el conformador: debe ser SIEMPRE un pulso de ~133 ms, mida lo que mida
    // el boton. Si esto se queda bajo mas de ~0.35 s -> stuck coin -> MCU colgado en 0x218.
    if( coin_mech != cmech_p )
        $display("[MCU-COIN] pb_in[7:6] (mech) %b -> %b (0=moneda)", cmech_p, coin_mech);
    cmech_p <= coin_mech;
    if( pc_wr ) begin
        n_pcwr = n_pcwr+1;
        if( n_pcwr<200 || mcu_db[1:0]!=2'b11 )
            $display("[MCU-COIN] portC wr %h -> %h (bit0/1=coin valid en flanco bajo)",
                     pcout_r, mcu_db);
    end
end
reg nmin_p=1;
always @(posedge clk) begin
    if( nmin_p && !nmin_r ) $display("[MCU] >>> NMI ASSERT (pcout=%h)", pcout_r);
    if( !nmin_p && nmin_r ) $display("[MCU] >>> NMI clear");
    nmin_p <= nmin_r;
end
`endif

jtframe_6805mcu u_mcu(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .cen    ( cen3      ),
    .wr     ( mcu_wr    ),
    .addr   ( mcu_ab    ),
    .dout   ( mcu_db    ),
    .irq    ( mcu_irq   ),   // VCK/2 del MSM5205 (activo alto)
    .timer  ( 1'b0      ),
    .pa_in  ( 8'hff     ),   // port A entradas con pull-up (sólo se usa la salida)
    .pa_out ( pa_out    ),
    .pb_in  ( pb_in     ),
    .pb_out ( pb_out    ),
    .pc_in  ( 4'hf      ),
    .pc_out ( pc_out    ),
    .rom_addr( rom_addr ),
    .rom_data( rom_data ),
    .rom_cs (           )
);
`else
assign mcu_nmi_n=1; assign adpcm_start=0; assign adpcm_rst=1; assign rom_addr=0;
initial coin_valid=0;
`endif
endmodule
