/*  Empire City: 1931 / Street Fight (Seibu, 1986) — CPU principal (Z80).
    Plantilla: cores/trojan/hdl/jttrojan_main.v (mismo chipset). Mapa = stfight_cpu1_map.
    Especificidades stfight:
      · **Cifrado de opcodes Seibu (split M1)**: 0x0000-0x7fff cifrado por una PAL 16R4 con split
        opcode/dato. **Se descifra AL VUELO en este módulo** (`dec_opc`/`dec_opr`, combinacional; ver
        abajo). En SDRAM BA0: **cpu.4u CRUDO @0x00000** (0x8000) + **bank(cpu.2u) @0x10000** (4×0x4000).
        ⚠ Antes había DOS imágenes precomputadas por Python (operands@0 + opcodes@0x8000): se abandonó
        porque **un `.mra` no puede descifrar** -> la placa recibía basura (negro, 2026-07-16, HANDOFF §6-B).
        `tools/empirecity_decrypt.py` sigue siendo la REFERENCIA (verificada byte-exacta vs MAME) contra
        la que se validaron estas ecuaciones.
      · **IM0 con DOS vectores**: vblank → 0xcf (RST08→0x0008); timer ~120 Hz → 0xd7 (RST10→0x0010).
      · **Banco 0x8000-0xbfff = FIJO EN 0** (stfight/empcity NUNCA lo conmutan; `set_entry(0)` al init y ya).
        ⛔ Antes conmutábamos con {d7,d2} de 0xc804 = BUG: eso es `cshooter_bank_w` de OTRO juego. Rompía
        el sonido de empcity (que escribe 0xc804 con esos bits ≠ 0). Ver el bloque de registros abajo.
    Contrato de puertos = el que instancia jtempirecity_game.v (no tocar sin actualizar el game top).

    ⚠️ INTEGRACIÓN PENDIENTE (requiere extender empirecity_video.v + wiring; se cierra con el boot en jtsim):
      (1) sprite_bank (0xc807) decodificado aquí en `sprbank`; falta ruta main→video (nuevo puerto).
      (2) read-back de sprram (0xf000) y vregs (0xd800): el mapa los permite (.ram()); el vídeo aún no
          expone esas lecturas → aquí devuelven 0xff (TODO). Si el programa las lee, habrá que exponerlas.
      (3) coins: coin_state vive aquí (coin_w ack + coin_r); falta el strobe "moneda válida" desde la MCU
          (port C) → nuevo puerto main←mcu. Hoy coin_state = 3 (sin monedas). Ver stfight.cpp _68705_port_c_w.
    GPLv3 — crédito a jotego/JTFRAME. */
