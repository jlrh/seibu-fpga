/*  Empire City: 1931 / Street Fight (Seibu, 1986) — core FPGA (jtframe).
    GAMETOP interno. Estructura clonada de bubl (68705) + trojan (2xYM2203+MSM5205).
    Contrato jtframe: puertos via jtframe_game_ports.inc; buses de mem.yaml conectados por nombre.
    GPLv3 — credito a Jose Tejada (jotego) / JTFRAME. */
module jtempirecity_game(
    `include "jtframe_game_ports.inc"
);

// ---- CPU principal <-> video ----
wire [12:0] cpu_addr;
wire [ 7:0] cpu_dout, vram_dout, pal_dout, spr_dout, vreg_dout;
wire [ 9:0] sprbank;
wire        cpu_rnw, vram_cs, pal_cs, vreg_cs, spr_cs;
wire        flip, black_n;
// ---- sonido ----
wire [ 7:0] snd_latch;
wire        snd_wr, snd_rd, fm_wr;
wire [ 7:0] fm_dout;
wire [ 7:0] snd_dbg;      // signos vitales del Z80 de sonido (debug)
wire [ 7:0] snd_dbg2;     // actividad del YM: ¿el Z80 lo escribe? ¿produce salida?
wire [ 7:0] snd_dbg3;     // banco 03: amplitud pico FM (nibble alto) + div_setting (nibble bajo)
// ---- MCU 68705 ----
wire [ 7:0] cpu2mcu;
wire        mcu_we, mcu_nmi_n;
wire [ 1:0] coin_valid;   // moneda validada por la MCU -> baja coin_state en el main
wire [ 7:0] adpcm_start;  // dir alta del sample ADPCM (port A de la MCU)
wire        adpcm_rst, mcu_irq;
// ---- DIPs / cabina ----
wire [ 7:0] dipsw_a, dipsw_b;
assign { dipsw_b, dipsw_a } = dipsw[15:0];
assign dip_flip = flip;

// ================== DEBUG EN PLACA (JTFRAME_RELEASE off) ==================
// Objetivo: separar "el Z80 de sonido se cuelga" de "el main deja de mandar comandos".
// En placa: teclas +/- cambian debug_bus; el valor se ve en pantalla en BINARIO (blanco).
// 3 vistas, se eligen con debug_bus[1:0] (teclas +/- en placa):
//   =0 (0x00) -> HEARTBEAT: nibble ALTO=comandos del main; nibble BAJO=fetches del Z80 sonido.
//               ambos contando=ambos vivos; alto parado=main paró; bajo parado=Z80 colgado.
//   =1 (0x01) -> FLAGS Z80: {wait_n, rom_lock, int_n, fm_lock, hb_m1}. wait_n=0+rom_lock=1 fijos=SDRAM.
//   =2 (0x02) -> YM (LA DECISIVA AHORA): nibble ALTO=ym_wr_hb (escrituras del Z80 al YM),
//               nibble BAJO={fm1_act,fm0_act,psg1_act,psg0_act} (esa salida del YM CAMBIÓ = produce señal).
//               · ym_wr_hb CUENTA + act=0 -> el Z80 escribe pero el YM NO produce (jt03: reloj/prescaler).
//               · ym_wr_hb CUENTA + act=1 -> el YM produce -> el fallo es salida/DAC (no el YM ni el mixer).
//               · ym_wr_hb NO cuenta      -> el Z80 no llega a escribir el YM (decode).
reg  [3:0] hb_latch;   // heartbeat de comandos del main al latch de sonido
reg        snd_wr_dl;
always @(posedge clk or posedge rst) begin
    if( rst ) begin hb_latch <= 4'd0; snd_wr_dl <= 1'b0; end
    else begin
        snd_wr_dl <= snd_wr;
        if( snd_wr && !snd_wr_dl ) hb_latch <= hb_latch + 4'd1;
    end
end
reg [7:0] dbgv;
always @(*) case( debug_bus[1:0] )
    2'd0:    dbgv = { hb_latch, snd_dbg[3:0] };  // heartbeats
    2'd1:    dbgv = snd_dbg;                       // flags Z80
    2'd2:    dbgv = snd_dbg2;                      // YM: escrituras + actividad
    default: dbgv = snd_dbg3;                      // 03: amplitud pico FM (alto) + div_setting (bajo)
endcase
assign debug_view = dbgv;

// pixel clock enables (el game los GENERA; jtframe los usa en su pipeline de video). El pixel clock
// de stfight ~6 MHz -> pxl_cen=cen6, pxl2_cen=cen12 (12 MHz). Sin esto el sim se queda clavado en
// frame 0 (los contadores de empirecity_video corren con pxl_cen y VS nunca pulsa). Ver HANDOFF 2c.3b.
assign pxl_cen  = cen6;
assign pxl2_cen = cen12;

/* verilator tracing_off */
`ifndef NOMAIN
empirecity_main u_main(
    .rst        ( rst        ),  .clk        ( clk        ),
    .cen3       ( cen3       ),
    // ROM Z80 principal
    .main_addr  ( main_addr  ),  .main_cs    ( main_cs    ),
    .main_data  ( main_data  ),  .main_ok    ( main_ok    ),
    // cabina
    .cab_1p     ( cab_1p[1:0]),  .coin       ( coin[1:0]  ),
    .joystick1  ( joystick1  ),  .joystick2  ( joystick2  ),
    .service    ( service    ),
    .dipsw_a    ( dipsw_a    ),  .dipsw_b    ( dipsw_b    ),
    // video (RAM interna del juego)
    .cpu_addr   ( cpu_addr   ),  .cpu_dout   ( cpu_dout   ),  .cpu_rnw ( cpu_rnw ),
    .vram_cs    ( vram_cs    ),  .vram_dout  ( vram_dout  ),
    .pal_cs     ( pal_cs     ),  .pal_dout   ( pal_dout   ),
    .vreg_cs    ( vreg_cs    ),  .spr_cs     ( spr_cs     ),
    .vreg_dout  ( vreg_dout  ),  .spr_dout   ( spr_dout   ),  .sprbank_o ( sprbank ),
    .flip       ( flip       ),  .LVBL       ( LVBL       ),
    // sonido
    .snd_latch  ( snd_latch  ),  .snd_wr     ( snd_wr     ),
    .fm_wr      ( fm_wr      ),  .fm_dout    ( fm_dout    ),
    // MCU
    .cpu2mcu    ( cpu2mcu    ),  .mcu_we     ( mcu_we     ),
    .coin_valid ( coin_valid ),  .mcu_nmi_n  ( mcu_nmi_n  ),
    .dip_pause  ( dip_pause  )
);
`else
assign main_cs=0; assign cpu_rnw=1; assign vram_cs=0; assign pal_cs=0; assign flip=0;
assign spr_cs=0; assign vreg_cs=0; assign sprbank=0; assign cpu_addr=0; assign cpu_dout=0;
`endif
/* verilator tracing_on */

empirecity_video u_video(
    .rst        ( rst        ),  .clk        ( clk        ),
    .pxl2_cen   ( pxl2_cen   ),  .pxl_cen    ( pxl_cen    ),
    .LHBL       ( LHBL       ),  .LVBL       ( LVBL       ),
    .HS         ( HS         ),  .VS         ( VS         ),
    .flip       ( flip       ),
    // interfaz CPU
    .cpu_addr   ( cpu_addr   ),  .cpu_dout   ( cpu_dout   ),  .cpu_rnw ( cpu_rnw ),
    .vram_cs    ( vram_cs    ),  .vram_dout  ( vram_dout  ),
    .pal_cs     ( pal_cs     ),  .pal_dout   ( pal_dout   ),
    .vreg_cs    ( vreg_cs    ),  .spr_cs     ( spr_cs     ),
    .vreg_dout  ( vreg_dout  ),  .spr_dout   ( spr_dout   ),  .sprbank ( sprbank ),
    // SDRAM gfx
    .fgmap_addr ( fgmap_addr ),  .fgmap_data ( fgmap_data ),  .fgmap_cs ( fgmap_cs ), .fgmap_ok ( fgmap_ok ),
    .bgmap_addr ( bgmap_addr ),  .bgmap_data ( bgmap_data ),  .bgmap_cs ( bgmap_cs ), .bgmap_ok ( bgmap_ok ),
    .fgrom_addr ( fgrom_addr ),  .fgrom_data ( fgrom_data ),  .fgrom_cs ( fgrom_cs ), .fgrom_ok ( fgrom_ok ),
    .bgrom_addr ( bgrom_addr ),  .bgrom_data ( bgrom_data ),  .bgrom_cs ( bgrom_cs ), .bgrom_ok ( bgrom_ok ),
    .objrom_addr( objrom_addr),  .objrom_data( objrom_data),  .objrom_cs( objrom_cs), .objrom_ok( objrom_ok),
    // salida de color
    .red        ( red        ),  .green      ( green      ),  .blue      ( blue      ),
    .gfx_en     ( gfx_en     ),
    // carga de PROMs (tx gfx + 4 CLUTs) desde el download de jtframe
    .prog_addr  ( prog_addr  ),  .prog_data  ( prog_data  ),  .prom_we   ( prom_we   )
);
// Las PROMs (tx gfx + CLUTs) las carga empirecity_video de su propio download (prom_we/prog_addr).
// Las BRAM que instancia el wrapper de jtframe quedan SIN USAR (Quartus las poda): direcciones a 0.
// ⚠ ESTA LISTA DEBE SEGUIR A `cfg/mem.yaml` (bram:). Si anades/renombras una PROM alli y no aqui,
// el simulador NO da error: crea la senal IMPLICITAMENTE y solo suelta un aviso perdido entre cientos:
//   %Warning-IMPLICIT: Signal definition not found, creating implicitly: 'fgclut_addr'
// ...y el wrapper se queda con su puerto colgando. Paso el 2026-07-16 al partir las CLUT en hi/lo.
// ⚠⚠ Y NO empieces una linea de comentario con la palabra "verilator": la toma por METADIRECTIVA
//    (`%Error: Unknown verilator comment`). Tambien paso, 5 min despues.
assign txrom_addr     = 13'd0;
assign txclut_addr    = 8'd0;
assign fgclut_hi_addr = 8'd0;
assign fgclut_lo_addr = 8'd0;
assign bgclut_hi_addr = 8'd0;
assign bgclut_lo_addr = 8'd0;
assign sprclut_hi_addr= 8'd0;
assign sprclut_lo_addr= 8'd0;

/* verilator tracing_off */
`ifndef NOSOUND
empirecity_sound u_sound(
    .rst        ( rst        ),  .clk        ( clk        ),
    .cen3       ( cen3       ),  .cen1p5     ( cen1p5     ),
    .snd_latch  ( snd_latch  ),  .snd_wr     ( snd_wr     ),
    .fm_wr      ( fm_wr      ),  .fm_dout    ( fm_dout    ),
    .rom_addr   ( snd_addr   ),  .rom_cs     ( snd_cs     ),
    .rom_data   ( snd_data   ),  .rom_ok     ( snd_ok     ),
    .psg0       ( psg0       ),  .psg1       ( psg1       ),
    .fm0        ( fm0        ),  .fm1        ( fm1        ),
    .snd_dbg    ( snd_dbg    ),  .snd_dbg2   ( snd_dbg2   ),
    .snd_dbg3   ( snd_dbg3   )
);
empirecity_mcu u_mcu(
    .rst        ( rst        ),  .clk        ( clk        ),  .cen3 ( cen3 ),
    .cpu2mcu    ( cpu2mcu    ),  .mcu_we     ( mcu_we     ),
    .mcu_nmi_n  ( mcu_nmi_n  ),  .coin_valid ( coin_valid ),
    .coin       ( coin[1:0]  ),
    .adpcm_start( adpcm_start),  .adpcm_rst  ( adpcm_rst  ),  .mcu_irq ( mcu_irq ),
    // ROM interna (BRAM prom)
    .rom_addr   ( mcu_addr   ),  .rom_data   ( mcu_data   )
);
empirecity_adpcm u_adpcm(
    .rst        ( rst        ),  .clk        ( clk        ),  .cenp384 ( cenp384 ),
    .start_hi   ( adpcm_start),  .adpcm_rst  ( adpcm_rst  ),  .mcu_irq ( mcu_irq ),
    .rom_addr   ( adpcm_addr ), .rom_cs  ( adpcm_cs   ), .rom_data( adpcm_data ), .rom_ok( adpcm_ok ),
    .pcm        ( pcm        )
);
`else
assign snd_cs=0; assign snd_addr=0; assign psg0=0; assign psg1=0; assign fm0=0; assign fm1=0; assign pcm=0;
assign snd_dbg=0; assign snd_dbg2=0;
`endif
/* verilator tracing_on */

endmodule
