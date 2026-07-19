/*  Empire City: 1931 / Street Fight (Seibu, 1986) — CPU de sonido.
    Delta vs jtgng_sound (referencia canónica, cores/gng): mapa stfight, IRQ periódica 120 Hz
    generada AQUÍ (la CPU de sonido de stfight corre autónoma: el main NO la resetea, sólo le
    escribe el soundlatch en 0xc500), soundlatch con bit7 "dato pendiente", y **inyección del
    prescaler 0x2F** a ambos YM2203 al arranque (replica de init_ymhack del .cpp: el juego nunca
    escribe el divisor pero espera FM=1/2, SSG=1/1; jt03 resetea a FM=1/6, SSG=1/4 → sonaría lento).

    cpu2_map (del stfight.cpp):
      0x0000-0x7fff  ROM sonido (32 KB)
      0xc000-0xc001  YM2203 #1 (r/w, addr=A0)     0xc800-0xc801  YM2203 #2 (r/w, addr=A0)
      0xd000 nopr    0xd800 nopw    0xe800 nopw
      0xf000         fm_r  (lee soundlatch; ACK = borra bit7)
      0xf800-0xffff  RAM (2 KB)
    IRQ: periódica 120 Hz (irq0_line_hold), IM1 (salta a 0x0038).  GPLv3 — crédito a jotego/JTFRAME. */