module empirecity_main(
    input             rst, clk, cen3, LVBL, dip_pause,
    // ROM Z80 principal (SDRAM BA0)
    output reg [17:0] main_addr,
    output reg        main_cs,
    input      [ 7:0] main_data,
    input             main_ok,
    // cabina
    input      [ 1:0] cab_1p, coin,
    input      [ 7:0] joystick1, joystick2,
    input             service,
    input      [ 7:0] dipsw_a, dipsw_b,
    // interfaz CPU <-> vídeo (RAMs internas del juego)
    output     [12:0] cpu_addr,
    output     [ 7:0] cpu_dout,
    output            cpu_rnw,
    output reg        vram_cs,
    input      [ 7:0] vram_dout,
    output reg        pal_cs,
    input      [ 7:0] pal_dout,
    output reg        vreg_cs, spr_cs,
    input      [ 7:0] vreg_dout, spr_dout,
    output     [ 9:0] sprbank_o,   // sprite_bank (0xc807) -> base de sprites del vídeo
    output reg        flip,
    // sonido
    output reg [ 7:0] snd_latch,
    output reg        snd_wr, fm_wr,
    input      [ 7:0] fm_dout,
    // MCU
    output     [ 7:0] cpu2mcu,      // dato a la MCU = cpu_dout combinacional (válido durante mcu_we)
    output reg        mcu_we,
    input      [ 1:0] coin_valid,   // pulso de moneda validada por la MCU -> baja coin_state
    input             mcu_nmi_n
);
`ifndef NOMAIN
wire [15:0] A;
wire        rd_n, wr_n, mreq_n, rfsh_n, iorq_n, m1_n, rst_n, cpu_cen, busak_n;
reg  [ 7:0] cpu_din, cab_dout;
wire [ 7:0] ram_dout8;   // salida .q de u_ram: DEBE ser wire (Quartus Error 10663; Verilator lo toleraba)
reg         ram_cs, in_cs, coin_cs, io_cs, sprbank_cs;
reg  [ 1:0] bank;
reg  [ 9:0] sprbank;       // (d&4)<<7 | (d&1)<<8 -> {0,0x100,0x200,0x300}; TODO rutar a vídeo
reg  [ 1:0] coin_state;

assign cpu_addr  = A[12:0];
assign cpu_rnw   = wr_n;
assign sprbank_o = sprbank;
assign cpu2mcu   = cpu_dout;   // combinacional: válido durante la escritura a 0xc600 (la MCU latchea en mcu_we)

// ---- decodificación (stfight_cpu1_map) ----
always @(*) begin
    main_cs    = 1'b0;
    ram_cs     = 1'b0;
    pal_cs     = 1'b0;
    vram_cs    = 1'b0;
    vreg_cs    = 1'b0;
    spr_cs     = 1'b0;
    in_cs      = 1'b0;
    coin_cs    = 1'b0;
    io_cs      = 1'b0;
    sprbank_cs = 1'b0;
    snd_wr     = 1'b0;
    fm_wr      = 1'b0;
    mcu_we     = 1'b0;
    if( rfsh_n && !mreq_n ) begin
        casez( A[15:13] )
            3'b0??: main_cs = 1'b1;                 // 0x0000-0x7fff  ROM (cifrado)
            3'b10?: main_cs = 1'b1;                 // 0x8000-0xbfff  ROM banco
            3'b110: begin                           // 0xc000-0xdfff
                casez( A[12:8] )
                    5'b0000?: pal_cs  = 1'b1;       // 0xc000-0xc1ff  paleta (lo/hi por A[8])
                    5'b00010: begin                 // 0xc200-0xc2ff  inputs / coin_r
                        in_cs   = (A[2:0] != 3'd5);
                        coin_cs = (A[2:0] == 3'd5);  // 0xc205
                    end
                    5'b00101: begin                 // 0xc500  fm_w
                        snd_wr = !wr_n; fm_wr = !wr_n;
                    end
                    5'b00110: mcu_we = !wr_n;        // 0xc600  mcu_w
                    5'b00111: coin_cs = 1'b1;        // 0xc700  coin_w (ack)
                    5'b01000: begin                 // 0xc800-0xc8ff
                        io_cs      = (A[3:0]==4'h4) && !wr_n;  // 0xc804 io_w (banco)
                        sprbank_cs = (A[3:0]==4'h7) && !wr_n;  // 0xc807 sprite_bank
                    end
                    5'b10???: vram_cs = 1'b1;        // 0xd000-0xd7ff  txram
                    5'b11???: vreg_cs = 1'b1;        // 0xd800-0xdfff  vregs (usa d800-d808)
                    default:;
                endcase
            end
            3'b111: begin                           // 0xe000-0xffff
                ram_cs = !A[12];                    // 0xe000-0xefff  RAM
                spr_cs =  A[12];                    // 0xf000-0xffff  sprite_ram
            end
        endcase
    end
end

// ---- registros de escritura (banco / flip / sprite_bank / latches) ----
always @(posedge clk) begin
    if( rst ) begin
        bank <= 2'd0; sprbank <= 10'd0; flip <= 1'b0; snd_latch <= 8'd0;
    end else if( cen3 ) begin
        // ⛔ BANCO 0x8000-0xbfff = FIJO EN 0 en stfight/empcity. NO se conmuta.
        // BUG (2026-07-17, regresión al pasar a empcity): antes hacíamos `bank <= {d[7],d[2]}` en cada
        // escritura a 0xc804. Pero en MAME 0xc804 = `io_w` = SOLO contadores de moneda (stfight.cpp:436);
        // el `set_entry(bitswap(data,7,2))` (línea 413) es `cshooter_bank_w`, de **Cross Shooter, OTRO
        // juego** (solo en cshooter_cpu1_map @0xc801). En stfight/empcity: `set_entry(0)` en el init y
        // NUNCA más ("It's entirely possible that this bank is never switched out", stfight.cpp:409).
        // empcityu escribía 0xc804 con d[7]=d[2]=0 (banco 0 por casualidad) → sonaba; empcity los pone
        // a 1 → saltábamos a banco 1/2/3 → basura en 0x8000-0xbfff → SONIDO CORTADO. `bank` queda en 0.
        if( sprbank_cs ) sprbank <= { cpu_dout[2], cpu_dout[0], 8'd0 }; // (d&4)<<7 | (d&1)<<8
        if( snd_wr )     snd_latch <= cpu_dout;      // 0xc500 -> latch de sonido
    end
end

// ---- coin_state (0xc205 read / 0xc700 write ack) ----
// stfight: init=3; coin_w RE-pone bits (activo-bajo); la MCU los BAJA al validar moneda (coin_valid).
always @(posedge clk) begin
    if( rst ) coin_state <= 2'b11;
    else begin
        if( cen3 && coin_cs && !wr_n ) begin        // 0xc700 coin_w (ack, activo-bajo)
            if( !cpu_dout[0] ) coin_state[0] <= 1'b1;
            if( !cpu_dout[1] ) coin_state[1] <= 1'b1;
        end
        if( coin_valid[0] ) coin_state[0] <= 1'b0;  // moneda validada por la MCU (prioridad)
        if( coin_valid[1] ) coin_state[1] <= 1'b0;
    end
end

`ifdef SIMULATION
// ---- DIAG COIN (Fase 5, bug del coin): un contador POR ESLABON del handshake ----
//   L1 coin_w (0xc700, el main ARMA) | L2 coin_valid (la MCU VALIDA) | L3 coin_r (0xc205, el main LEE)
// ⚠ CADA LINEA LLEVA SU `n=` (nº de evento) A PROPOSITO: el log de jtsim REPITE BLOQUES ENTEROS (re-vuelca
// su buffer al imprimir el progreso con escapes ANSI) => `grep -c` CUENTA DE MAS. El 2026-07-17 casi
// reporto "entran 4 monedas de una pulsacion" cuando era UNA (mismo `cencnt` en las 4 copias). Con `n=`,
// las copias comparten numero y se distinguen del evento real: cuenta `n` DISTINTOS, no lineas.
integer n_coinw=0, n_coinvalid=0, n_coinr=0;
reg [1:0] cst_p=2'b11, cline_p=2'b11;
always @(posedge clk) if( !rst ) begin
    if( cen3 && coin_cs && !wr_n ) begin
        n_coinw = n_coinw+1;
        $display("[COIN] L1 coin_w  A=%h d=%h -> arma (coin_state=%b) n=%0d", A, cpu_dout, coin_state, n_coinw);
    end
    if( coin_valid!=2'b00 ) begin
        n_coinvalid = n_coinvalid+1;
        $display("[COIN] L2 coin_valid=%b (MCU valida) n=%0d", coin_valid, n_coinvalid);
    end
    if( cen3 && coin_cs && !rd_n && A[2:0]==3'd5 ) begin
        n_coinr = n_coinr+1;
        if( coin_state!=2'b11 )
            $display("[COIN] L3 coin_r  <- %b  (!=11: el main VE la moneda) n=%0d", coin_state, n_coinr);
    end
    if( coin_state != cst_p )
        $display("[COIN] ** coin_state %b -> %b", cst_p, coin_state);
    cst_p <= coin_state;
    if( coin != cline_p ) begin
        $display("[COIN] linea de cabina coin %b -> %b (0=pulsado)", cline_p, coin);
    end
    cline_p <= coin;
end
// (sin `final`: Verilator parsea .v como Verilog-2005 y no lo admite. Los totales se cuentan
//  con `grep -c` sobre el log en _empirecity_coin.sh.)
`endif

// ---- inputs ----
always @(*) begin
    case( A[2:0] )
        3'd0: cab_dout = joystick1;                          // 0xc200 P1
        3'd1: cab_dout = joystick2;                          // 0xc201 P2
        // 0xc202 START (b4=st2, b3=st1). ⛔ NO INVERTIR: jtframe entrega cab_1p/coin/joystick
        // **ACTIVO-BAJO**, igual que los espera MAME (IP_ACTIVE_LOW). Evidencia:
        // `jtframe_game_instance.v`: `assign game_start[1]=1'b1; game_coin[1]=1'b1; game_joystick2=~10'd0;`
        // (reposo = todo unos) y trojan (nuestra plantilla) los pasa DIRECTOS: `{ coin, 4'hf, cab_1p }`.
        // Estaba `~cab_1p` -> en reposo daba 0 = "START PULSADO SIEMPRE" -> el juego no ve el flanco
        // -> **"el start no responde"** en placa (2026-07-16).
        3'd2: cab_dout = { 3'b111, cab_1p[1], cab_1p[0], 3'b111 };
        3'd3: cab_dout = dipsw_a;                            // 0xc203 DSW0
        3'd4: cab_dout = dipsw_b;                            // 0xc204 DSW1
        3'd5: cab_dout = { 6'h00, coin_state };              // 0xc205 coin_r
        default: cab_dout = 8'hff;
    endcase
end

// ---- ROM address (SDRAM BA0), consciente del cifrado + banco ----
//   0x0000-0x7fff -> 0x00000+A          (cpu.4u CRUDO; el descifrado es COMBINACIONAL aquí, no por dirección)
//   0x8000-0xbfff -> 0x10000 + bank*0x4000 + A[13:0]   (cpu.2u, NO cifrado)
// ⛔ AQUÍ PONÍA "opcode(M1) -> 0x08000+A ; dato -> 0x00000+A": **FALSO** (2026-07-17). Era del esquema
//    ABANDONADO de dos imágenes precomputadas (operands@0 + opcodes@0x8000), que se tiró porque una
//    `.mra` no puede descifrar. El código de debajo NUNCA usa 0x8000+A. Consecuencia real: **0x08000-
//    0x0FFFF de BA0 no se direcciona jamás** -> lo que haya ahí (relleno) da igual. Si te fías del
//    comentario, concluyes lo contrario. *(Un comentario no es una medida: el mismo día, un comentario
//    que afirmaba "`bits` es una LISTA" en el .mra era el bug de los DIP.)*
wire is_opcode = ~m1_n;   // fetch de opcode en ciclo M1
always @(*) begin
    if( !A[15] )
        main_addr = { 3'b000, A[14:0] };                    // cpu.4u CRUDO (cifrado) @0
    else
        main_addr = { 2'b01, bank, A[13:0] };               // banco (cpu.2u) @0x10000, NO cifrado
end

// ============================ DESCIFRADO AL VUELO (Seibu PAL 16R4, split M1/dato) ============
// ⭐ ANTES: la SDRAM llevaba DOS imágenes YA descifradas (operands@0 + opcodes@0x8000) que precomputaba
// `tools/empirecity_decrypt.py`. **Eso NO puede llegar a la placa: un `.mra` solo CONCATENA trozos de
// ROM, no puede descifrar** -> el HW recibía cpu.4u cifrado y el Z80 ejecutaba basura (negro + silencio,
// 2026-07-16). Ver HANDOFF §6-B.
// AHORA: la SDRAM lleva **cpu.4u CRUDO** (lo que hay en el zip = lo que el .mra puede entregar) y el
// descifrado se hace aquí, combinacional. Sim y placa comparten UNA SOLA imagen -> se mata de raíz esta
// clase de divergencia (§H22).
//
// Es una PAL: función pura de (byte, dirección). Preserva 0xa6 (bits 7,5,2,1) y recalcula D6/D4/D3/D0.
// Solo depende de A[7], A[4], A[1], A[0] -> 8 XOR, coste despreciable.
// ⚠ Ecuaciones DERIVADAS del port de MAME y **verificadas EXHAUSTIVAMENTE** contra `decrypt()` de
// `empirecity_decrypt.py`: 0x8000 direcciones x 256 bytes = 8.388.608 combinaciones, 0 discrepancias.
// (El Python usa enteros SIN truncar: transcribir sus `<<`/`~` a ojo es donde se cuela el bug. No lo
//  toques sin re-verificar con el mismo barrido.)
function [7:0] dec_opc(input [7:0] s, input [14:0] a);   // fetch M1
    dec_opc = { s[7], s[1]^s[3], s[5], ~(s[6]^a[7]), ~(s[0]^a[1]), s[2], s[1], s[1]^s[4] };
endfunction
function [7:0] dec_opr(input [7:0] s, input [14:0] a);   // lectura de dato/operando
    dec_opr = { s[7], ~(s[1]^s[0]), s[5], s[3]^a[0], s[4]^a[4], s[2], s[1], ~(s[6]^a[0]) };
endfunction
// A está estable mientras dura el fetch (jtframe_z80wait para la CPU hasta main_ok) -> se puede usar
// combinacionalmente junto con main_data. El banco (A[15]=1) NO se cifra.
wire [7:0] main_dec = !A[15] ? ( is_opcode ? dec_opc( main_data, A[14:0] )
                                           : dec_opr( main_data, A[14:0] ) )
                             : main_data;

// ---- RAM de trabajo 4KB (0xe000-0xefff) ----
jtframe_ram #(.AW(12)) u_ram(
    .clk ( clk ), .cen ( 1'b1 ), .data ( cpu_dout ),
    .addr( A[11:0] ), .we ( ram_cs && !wr_n ), .q ( ram_dout8 )
);

// ---- din de la CPU + inyección de vector IM0 ----
wire irq_ack = ~iorq_n && ~m1_n;
reg  [7:0] int_vec;
always @(posedge clk) begin
    cpu_din <= main_cs ? main_dec   :   // main_dec = main_data descifrado al vuelo (ver arriba)
               ram_cs  ? ram_dout8  :
               vram_cs ? vram_dout  :
               spr_cs  ? spr_dout   :
               vreg_cs ? vreg_dout  :
               pal_cs  ? pal_dout   :
               in_cs   ? cab_dout   :
               coin_cs ? { 6'h00, coin_state } : 8'hff;
    if( irq_ack ) cpu_din <= int_vec;   // IM0: vector en el bus durante el ack
end

// ---- interrupciones IM0: vblank->0xcf, timer 120Hz->0xd7 ; NMI de la MCU ----
localparam [14:0] T120 = 15'd24999;     // 3 MHz / 120 = 25000
reg        irqn, LVBLl;
reg [14:0] tcnt;
reg        tarm;
always @(posedge clk) begin
    if( rst ) begin
        irqn <= 1'b1; LVBLl <= 1'b0; tcnt <= 15'd0; tarm <= 1'b0; int_vec <= 8'hcf;
    end else begin
        LVBLl <= LVBL;
        // ⛔⛔ POLARIDAD DE dip_pause: es **ALTO cuando el juego CORRE** (bajo = PAUSA).
        // Estaba INVERTIDO (`if(!dip_pause)`) -> la IRQ de VBLANK no se disparaba NUNCA en juego
        // normal, solo en pausa. **Ese era el cuelgue del 2026-07-16**: el juego dibujaba (eso lo
        // hace el handler del TIMER, 0xd7) pero la LÓGICA no avanzaba (eso es el de vblank) ->
        // pantalla de Taito y spin eterno en 0x2854 esperando E43B, que solo incrementa el handler
        // de vblank (0x2CA2 `inc (hl)` @2CC6). MEDIDO: 0 acks con vector 0xcf en 250 frames.
        // Evidencia de la polaridad: jtframe_board.v:291 `show_credits <= locked | ~dip_pause`;
        // gng `.nIRQ( LVBL | ~dip_pause )`; trojan (nuestra plantilla) `irqn <= ~nmi_mask | ~dip_pause`.
        // vblank (flanco de bajada de LVBL) -> RST08 (0xcf) + arma timer
        if( !LVBL && LVBLl ) begin
            if( dip_pause ) begin irqn <= 1'b0; int_vec <= 8'hcf; end
            tcnt <= 15'd0; tarm <= 1'b1;
        end
        // timer ~120 Hz (one-shot tras vblank) -> RST10 (0xd7). MAME: rst08_tick -> vector 0xd7,
        // armado por vb_interrupt con `m_int1_timer->adjust(attotime::from_hz(120))`.
        if( tarm && cen3 ) begin
            if( tcnt==T120 ) begin
                tarm <= 1'b0;
                if( dip_pause ) begin irqn <= 1'b0; int_vec <= 8'hd7; end   // la pausa para AMBAS
            end else tcnt <= tcnt + 15'd1;
        end
        if( irq_ack ) irqn <= 1'b1;         // ACK limpia
    end
end

`ifdef SIMULATION
// diagnóstico: imprime SALTOS de PC (dedup de bucles tight) + eventos clave. Revela el control-flow.
reg  m1_l2, lvbl_l, nmi_l; reg [15:0] pc_prev, js_l, jd_l; integer njmp=0;
// ⭐ DIAGNÓSTICO DEL CUELGUE (2026-07-16): el juego spinea en 0x2854 esperando a E43B.
// Del oráculo (MAME): E43B lo incrementa SOLO el handler de VBLANK (RST08=0xcf, 0x2CA2), y solo si
// E00F==0 (`2CB0: ld a,($E00F) / and a / jp nz,$2CC7` se salta el `inc (hl)` de 2CC6).
// Estas cuentas separan las 2 hipótesis: (a) la IRQ de vblank NO llega -> cf no sube;
//                                        (b) llega pero E00F!=0 -> cf sube y E43B NO.
reg [15:0] n_cf=0, n_d7=0;
always @(posedge clk) if( irq_ack ) begin
    if( int_vec==8'hcf ) n_cf <= n_cf + 16'd1;
    if( int_vec==8'hd7 ) n_d7 <= n_d7 + 16'd1;
end
reg  seen_pal, seen_tx, seen_mcu; reg [19:0] dbgcnt=0; reg [31:0] cencnt=0;
always @(posedge clk) begin
    lvbl_l <= LVBL; nmi_l <= mcu_nmi_n;
    if( cpu_cen && rst_n ) begin
        m1_l2 <= m1_n;                      // muestreo a resolución cpu_cen
        if( !m1_n && m1_l2 ) begin          // flanco de M1 = nuevo fetch
            if( (A > pc_prev+16'd8 || A+16'd8 < pc_prev) && njmp<120
                && !(pc_prev==js_l && A==jd_l) ) begin   // colapsa saltos idénticos consecutivos
                $display("[MAIN] PC %h -> %h", pc_prev, A); njmp=njmp+1;
                js_l<=pc_prev; jd_l<=A;
            end
            pc_prev <= A;
        end
    end
    // muestreo periódico crudo: ¿PC congelado (deadlock) o avanzando?
    dbgcnt <= dbgcnt + 1;
    if( cpu_cen ) cencnt <= cencnt + 1;
    if( dbgcnt == 20'd0 ) $display("[MAIN] tick PC=%h cencnt=%0d  IRQ cf=%0d d7=%0d  E00F=%h E43B=%h",
        pc_prev, cencnt, n_cf, n_d7, u_ram.mem[12'h00f], u_ram.mem[12'h43b]);
    if( mcu_we && !seen_mcu ) begin $display("[MAIN] >>> write MCU (0xc600) D=%h", cpu_dout); seen_mcu<=1; end
    if( nmi_l && !mcu_nmi_n ) $display("[MAIN] >>> NMI de la MCU");
    if( pal_cs && !wr_n && !seen_pal ) begin $display("[MAIN] >>> 1er write PALETA A=%h", A); seen_pal<=1; end
    if( vram_cs && !wr_n && !seen_tx ) begin $display("[MAIN] >>> 1er write TXRAM A=%h", A); seen_tx<=1; end
end
`endif

jt12_rst u_rst( .rst(rst), .clk(clk), .rst_n(rst_n) );

// espera de SDRAM (patrón trojan): gating de cen en lugar de wait_n directo (más robusto que main_ok|~cs)
jtframe_z80wait #(.DEVCNT(1)) u_wait(
    .rst_n   ( rst_n            ),
    .clk     ( clk              ),
    .cen_in  ( cen3             ),
    .cen_out ( cpu_cen          ),
    .gate    (                  ),
    .mreq_n  ( mreq_n & m1_n    ),
    .iorq_n  ( iorq_n           ),
    .busak_n ( busak_n          ),
    .dev_busy( 1'b0             ),   // las RAMs de vídeo son BRAM inmediata (sin busy)
    .rom_cs  ( main_cs          ),
    .rom_ok  ( main_ok          )
);

jtframe_z80 u_cpu(
    .rst_n  ( rst_n     ),
    .clk    ( clk       ),
    .cen    ( cpu_cen   ),
    .wait_n ( 1'b1      ),
    .int_n  ( irqn      ),
    .nmi_n  ( mcu_nmi_n ),
    .busrq_n( 1'b1      ),
    .m1_n   ( m1_n      ),
    .mreq_n ( mreq_n    ),
    .iorq_n ( iorq_n    ),
    .rd_n   ( rd_n      ),
    .wr_n   ( wr_n      ),
    .rfsh_n ( rfsh_n    ),
    .halt_n (           ),
    .busak_n( busak_n   ),
    .A      ( A         ),
    .din    ( cpu_din   ),
    .dout   ( cpu_dout  )
);
`else
assign main_addr=0; assign main_cs=0; assign cpu_addr=0; assign cpu_dout=0; assign cpu_rnw=1;
assign vram_cs=0; assign pal_cs=0; assign vreg_cs=0; assign spr_cs=0; assign flip=0;
assign sprbank_o=0;
assign snd_latch=0; assign snd_wr=0; assign fm_wr=0; assign cpu2mcu=0; assign mcu_we=0;
`endif
endmodule
