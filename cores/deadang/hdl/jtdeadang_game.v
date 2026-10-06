module jtdeadang_game(
    `include "jtframe_game_ports.inc"
);

assign pxl_cen  = cen6;
assign pxl2_cen = cen12;

wire [15:0] p1p2 = { cab_1p[0], cab_1p[1], joystick2[5:4], joystick2[3:0],
                     2'b11, joystick1[5:4], joystick1[3:0] };

wire [15:0] dsw  = { dipsw[15:6], dipsw[5] & service, dipsw[4:0] };

reg  [1:0] coin_imp;
reg  [1:0] coin_l, coin_arm;
reg  [2:0] coin_cnt0, coin_cnt1;
reg        lvbl_l;
always @(posedge clk) begin
    if( rst ) begin
        coin_imp <= 0; coin_l <= 2'b11; coin_arm <= 0; coin_cnt0 <= 0; coin_cnt1 <= 0; lvbl_l <= 0;
    end else begin
        coin_l <= coin[1:0];
        lvbl_l <= LVBL;
        if( coin[0] ) coin_arm[0] <= 1;
        if( coin[1] ) coin_arm[1] <= 1;
        if( coin_arm[0] && !coin[0] && coin_l[0] ) coin_cnt0 <= 3'd4;
        if( coin_arm[1] && !coin[1] && coin_l[1] ) coin_cnt1 <= 3'd4;
        if( !LVBL && lvbl_l ) begin
            if( coin_cnt0 != 0 ) coin_cnt0 <= coin_cnt0 - 3'd1;
            if( coin_cnt1 != 0 ) coin_cnt1 <= coin_cnt1 - 3'd1;
        end
        coin_imp <= { coin_cnt1 != 0, coin_cnt0 != 0 };
    end
end

wire        irq_l240, irq_l0;
wire [11:1] msh_addr, ssh_addr;
wire [15:0] msh_din, ssh_din, msh_dout, ssh_dout;
wire  [1:0] msh_we, ssh_we;
wire        lock, sub_wait, ssh_cs;
wire  [2:0] snd_m_addr;
wire  [7:0] snd_m_din, snd_m_dout;
wire        snd_m_wr, snd_m_rd;
wire  [9:0] vtxt_addr, vspr_addr, vpf1_addr;
wire [10:0] vpal_addr;
wire [15:0] vtxt_data, vspr_data, vpal_data, vpf1_data;
wire  [7:0] scr01, scr02, scr09, scr0a, scr11, scr12, scr19, scr1a,
            scr21, scr22, scr29, scr2a, ctl34;
wire        spr_dma, tilebank, wdog;
wire [19:0] main_dbg, sub_dbg;

assign dip_flip = ctl34[6];

deadang_main u_main(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .cpu_cen    ( cpu_cen    ),
    .rom_addr   ( main_addr  ),
    .rom_cs     ( main_cs    ),
    .rom_data   ( main_data  ),
    .rom_ok     ( main_ok    ),
    .irq_l240   ( irq_l240   ),
    .irq_l0     ( irq_l0     ),
    .sh_addr    ( msh_addr   ),
    .sh_din     ( msh_din    ),
    .sh_we      ( msh_we     ),
    .sh_dout    ( msh_dout   ),
    .lock       ( lock       ),
    .snd_addr   ( snd_m_addr ),
    .snd_din    ( snd_m_din  ),
    .snd_wr     ( snd_m_wr   ),
    .snd_rd     ( snd_m_rd   ),
    .snd_dout   ( snd_m_dout ),
    .vtxt_addr  ( vtxt_addr  ), .vtxt_dout( vtxt_data ),
    .vspr_addr  ( vspr_addr  ), .vspr_dout( vspr_data ),
    .vpal_addr  ( vpal_addr  ), .vpal_dout( vpal_data ),
    .scr01(scr01), .scr02(scr02), .scr09(scr09), .scr0a(scr0a),
    .scr11(scr11), .scr12(scr12), .scr19(scr19), .scr1a(scr1a),
    .scr21(scr21), .scr22(scr22), .scr29(scr29), .scr2a(scr2a),
    .ctl34      ( ctl34      ),
    .spr_dma    ( spr_dma    ),
    .p1p2       ( p1p2       ),
    .dsw        ( dsw        ),
    .dbg_addr   ( main_dbg   )
);

deadang_sub u_sub(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .cpu_cen    ( cpu_cen    ),
    .rom_addr   ( sub_addr   ),
    .rom_cs     ( sub_cs     ),
    .rom_data   ( sub_data   ),
    .rom_ok     ( sub_ok     ),
    .irq_l240   ( irq_l240   ),
    .irq_l0     ( irq_l0     ),
    .sh_addr    ( ssh_addr   ),
    .sh_din     ( ssh_din    ),
    .sh_we      ( ssh_we     ),
    .sh_cs      ( ssh_cs     ),
    .sh_dout    ( ssh_dout   ),
    .sh_wait    ( sub_wait   ),
    .vpf1_addr  ( vpf1_addr  ),
    .vpf1_dout  ( vpf1_data  ),
    .tilebank   ( tilebank   ),
    .wdog       ( wdog       ),
    .dbg_addr   ( sub_dbg    )
);

deadang_shared u_shared(
    .clk        ( clk        ),
    .lock       ( lock       ),
    .main_addr  ( msh_addr   ),
    .main_din   ( msh_din    ),
    .main_we    ( msh_we     ),
    .main_dout  ( msh_dout   ),
    .sub_addr   ( ssh_addr   ),
    .sub_din    ( ssh_din    ),
    .sub_we     ( ssh_we     ),
    .sub_dout   ( ssh_dout   ),
    .sub_wait   ( sub_wait   )
);

wire [7:0] snd_dbg;
`ifndef NOSOUND
deadang_sound u_sound(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .cen_fm     ( cen_fm     ),
    .cen375     ( cen375     ),
    .m_addr     ( snd_m_addr ),
    .m_din      ( snd_m_din  ),
    .m_wr       ( snd_m_wr   ),
    .m_rd       ( snd_m_rd   ),
    .m_dout     ( snd_m_dout ),
    .coin       ( coin_imp   ),
    .rom_addr   ( snd_addr   ),
    .rom_cs     ( snd_cs     ),
    .rom_data   ( snd_data   ),
    .rom_ok     ( snd_ok     ),
    .pcm0_addr  ( pcm0_addr  ), .pcm0_cs( pcm0_cs ), .pcm0_data( pcm0_data ), .pcm0_ok( pcm0_ok ),
    .pcm1_addr  ( pcm1_addr  ), .pcm1_cs( pcm1_cs ), .pcm1_data( pcm1_data ), .pcm1_ok( pcm1_ok ),
    .fm0        ( fm0        ), .fm1 ( fm1  ),
    .psg0       ( psg0       ), .psg1( psg1 ),
    .pcm0       ( pcm0       ), .pcm1( pcm1 ),
    .dbg        ( snd_dbg    )
);
`else
assign snd_m_dout = 8'hFF; assign snd_cs = 0; assign snd_addr = 0;
assign pcm0_cs = 0; assign pcm0_addr = 0; assign pcm1_cs = 0; assign pcm1_addr = 0;
assign fm0 = 0; assign fm1 = 0; assign psg0 = 0; assign psg1 = 0; assign pcm0 = 0; assign pcm1 = 0;
assign snd_dbg = 0;
`endif

wire [14:0] map1_addr, map2_addr;
assign map1hi_addr = map1_addr;
assign map1lo_addr = map1_addr;
assign map2hi_addr = map2_addr;
assign map2lo_addr = map2_addr;

deadang_video u_video(
    .rst        ( rst        ),
    .clk        ( clk        ),
    .pxl_cen    ( cen6       ),
    .scr01_i(scr01), .scr02_i(scr02), .scr09_i(scr09), .scr0a_i(scr0a),
    .scr11_i(scr11), .scr12_i(scr12), .scr19_i(scr19), .scr1a_i(scr1a),
    .scr21_i(scr21), .scr22_i(scr22), .scr29_i(scr29), .scr2a_i(scr2a),
    .ctl34_i      ( ctl34      ),
    .tilebank_i   ( tilebank   ), .spr_dma(spr_dma),
    .vtxt_addr  ( vtxt_addr  ), .vtxt_data( vtxt_data ),
    .vspr_addr  ( vspr_addr  ), .vspr_data( vspr_data ),
    .vpal_addr  ( vpal_addr  ), .vpal_data( vpal_data ),
    .vpf1_addr  ( vpf1_addr  ), .vpf1_data( vpf1_data ),
    .map1_addr  ( map1_addr  ), .map1_data( { map1hi_data, map1lo_data } ),
    .map2_addr  ( map2_addr  ), .map2_data( { map2hi_data, map2lo_data } ),
    .char_addr  ( chars_addr ), .char_data( chars_data ),
    .pf1rom_addr( pf1rom_addr), .pf1rom_cs( pf1rom_cs ), .pf1rom_data( pf1rom_data ), .pf1rom_ok( pf1rom_ok ),
    .pf2rom_addr( pf2rom_addr), .pf2rom_cs( pf2rom_cs ), .pf2rom_data( pf2rom_data ), .pf2rom_ok( pf2rom_ok ),
    .pf3rom_addr( pf3rom_addr), .pf3rom_cs( pf3rom_cs ), .pf3rom_data( pf3rom_data ), .pf3rom_ok( pf3rom_ok ),
    .objrom_addr( objrom_addr), .objrom_cs( objrom_cs ), .objrom_data( objrom_data ), .objrom_ok( objrom_ok ),
    .irq_l240   ( irq_l240   ),
    .irq_l0     ( irq_l0     ),
    .LHBL       ( LHBL       ),
    .LVBL       ( LVBL       ),
    .HS         ( HS         ),
    .VS         ( VS         ),
    .red        ( red        ),
    .green      ( green      ),
    .blue       ( blue       ),
    .gfx_en     ( gfx_en     )
);

`ifdef SIMULATION

reg lvbl_d = 0; integer simframe = 0;
always @(posedge clk) begin
    lvbl_d <= LVBL;
    if( !LVBL && lvbl_d ) begin
        simframe = simframe + 1;
        $display("SIMF %0d main=%05X sub=%05X ctl34=%02X lock=%0d main_cs=%0d main_ok=%0d sub_cs=%0d sub_ok=%0d",
            simframe, main_dbg, sub_dbg, ctl34, lock, main_cs, main_ok, sub_cs, sub_ok);
    end
end
`endif

reg [7:0] dbgv;
always @(*) case( debug_bus[1:0] )
    2'd0: dbgv = main_dbg[19:12];
    2'd1: dbgv = sub_dbg[19:12];
    2'd2: dbgv = snd_dbg;
    default: dbgv = ctl34;
endcase
assign debug_view = dbgv;

endmodule