module empirecity_sound(
    input                rst,
    input                clk,
    input                cen3,      // 3   MHz  (Z80)
    input                cen1p5,    // 1.5 MHz  (YM2203 x2)
    // Interfaz con la CPU principal (soundlatch, 0xc500)
    input      [ 7:0]    snd_latch,
    input                snd_wr,    // strobe de escritura del latch (main -> sonido)
    input                fm_wr,     // strobe alternativo (mismo evento 0xc500); se acepta cualquiera
    output     [ 7:0]    fm_dout,   // valor del latch expuesto de vuelta (readback; stfight no lo usa)
    // ROM de sonido (SDRAM, bus de 8 bits)
    output     [15:0]    rom_addr,
    output               rom_cs,
    input      [ 7:0]    rom_data,
    input                rom_ok,
    // Salida de audio (canales separados, mezcla en jtframe_mixer del game top)
    output        [ 9:0] psg0, psg1,
    output signed [15:0] fm0,  fm1,
    // ---- debug (JTFRAME_RELEASE off) — signos vitales del Z80 de sonido ----
    // snd_dbg  = {wait_n, rom_lock, int_n, fm_lock, hb_m1[3:0]}
    //   hb_m1  = contador que incrementa en cada fetch de OPCODE (M1). Si el Z80 corre, cuenta;
    //            si está CONGELADO, se para -> se ve en pantalla si el sonido está colgado.
    //   wait_n = 0 -> Z80 parado esperando SDRAM/YM.  rom_lock = 1 -> esperando rom_ok (SDRAM).
    // snd_dbg2 = {ym_wr_hb[3:0], fm1_act, fm0_act, psg1_act, psg0_act}
    //   ym_wr_hb = contador de ESCRITURAS del Z80 al YM (cuenta -> el Z80 dirige el YM).
    //   *_act    = esa salida del YM CAMBIÓ en la última ventana (1 -> el YM produce señal).
    output        [ 7:0] snd_dbg,
    output        [ 7:0] snd_dbg2,
    // snd_dbg3 = { fm0_peak[15:12], flag_B, flag_A, div_setting[1:0] }  (banco 03, debug en placa)
    //   nibble ALTO = amplitud pico de fm0 (4 bits altos): 0 = FM diminuta/muda; !=0 = FM con nivel real.
    //   nibble BAJO bits[1:0] = div_setting del YM: 00 = prescaler 0x2F APLICADO (FM 1/2); 10 = reset (FM 1/6, MAL).
    output        [ 7:0] snd_dbg3
);
`ifndef NOSOUND
wire [15:0] A;
wire        iorq_n, m1_n, wr_n, rd_n, mreq_n, rfsh_n;
wire [ 7:0] ram_dout, dout, fm0_dout, fm1_dout;
reg  [ 7:0] din;
reg         fm0_cs, fm1_cs, latch_cs, ram_cs, rom_csr;

assign rom_addr = A;            // A[15]==0 en toda lectura de ROM (0x0000-0x7fff)
assign rom_cs   = rom_csr;

// ---- decodificación (stfight cpu2_map) ----
always @(*) begin
    rom_csr  = 1'b0;
    ram_cs   = 1'b0;
    latch_cs = 1'b0;
    fm0_cs   = 1'b0;
    fm1_cs   = 1'b0;
    if( rfsh_n && !mreq_n )
        casez( A[15:11] )
            5'b0????: rom_csr  = 1'b1;   // 0x0000-0x7fff  ROM
            5'b11000: fm0_cs   = 1'b1;   // 0xc000-0xc7ff  YM2203 #1
            5'b11001: fm1_cs   = 1'b1;   // 0xc800-0xcfff  YM2203 #2
            5'b11110: latch_cs = 1'b1;   // 0xf000-0xf7ff  fm_r
            5'b11111: ram_cs   = 1'b1;   // 0xf800-0xffff  RAM
            default:;                    // 0xd000/0xd800/0xe800 = nop; 0x8000-0xbfff sin mapear
        endcase
end

// ---- soundlatch (fm_data) con semántica bit7 = "dato pendiente" ----
// main escribe 0xc500 -> fm_data = 0x80 | data.  sonido lee 0xf000 -> devuelve fm_data y ACK borra bit7.
reg  [7:0] fm_data;
reg        swr_l, fwr_l, latch_rd_l, wr_seen;
wire       wr_edge  = (snd_wr & ~swr_l) | (fm_wr & ~fwr_l);
wire       latch_rd = latch_cs && !rd_n;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        fm_data <= 8'h00; swr_l <= 1'b0; fwr_l <= 1'b0; latch_rd_l <= 1'b0; wr_seen <= 1'b0;
    end else begin
        swr_l <= snd_wr; fwr_l <= fm_wr; latch_rd_l <= latch_rd;
        // ⭐ RACE DEL SOUNDLATCH (causa del sonido mudo/intermitente). El Z80 pulea 0xf000 sin parar. Si el
        // comando del main (wr_edge) cae DURANTE una lectura del Z80 (tras muestrear pero antes del flanco de
        // bajada), el ACK de ESA lectura borraba el bit7 -> el comando llegaba SIN "pendiente" -> el Z80 no lo
        // despachaba -> sin música. Determinista en el sim (timing alineado -> se pierde SIEMPRE cmd 00/23),
        // intermitente en placa (timing con jitter -> a veces cuela). Fix: (a) SET domina (else if), y (b)
        // `wr_seen`: si llegó un comando en cualquier momento de la lectura en curso, NO borres el bit7 al
        // acabarla -> el comando sobrevive a la siguiente lectura. Réplica fiel de MAME fm_r/fm_w (atómicos).
        if( !latch_rd )     wr_seen <= 1'b0;               // fin/fuera de lectura: rearma
        else if( wr_edge )  wr_seen <= 1'b1;               // llegó comando durante la lectura en curso
        if( wr_edge )
            fm_data <= { 1'b1, snd_latch[6:0] };            // 0x80 | data (bit7 = comando pendiente)
        else if( latch_rd_l && !latch_rd && !wr_seen )
            fm_data[7] <= 1'b0;                             // ACK: borra bit7 SOLO si no llegó comando durante la lectura
    end
end
assign fm_dout = fm_data;

// ---- IRQ periódica 120 Hz (IM1) ----
// cen3 = 3 MHz; 3_000_000/120 = 25000 cuentas.  Enclavado hasta el ACK del ciclo de interrupción.
localparam [14:0] IRQ_DIV = 15'd24999;
reg  [14:0] irq_cnt;
reg         snd_int, snd_int_l, int_n;
wire        irq_ack = ~iorq_n & ~m1_n;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        irq_cnt <= 15'd0; snd_int <= 1'b0; snd_int_l <= 1'b0; int_n <= 1'b1;
    end else if( cen3 ) begin
        // tick 120 Hz
        if( irq_cnt==IRQ_DIV ) begin irq_cnt <= 15'd0; snd_int <= 1'b1; end
        else                   begin irq_cnt <= irq_cnt + 15'd1; snd_int <= 1'b0; end
        // enclavado de int_n
        snd_int_l <= snd_int;
        if( irq_ack )                 int_n <= 1'b1;
        else if( snd_int & ~snd_int_l ) int_n <= 1'b0;
    end
end

// ---- estados de espera (jt03 ocupado tras acceso + latencia SDRAM de la ROM) ----
// ⛔⛔ SON DOS BLOQUES, NO UNO. Copia FIEL de `cores/gng/hdl/jtgng_sound.v:260-288` (la referencia):
//   · fm_wait  -> SÍ va gateado por cen3 (cuenta ciclos de CPU que el jt03 está ocupado).
//   · rom_lock/wait_n -> **A CLK COMPLETO, SIN cen3**.
// **Estaban FUSIONADOS en un solo `always ... else if(cen3)` y ESE era el bug de "no hay música"**
// (2026-07-16): `rom_ok` es un PULSO CORTO de la SDRAM; muestreándolo solo en cen3 (1 de cada 16 clk)
// **se pierde** -> `rom_lock` se queda a 1 -> `wait_n=0` -> **el Z80 de sonido se CONGELA** y el YM2203
// se queda en su valor de reposo -> el mixer saca un **DC constante de -28416** (no silencio).
// MEDIDO: pc_max=5f2c congelado, latch_rd=4 congelado, rom_ok=0. El smoke standalone NO lo veía porque
// sirve la ROM cruda con rom_ok siempre a 1: **el TB no ejercitaba el handshake de SDRAM**.
// ⚠ Es el MISMO fallo que ya tuvo el main (HANDOFF 4d: "con el wait simple la CPU leía ROM obsoleta").
reg  [1:0] fm_wait;
reg        wait_n, last_fmx, last_rom, rom_lock;
wire       fmx_cs = fm0_cs | fm1_cs;
wire       fmx_posedge = fmx_cs & ~last_fmx;
wire       fm_lock = |fm_wait;

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        fm_wait <= 2'b00; last_fmx <= 1'b0;
    end else if( cen3 ) begin
        last_fmx <= fmx_cs;
        fm_wait  <= { fm_wait[0], fmx_posedge };
    end
end

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        wait_n <= 1'b1; last_rom <= 1'b0; rom_lock <= 1'b0;
    end else begin                       // <-- SIN cen3: hay que cazar el pulso de rom_ok
        last_rom <= rom_csr;
        if( rom_csr && !last_rom ) rom_lock <= 1'b1;
        if( rom_ok )               rom_lock <= 1'b0;
        wait_n   <= !fm_lock && !rom_lock;
    end
end

// ---- inyección del prescaler 0x2F (init_ymhack) ----
// Mantiene la CPU en reset hasta escribir addr=0x2F en ambos YM (data-less: selecciona prescaler).
reg  [5:0] ini_cnt;
reg        init_done, ini_cs0, ini_cs1, ini_wrn;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        ini_cnt <= 6'd0; init_done <= 1'b0; ini_cs0 <= 1'b0; ini_cs1 <= 1'b0; ini_wrn <= 1'b1;
    end else if( cen1p5 && !init_done ) begin
        ini_cnt <= ini_cnt + 6'd1;
        case( ini_cnt )
            6'd8:  begin ini_cs0 <= 1'b1; ini_wrn <= 1'b0; end  // write YM0 addr=0x2F
            6'd10: begin ini_wrn <= 1'b1; end
            6'd12: begin ini_cs0 <= 1'b0; end
            6'd16: begin ini_cs1 <= 1'b1; ini_wrn <= 1'b0; end  // write YM1 addr=0x2F
            6'd18: begin ini_wrn <= 1'b1; end
            6'd20: begin ini_cs1 <= 1'b0; init_done <= 1'b1; end
            default:;
        endcase
    end
end

// mux del bus de los YM entre el inyector (init) y la CPU
wire       ym0_csn = init_done ? ~fm0_cs : ~ini_cs0;
wire       ym1_csn = init_done ? ~fm1_cs : ~ini_cs1;
wire       ym_wrn  = init_done ? wr_n    : ini_wrn;
wire       ym_addr = init_done ? A[0]    : 1'b0;
wire [7:0] ym_din  = init_done ? dout    : 8'h2f;

// ---- din de la CPU ----
always @(posedge clk) begin
    case( 1'b1 )
        rom_csr:  din <= rom_data;
        fm0_cs:   din <= fm0_dout;   // status/SSG readback (mapa r/w)
        fm1_cs:   din <= fm1_dout;
        latch_cs: din <= fm_data;
        ram_cs:   din <= ram_dout;
        default:  din <= 8'hff;
    endcase
end

// ---- RAM de trabajo (2 KB) ----
jtframe_ram #(.AW(11)) u_ram(
    .clk    ( clk               ),
    .cen    ( 1'b1              ),
    .data   ( dout              ),
    .addr   ( A[10:0]           ),
    .we     ( ram_cs && !wr_n   ),
    .q      ( ram_dout          )
);

jtframe_z80 u_cpu(
    .rst_n      ( ~rst & init_done ), // arranca tras inyectar el prescaler
    .clk        ( clk         ),
    .cen        ( cen3        ),
    .wait_n     ( wait_n      ),
    .int_n      ( int_n       ),
    .nmi_n      ( 1'b1        ),
    .busrq_n    ( 1'b1        ),
    .m1_n       ( m1_n        ),
    .mreq_n     ( mreq_n      ),
    .iorq_n     ( iorq_n      ),
    .rd_n       ( rd_n        ),
    .wr_n       ( wr_n        ),
    .rfsh_n     ( rfsh_n      ),
    .halt_n     (             ),
    .busak_n    (             ),
    .A          ( A           ),
    .din        ( din         ),
    .dout       ( dout        )
);

wire [7:0] ym0_dbg, ym1_dbg;   // {flag_B,flag_A,div_setting} — div_setting[1:0]: 00=FM1/2(0x2F ok), 10=FM1/6(reset)

jt03 u_fm0(
    .rst    ( rst        ),
    .clk    ( clk        ),
    .cen    ( cen1p5     ),
    .din    ( ym_din     ),
    .addr   ( ym_addr    ),
    .cs_n   ( ym0_csn    ),
    .wr_n   ( ym_wrn     ),
    .psg_snd( psg0       ),
    .fm_snd ( fm0        ),
    .snd_sample (        ),
    .dout   ( fm0_dout   ),
    .irq_n  (            ),
    .IOA_in ( 8'd0       ),  .IOB_in ( 8'd0 ),
    .IOA_out(            ),  .IOB_out(      ),
    .IOA_oe (            ),  .IOB_oe (      ),
    .psg_A  (            ),  .psg_B  (      ),  .psg_C(  ),
    .snd    (            ),
    .debug_view( ym0_dbg  )
);

jt03 u_fm1(
    .rst    ( rst        ),
    .clk    ( clk        ),
    .cen    ( cen1p5     ),
    .din    ( ym_din     ),
    .addr   ( ym_addr    ),
    .cs_n   ( ym1_csn    ),
    .wr_n   ( ym_wrn     ),
    .psg_snd( psg1       ),
    .fm_snd ( fm1        ),
    .snd_sample (        ),
    .dout   ( fm1_dout   ),
    .irq_n  (            ),
    .IOA_in ( 8'd0       ),  .IOB_in ( 8'd0 ),
    .IOA_out(            ),  .IOB_out(      ),
    .IOA_oe (            ),  .IOB_oe (      ),
    .psg_A  (            ),  .psg_B  (      ),  .psg_C(  ),
    .snd    (            ),
    .debug_view( ym1_dbg  )
);
// ---- amplitud pico de fm0 + estado del YM (debug en placa, banco 03) ----
// Mide EN HARDWARE lo que hasta ahora solo teníamos en sim: ¿la FM tiene nivel real? ¿prescaler aplicado?
reg  [15:0] fm0_pk;
reg  [21:0] pkwin;                                     // ventana ~87ms (2^22/48MHz)
wire [15:0] fm0_abs = fm0[15] ? (~fm0 + 16'd1) : fm0;  // |fm0|
always @(posedge clk or posedge rst) begin
    if( rst ) begin fm0_pk <= 16'd0; pkwin <= 22'd0; end
    else begin
        pkwin <= pkwin + 22'd1;
        if( fm0_abs > fm0_pk ) fm0_pk <= fm0_abs;      // peak-hold en la ventana
        if( &pkwin ) fm0_pk <= 16'd0;                  // reinicia la ventana
    end
end
assign snd_dbg3 = { fm0_pk[15:12], ym0_dbg[3:0] };     // alto=amplitud FM (0=diminuta); bajo[1:0]=div_setting
// ---- heartbeat de vida del Z80 de sonido (debug en placa) ----
reg  [3:0] hb_m1;
reg        m1_dl;
always @(posedge clk or posedge rst) begin
    if( rst ) begin hb_m1 <= 4'd0; m1_dl <= 1'b1; end
    else begin
        m1_dl <= m1_n;
        if( !m1_n && m1_dl ) hb_m1 <= hb_m1 + 4'd1;   // flanco de fetch de opcode (M1)
    end
end
assign snd_dbg = { wait_n, rom_lock, int_n, fm_lock, hb_m1 };

// ---- YM: ¿el Z80 lo escribe? ¿produce salida? (debug en placa) ----
reg  [3:0] ym_wr_hb;
reg        ymwr_l;
wire       ymwr = (fm0_cs | fm1_cs) & ~wr_n;   // escritura del Z80 a cualquier YM
reg [15:0] fm0_p, fm1_p;
reg [ 9:0] psg0_p, psg1_p;
reg        fm0_c, fm1_c, psg0_c, psg1_c;       // cambió DENTRO de la ventana
reg        fm0_a, fm1_a, psg0_a, psg1_a;       // activo (latcheado por ventana, visible en pantalla)
reg [15:0] awin;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        ym_wr_hb<=4'd0; ymwr_l<=1'b0; awin<=16'd0;
        fm0_c<=0; fm1_c<=0; psg0_c<=0; psg1_c<=0;
        fm0_a<=0; fm1_a<=0; psg0_a<=0; psg1_a<=0;
        fm0_p<=0; fm1_p<=0; psg0_p<=0; psg1_p<=0;
    end else begin
        ymwr_l <= ymwr;
        if( ymwr && !ymwr_l ) ym_wr_hb <= ym_wr_hb + 4'd1;
        awin  <= awin + 16'd1;
        fm0_p <= fm0; fm1_p <= fm1; psg0_p <= psg0; psg1_p <= psg1;
        if( fm0 !=fm0_p  ) fm0_c  <= 1'b1;
        if( fm1 !=fm1_p  ) fm1_c  <= 1'b1;
        if( psg0!=psg0_p ) psg0_c <= 1'b1;
        if( psg1!=psg1_p ) psg1_c <= 1'b1;
        if( &awin ) begin                       // cada 65536 clk: latch de actividad y reinicio
            fm0_a<=fm0_c; fm1_a<=fm1_c; psg0_a<=psg0_c; psg1_a<=psg1_c;
            fm0_c<=0; fm1_c<=0; psg0_c<=0; psg1_c<=0;
        end
    end
end
assign snd_dbg2 = { ym_wr_hb, fm1_a, fm0_a, psg1_a, psg0_a };
`else
    assign rom_addr = 16'd0;
    assign rom_cs   = 1'b0;
    assign fm_dout  = 8'd0;
    assign psg0     = 10'd0;
    assign psg1     = 10'd0;
    assign fm0      = 16'd0;
    assign fm1      = 16'd0;
    assign snd_dbg  = 8'd0;
    assign snd_dbg2 = 8'd0;
    assign snd_dbg3 = 8'd0;
