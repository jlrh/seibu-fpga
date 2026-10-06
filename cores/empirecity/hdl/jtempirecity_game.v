module jtempirecity_game(
    `include "jtframe_game_ports.inc"
);

wire [12:0] cpu_addr;
wire [ 7:0] cpu_dout, vram_dout, pal_dout, spr_dout, vreg_dout;
wire [ 9:0] sprbank;
wire        cpu_rnw, vram_cs, pal_cs, vreg_cs, spr_cs;
wire        flip, black_n;

wire [ 7:0] snd_latch;
wire        snd_wr, snd_rd, fm_wr;
wire [ 7:0] fm_dout;
wire [ 7:0] snd_dbg;
wire [ 7:0] snd_dbg2;
wire [ 7:0] snd_dbg3;

wire [ 7:0] cpu2mcu;
wire        mcu_we, mcu_nmi_n;
wire [ 1:0] coin_valid;
wire [ 7:0] adpcm_start;
wire        adpcm_rst, mcu_irq;

wire [ 7:0] dipsw_a, dipsw_b;
assign { dipsw_b, dipsw_a } = dipsw[15:0];
assign dip_flip = flip;

reg  [3:0] hb_latch;
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
    2'd0:    dbgv = { hb_latch, snd_dbg[3:0] };
    2'd1:    dbgv = snd_dbg;
    2'd2:    dbgv = snd_dbg2;
    default: dbgv = snd_dbg3;
endcase
assign debug_view = dbgv;

assign pxl_cen  = cen6;
assign pxl2_cen = cen12;

/* verilator tracing_off */
`ifndef NOMAIN
empirecity_main u_main(
    .rst        ( rst        ),  .clk        ( clk        ),
    .cen3       ( cen3       ),

    .main_addr  ( main_addr  ),  .main_cs    ( main_cs    ),
    .main_data  ( main_data  ),  .main_ok    ( main_ok    ),

    .cab_1p     ( cab_1p[1:0]),  .coin       ( coin[1:0]  ),
    .joystick1  ( joystick1  ),  .joystick2  ( joystick2  ),
    .service    ( service    ),
    .dipsw_a    ( dipsw_a    ),  .dipsw_b    ( dipsw_b    ),

    .cpu_addr   ( cpu_addr   ),  .cpu_dout   ( cpu_dout   ),  .cpu_rnw ( cpu_rnw ),
    .vram_cs    ( vram_cs    ),  .vram_dout  ( vram_dout  ),
    .pal_cs     ( pal_cs     ),  .pal_dout   ( pal_dout   ),
    .vreg_cs    ( vreg_cs    ),  .spr_cs     ( spr_cs     ),
    .vreg_dout  ( vreg_dout  ),  .spr_dout   ( spr_dout   ),  .sprbank_o ( sprbank ),
    .flip       ( flip       ),  .LVBL       ( LVBL       ),

    .snd_latch  ( snd_latch  ),  .snd_wr     ( snd_wr     ),
    .fm_wr      ( fm_wr      ),  .fm_dout    ( fm_dout    ),

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

    .cpu_addr   ( cpu_addr   ),  .cpu_dout   ( cpu_dout   ),  .cpu_rnw ( cpu_rnw ),
    .vram_cs    ( vram_cs    ),  .vram_dout  ( vram_dout  ),
    .pal_cs     ( pal_cs     ),  .pal_dout   ( pal_dout   ),
    .vreg_cs    ( vreg_cs    ),  .spr_cs     ( spr_cs     ),
    .vreg_dout  ( vreg_dout  ),  .spr_dout   ( spr_dout   ),  .sprbank ( sprbank ),

    .fgmap_addr ( fgmap_addr ),  .fgmap_data ( fgmap_data ),  .fgmap_cs ( fgmap_cs ), .fgmap_ok ( fgmap_ok ),
    .bgmap_addr ( bgmap_addr ),  .bgmap_data ( bgmap_data ),  .bgmap_cs ( bgmap_cs ), .bgmap_ok ( bgmap_ok ),
    .fgrom_addr ( fgrom_addr ),  .fgrom_data ( fgrom_data ),  .fgrom_cs ( fgrom_cs ), .fgrom_ok ( fgrom_ok ),
    .bgrom_addr ( bgrom_addr ),  .bgrom_data ( bgrom_data ),  .bgrom_cs ( bgrom_cs ), .bgrom_ok ( bgrom_ok ),
    .objrom_addr( objrom_addr),  .objrom_data( objrom_data),  .objrom_cs( objrom_cs), .objrom_ok( objrom_ok),

    .red        ( red        ),  .green      ( green      ),  .blue      ( blue      ),
    .gfx_en     ( gfx_en     ),

    .prog_addr  ( prog_addr  ),  .prog_data  ( prog_data  ),  .prom_we   ( prom_we   )
);

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
