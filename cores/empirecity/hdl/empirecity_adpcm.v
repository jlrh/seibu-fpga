/*  Empire City: 1931 (Seibu, 1986) — ADPCM (MSM5205 vía jt5205), DIRIGIDO POR LA MCU.
    Réplica de stfight.cpp adpcm_int + _68705_port_c_w:
      · la MCU latchea la parte alta de la dir (port A) al SOLTAR el reset (port C bit2, flanco de bajada):
        offs = start<<9  (uint16, por eso start[6:0]<<9).
      · en cada VCK (mientras !reset): sample = adpcm[(offs>>1)&0x7fff]; nibble = offs par? ALTO : BAJO;
        offs++; se alimenta al MSM.
      · el IRQ del 68705 = VCK/2 (m_vck2 conmuta en cada VCK). El VCK del MSM corre SIEMPRE (aun en reset),
        por eso jt5205 NO se resetea con adpcm_rst (si no, se pararía el IRQ del MCU).
    S48_4B -> sel=2'b10 (8 kHz). GPLv3 — crédito a jotego/JTFRAME. */
module empirecity_adpcm(
    input                rst, clk, cenp384,
    input      [ 7:0]    start_hi,     // MCU port A (parte alta de la dir)
    input                adpcm_rst,    // MCU port C bit2 (1=reset/silencio, 0=play)
    output reg           mcu_irq,      // VCK/2 -> IRQ del 68705
    output     [14:0]    rom_addr,     // bus SDRAM 'adpcm' (32KB)
    output               rom_cs,
    input      [ 7:0]    rom_data,
    input                rom_ok,
    output signed [11:0] pcm
);
`ifndef NOSOUND
wire signed [11:0] pcm_raw;
// ⭐ DC-BLOCKER del ADPCM. jt5205 NO se resetea (el VCK debe seguir para el IRQ del MCU) -> en reposo su
// acumulador DPCM DERIVA a un DC != 0. Ese DC, a ganancia máxima en el mixer (`g4=0x80`, DCRM4=0), SATURABA el
// sumador y TAPABA la FM (música). Quitando el DC de forma CONTINUA (paso-alto): (a) en reposo pcm≈0 -> no tapa
// la música; (b) durante disparos/grito no satura -> la FM sobrevive; (c) sin el CLIC del salto de DC que dejaba
// el gate anterior (pcm=adpcm_rst?0:...), que convertía cada disparo en un clic flojo. jt5205 es SIGNED -> SIGNED_INPUT=1.
jtframe_dcrm #(.SW(12), .SIGNED_INPUT(1)) u_pcm_dcrm(
    .rst( rst ), .clk( clk ), .sample( cenp384 ), .din( pcm_raw ), .dout( pcm )
);
reg  [15:0] offs;
reg  [ 3:0] nibble;
reg         adpcm_rst_l, irq_l;
wire        vck_irq;

assign rom_addr = offs[15:1];          // (offs>>1) & 0x7fff
assign rom_cs   = ~adpcm_rst;

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        offs <= 16'd0; nibble <= 4'd0; adpcm_rst_l <= 1'b1; irq_l <= 1'b0; mcu_irq <= 1'b0;
    end else begin
        adpcm_rst_l <= adpcm_rst;
        irq_l       <= vck_irq;
        // soltar reset -> latch de la dir de arranque (start<<9, uint16)
        if( adpcm_rst_l && !adpcm_rst ) offs <= { start_hi[6:0], 9'd0 };
        // VCK (flanco) -> IRQ MCU a mitad de frecuencia + avance de nibble
        if( vck_irq && !irq_l ) begin
            mcu_irq <= ~mcu_irq;
            if( !adpcm_rst ) begin
                nibble <= offs[0] ? rom_data[3:0] : rom_data[7:4]; // par->alto, impar->bajo
                offs   <= offs + 16'd1;
            end
        end
    end
end

`ifdef SIMULATION
reg [31:0] vckcnt=0, p384cnt=0; reg [19:0] ac=0; reg vl;
always @(posedge clk) begin
    ac<=ac+1; if(cenp384) p384cnt<=p384cnt+1; vl<=vck_irq; if(vck_irq&&!vl) vckcnt<=vckcnt+1;
    if(ac==20'd0) $display("[ADPCM] cenp384_pulsos=%0d VCK_pulsos=%0d mcu_irq=%b", p384cnt, vckcnt, mcu_irq);
end
`endif

jt5205 #(.INTERPOL(0)) u_msm(
    .rst    ( rst              ),   // NO se resetea con adpcm_rst: el VCK debe seguir corriendo
    .clk    ( clk              ),
    .cen    ( cenp384          ),
    .sel    ( 2'b10            ),   // S48_4B -> 8 kHz
    .din    ( adpcm_rst ? 4'd8 : nibble ), // en reset: código medio (el acumulador deriva -> se gatea la salida a 0 arriba)
    .sound  ( pcm_raw          ),
    .sample (                  ),
    .irq    ( vck_irq          ),
    .vclk_o (                  )
);
`else
    assign rom_addr = 0; assign rom_cs = 0; assign pcm = 0;
    initial mcu_irq = 0;
`endif
endmodule