`endif
`ifdef SIMULATION
// ⭐ DIAGNÓSTICO (2026-07-16): en placa NO HAY MÚSICA (sí ADPCM: se oye un grito). En el sim el audio
// sale como un **DC CONSTANTE de -28416** (≈ el reposo del FM) durante 20 s: el YM está CONGELADO.
// El smoke standalone del módulo PASA (fm0 [-28609,32767], 7/7 comandos) => el fallo es de INTEGRACIÓN.
// Estas 3 medidas separan las hipótesis:
//   pc_max/pags : ¿corre el Z80 de sonido, o está atascado? (si no avanza -> ROM/SDRAM o reset)
//   n_lat       : ¿le LLEGAN comandos del main (0xc500)? (si 0 -> el main no los manda o el latch no va)
//   n_rd        : ¿la CPU los LEE? (si llegan y no los lee -> la CPU no corre)
reg [15:0] pc_max=0; reg [31:0] n_lat=0, n_rd=0, n_col=0, n_irq=0, n_irqtk=0, n_disp=0, n_pcyc=0; reg [19:0] sdbg=0;
reg [6:0] n_lrd=0; reg saw_pend=0; reg [7:0] last_cmd=0, last_pdin=0, cmd_h0=0, cmd_h1=0, cmd_h2=0, cmd_h3=0; reg [31:0] n_5be=0;
reg signed [15:0] fm0_min=16'sh7fff, fm0_max=16'sh8000;   // rango de fm0: si min==max -> DC (congelado)
reg m1_sl;
always @(posedge clk) begin
    m1_sl <= m1_n;
    if( wr_edge && latch_rd_l && !latch_rd ) n_col <= n_col + 1;  // colisiones write+clear (la race)
    if( !m1_n && m1_sl && A>pc_max && A<16'h8000 ) pc_max <= A;   // PC máximo alcanzado en ROM
    // sonda FIEL: valor que el Z80 CAPTURA al FINAL de la lectura de 0xf000 (flanco de bajada). Loguea las
    // primeras 40 lecturas -> ver si el bit7 (pendiente) llega alguna vez al Z80.
    if( latch_rd_l && !latch_rd ) begin
        if( n_lrd<7'd40 ) begin n_lrd <= n_lrd + 7'd1;
            $display("[DIN] lectura 0xf000: din=%02h fm_data=%02h t=%0t", din, fm_data, $time); end
        if( din[7] ) begin saw_pend <= 1'b1; last_pdin <= din; end   // valor que el Z80 lee (comando + bit7)
    end
    if( fm_data[7] ) n_pcyc <= n_pcyc + 1;   // ciclos con bit7=1 (¿se pone y cuánto dura?)
    if( wr_edge ) begin last_cmd <= snd_latch;                  // valor que el MAIN escribió a 0xc500
        cmd_h0<=snd_latch; cmd_h1<=cmd_h0; cmd_h2<=cmd_h1; cmd_h3<=cmd_h2; end  // historial últimos 4
    if( !m1_n && m1_sl && A==16'h05be ) n_5be <= n_5be + 1;     // ¿el Z80 llega a la rutina FM de MAME?
    // ¿el Z80 TOMA la IRQ (fetch M1 en el vector IM1 0x0038)? y ¿cuántas veces se asserta?
    if( snd_int & ~snd_int_l ) n_irq <= n_irq + 1;
    if( !m1_n && m1_sl && A==16'h0038 ) begin n_irqtk <= n_irqtk + 1;
        if( n_irqtk<3 ) $display("[IRQ] Z80 entra handler 0x0038 (#%0d) t=%0t", n_irqtk, $time); end
    // ¿el Z80 entra en la región de dispatch/FM de MAME (0x0273..0x05be)?
    if( !m1_n && m1_sl && A>=16'h0200 && A<16'h0700 ) begin n_disp <= n_disp + 1;
        if( n_disp<5 ) $display("[DISP] Z80 M1 en region FM @%04h t=%0t", A, $time); end
    if( wr_edge ) n_lat <= n_lat + 1;                              // comandos que ENTRAN al latch
    if( latch_cs && !latch_rd_l ) n_rd <= n_rd + 1;                // lecturas de 0xf000 por la CPU
    if( $signed(fm0) < fm0_min ) fm0_min <= fm0;
    if( $signed(fm0) > fm0_max ) fm0_max <= fm0;
    // log de cada escritura del Z80 al YM (addr-reg vs data-reg) para comparar con MAME
    if( ymwr && !ymwr_l )
        $display("[YMW] %s a0=%b din=%02h  cmd=%02h  t=%0t",
                 fm0_cs?"YM0":"YM1", A[0], dout, fm_data, $time);
    sdbg <= sdbg + 1;
    if( sdbg==20'd0 )
        $display("[SND] lat_in=%0d n5be=%0d saw_pend=%b cmds=[%02h %02h %02h %02h] pdin=%02h | div=%b%b fm0=[%d,%d]",
                 n_lat, n_5be, saw_pend, cmd_h3, cmd_h2, cmd_h1, cmd_h0, last_pdin, ym0_dbg[1:0], ym1_dbg[1:0], fm0_min, fm0_max);
end
`endif
endmodule
