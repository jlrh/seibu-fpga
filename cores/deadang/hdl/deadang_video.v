/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_video -- timing + line renderers + priority mixer + palette (MAME deadang.cpp:329-363).
    Timing: 6 MHz pixel clock, 390 x 256 (15.38 kHz / 60.1 Hz; PCB: 15.37 kHz / 60 Hz, HTOTAL
    not documented -- GAPS O6). Lines are numbered like MAME's screen (0..255), visible 16..239,
    x 0..255. IRQs (to both V30): start of line 240 (vector 0x31) and line 0 (vector 0x32).
    Line v+1 is rendered during line v into the back half of every line buffer.
    Flip (ctl34 bit 6) = mirror of the unflipped frame: render line 255-v and read x as 255-x.
    Mixer (pri values as MAME's priority bitmap: PF3=1, PF1=2, PF2=4):
      PF3 opaque, PF1/PF2/text/sprites pen 15 transparent; sprite class w2[15:14]:
      00 hidden by PF1/PF2 pixels, 01 hidden by PF2 pixels, 1x never hidden. Text on top.
      Palette bases: PF3 0, PF2 256, text 512, sprites 768, PF1 1024. xBGR_444.
*/

module deadang_video(
    input             rst,
    input             clk,
    input             pxl_cen,

    input       [7:0] scr01_i, scr02_i, scr09_i, scr0a_i, scr11_i, scr12_i, scr19_i, scr1a_i,
                      scr21_i, scr22_i, scr29_i, scr2a_i,
    input       [7:0] ctl34_i,
    input             tilebank_i,
    input             spr_dma,

    output      [9:0] vtxt_addr,  input [15:0] vtxt_data,
    output reg  [9:0] vspr_addr,  input [15:0] vspr_data,
    output     [10:0] vpal_addr,  input [15:0] vpal_data,
    output      [9:0] vpf1_addr,  input [15:0] vpf1_data,

    output     [14:0] map1_addr,  input [15:0] map1_data,
    output     [14:0] map2_addr,  input [15:0] map2_data,
    output     [14:0] char_addr,  input  [7:0] char_data,

    output     [17:0] pf1rom_addr, output pf1rom_cs, input [31:0] pf1rom_data, input pf1rom_ok,
    output     [15:0] pf2rom_addr, output pf2rom_cs, input [31:0] pf2rom_data, input pf2rom_ok,
    output     [15:0] pf3rom_addr, output pf3rom_cs, input [31:0] pf3rom_data, input pf3rom_ok,
    output     [16:0] objrom_addr, output objrom_cs, input [31:0] objrom_data, input objrom_ok,

    output reg        irq_l240,
    output reg        irq_l0,

    output reg        LHBL,
    output reg        LVBL,
    output reg        HS,
    output reg        VS,
    output reg  [3:0] red,
    output reg  [3:0] green,
    output reg  [3:0] blue,
    input       [3:0] gfx_en
);

reg [8:0] hcnt;
reg [7:0] vcnt;
reg       front;
reg       lstart;
reg [3:0] ph;
reg [10:0] pal_idx;
reg       black, vis;

always @(posedge clk) begin
    if( rst ) begin
        hcnt <= 0; vcnt <= 8'd0; front <= 0; lstart <= 0;
        irq_l240 <= 0; irq_l0 <= 0;
        LHBL <= 0; LVBL <= 0; HS <= 0; VS <= 0;
    end else begin
        lstart <= 0; irq_l240 <= 0; irq_l0 <= 0;
        if( pxl_cen ) begin
            if( hcnt == 9'd389 ) begin
                hcnt  <= 0;
                vcnt  <= vcnt + 8'd1;
                front <= ~front;
                lstart <= 1;
                if( vcnt + 8'd1 == 8'd240 ) irq_l240 <= 1;
                if( vcnt == 8'd255 )        irq_l0   <= 1;
            end else hcnt <= hcnt + 9'd1;

            LHBL <= vis;
            LVBL <= vcnt >= 8'd16 && vcnt < 8'd240;
            HS   <= hcnt >= 9'd300 && hcnt < 9'd332;
            VS   <= vcnt >= 8'd244 && vcnt < 8'd247;
        end
    end
end

reg  [7:0] scr01, scr02, scr09, scr0a, scr11, scr12, scr19, scr1a,
           scr21, scr22, scr29, scr2a, ctl34;
reg        tilebank;
wire       frame_latch = lstart && vcnt == 8'd240;

always @(posedge clk) begin
    if( rst ) begin
        { scr01, scr02, scr09, scr0a, scr11, scr12, scr19, scr1a,
          scr21, scr22, scr29, scr2a, ctl34 } <= 0;
        tilebank <= 0;
    end else if( frame_latch ) begin
        { scr01, scr02, scr09, scr0a, scr11, scr12, scr19, scr1a, scr21, scr22, scr29, scr2a } <=
        { scr01_i, scr02_i, scr09_i, scr0a_i, scr11_i, scr12_i, scr19_i, scr1a_i,
          scr21_i, scr22_i, scr29_i, scr2a_i };
        ctl34    <= ctl34_i;
        tilebank <= tilebank_i;
    end
end

reg        cp_on, cp_new, sdisp;
reg [10:0] cp_d;
wire [9:0] sbuf_addr;
wire [15:0] sbuf_data;

always @(posedge clk) begin
    if( rst ) begin
        cp_on <= 0; cp_new <= 0; sdisp <= 0; vspr_addr <= 0; cp_d <= 0;
    end else begin
        cp_d <= { cp_on, vspr_addr };
        if( spr_dma ) begin
            cp_on <= 1; cp_new <= 0; vspr_addr <= 0;
        end else if( cp_on ) begin
            vspr_addr <= vspr_addr + 10'd1;
            if( vspr_addr == 10'h3FF ) begin cp_on <= 0; cp_new <= 1; end
        end
        if( frame_latch && cp_new && !cp_on ) begin sdisp <= ~sdisp; cp_new <= 0; end
    end
end

jtframe_dual_ram16 #(.AW(11)) u_sprbuf(
    .clk0 ( clk ), .data0( vspr_data ), .addr0( { ~sdisp, cp_d[9:0] } ), .we0( {2{cp_d[10]}} ), .q0(),
    .clk1 ( clk ), .data1( 16'd0     ), .addr1( {  sdisp, sbuf_addr } ), .we1( 2'b0 ),         .q1( sbuf_data )
);

function [11:0] sc12( input [7:0] h, input [7:0] l );
    sc12 = { h[7:4], 8'd0 } + { 3'd0, l[6:0], 1'b0 } + { 11'd0, l[7] };
endfunction
function [11:0] sc9( input [7:0] h, input [7:0] l );
    sc9 = { 3'd0, h[4], 8'd0 } + { 3'd0, l[6:0], 1'b0 } + { 11'd0, l[7] };
endfunction

wire flip = ctl34[6];

wire [7:0] vnext = vcnt + 8'd1;
wire [7:0] rline = flip ? ~vnext : vnext;

wire [7:0] pf3_ba, pf1_ba, pf2_ba, txt_ba, obj_ba;
wire [7:0] pf3_bd, pf1_bd, pf2_bd, txt_bd;
wire [9:0] obj_bd;
wire       pf3_we, pf1_we, pf2_we, txt_we, obj_we;
wire       pf3_busy, pf2_busy, pf1_busy, txt_busy, obj_busy;
wire [14:0] pf1_map;

deadang_tilemap #(.ROMMAP(1),.RW(16)) u_pf3(
    .rst(rst), .clk(clk), .start(lstart), .line(rline),
    .scrx(sc12(scr09,scr0a)), .scry(sc12(scr01,scr02)), .bank(1'b0),
    .map_addr(map1_addr), .map_data(map1_data),
    .rom_addr(pf3rom_addr), .rom_cs(pf3rom_cs), .rom_data(pf3rom_data), .rom_ok(pf3rom_ok),
    .buf_addr(pf3_ba), .buf_data(pf3_bd), .buf_we(pf3_we), .busy(pf3_busy)
);
deadang_tilemap #(.ROMMAP(1),.RW(16)) u_pf2(
    .rst(rst), .clk(clk), .start(lstart), .line(rline),
    .scrx(sc12(scr29,scr2a)), .scry(sc12(scr21,scr22)), .bank(1'b0),
    .map_addr(map2_addr), .map_data(map2_data),
    .rom_addr(pf2rom_addr), .rom_cs(pf2rom_cs), .rom_data(pf2rom_data), .rom_ok(pf2rom_ok),
    .buf_addr(pf2_ba), .buf_data(pf2_bd), .buf_we(pf2_we), .busy(pf2_busy)
);
deadang_tilemap #(.ROMMAP(0),.RW(18)) u_pf1(
    .rst(rst), .clk(clk), .start(lstart), .line(rline),
    .scrx(sc9(scr19,scr1a)), .scry(sc9(scr11,scr12)), .bank(tilebank),
    .map_addr(pf1_map), .map_data(vpf1_data),
    .rom_addr(pf1rom_addr), .rom_cs(pf1rom_cs), .rom_data(pf1rom_data), .rom_ok(pf1rom_ok),
    .buf_addr(pf1_ba), .buf_data(pf1_bd), .buf_we(pf1_we), .busy(pf1_busy)
);
assign vpf1_addr = pf1_map[9:0];

deadang_text u_txt(
    .rst(rst), .clk(clk), .start(lstart), .line(rline),
    .vram_addr(vtxt_addr), .vram_data(vtxt_data),
    .rom_addr(char_addr), .rom_data(char_data),
    .buf_addr(txt_ba), .buf_data(txt_bd), .buf_we(txt_we), .busy(txt_busy)
);

deadang_obj u_obj(
    .rst(rst), .clk(clk), .start(lstart), .line(rline),
    .ram_addr(sbuf_addr), .ram_data(sbuf_data),
    .rom_addr(objrom_addr), .rom_cs(objrom_cs), .rom_data(objrom_data), .rom_ok(objrom_ok),
    .buf_addr(obj_ba), .buf_data(obj_bd), .buf_we(obj_we), .busy(obj_busy)
);

reg  [7:0] rd_x;
reg        obj_clr;
wire [7:0] pf3_q, pf1_q, pf2_q, txt_q;
wire [9:0] obj_q;

jtframe_dual_ram #(.DW(8),.AW(9)) u_lb_pf3(
    .clk0(clk), .data0(pf3_bd), .addr0({~front,pf3_ba}), .we0(pf3_we), .q0(),
    .clk1(clk), .data1(8'd0),   .addr1({front,rd_x}),    .we1(1'b0),   .q1(pf3_q) );
jtframe_dual_ram #(.DW(8),.AW(9)) u_lb_pf1(
    .clk0(clk), .data0(pf1_bd), .addr0({~front,pf1_ba}), .we0(pf1_we), .q0(),
    .clk1(clk), .data1(8'd0),   .addr1({front,rd_x}),    .we1(1'b0),   .q1(pf1_q) );
jtframe_dual_ram #(.DW(8),.AW(9)) u_lb_pf2(
    .clk0(clk), .data0(pf2_bd), .addr0({~front,pf2_ba}), .we0(pf2_we), .q0(),
    .clk1(clk), .data1(8'd0),   .addr1({front,rd_x}),    .we1(1'b0),   .q1(pf2_q) );
jtframe_dual_ram #(.DW(8),.AW(9)) u_lb_txt(
    .clk0(clk), .data0(txt_bd), .addr0({~front,txt_ba}), .we0(txt_we), .q0(),
    .clk1(clk), .data1(8'd0),   .addr1({front,rd_x}),    .we1(1'b0),   .q1(txt_q) );
jtframe_dual_ram #(.DW(10),.AW(9)) u_lb_obj(
    .clk0(clk), .data0(obj_bd),  .addr0({~front,obj_ba}), .we0(obj_we),  .q0(),
    .clk1(clk), .data1(10'h00F), .addr1({front,rd_x}),    .we1(obj_clr), .q1(obj_q) );

assign vpal_addr = pal_idx;

wire en_pf3 = !ctl34[0] && gfx_en[0];
wire en_pf1 = !ctl34[1] && gfx_en[1];
wire en_pf2 = !ctl34[2] && gfx_en[2];
wire en_txt = !ctl34[3] && gfx_en[3];
wire en_obj = !ctl34[4] && gfx_en[3];

reg  [2:0] pri;
reg [10:0] idx;
reg        blk;
always @(*) begin
    idx = 0; pri = 0; blk = 1;
    if( en_pf3 ) begin idx = { 3'd0, pf3_q }; pri = 3'd1; blk = 0; end
    if( en_pf1 && pf1_q[3:0] != 4'hF ) begin idx = { 3'b100, pf1_q }; pri = 3'd2; blk = 0; end
    if( en_pf2 && pf2_q[3:0] != 4'hF ) begin idx = { 3'b001, pf2_q }; pri = 3'd4; blk = 0; end
    if( en_obj && obj_q[3:0] != 4'hF ) begin
        if( !( (obj_q[9:8] == 2'b00 && (pri == 3'd2 || pri == 3'd4)) ||
               (obj_q[9:8] == 2'b01 &&  pri == 3'd4) ) ) begin
            idx = { 3'b011, obj_q[7:0] }; blk = 0;
        end
    end
    if( en_txt && txt_q[3:0] != 4'hF ) begin idx = { 3'b010, txt_q }; blk = 0; end
end

always @(posedge clk) begin
    obj_clr <= 0;
    if( pxl_cen ) begin
        ph   <= 0;
        rd_x <= flip ? ~hcnt[7:0] : hcnt[7:0];
        vis  <= hcnt < 9'd256;

        if( black ) { red, green, blue } <= 12'd0;
        else { blue, green, red } <= vpal_data[11:0];
    end else if( ph != 4'd7 ) begin
        ph <= ph + 4'd1;
        if( ph == 4'd1 ) begin pal_idx <= idx; black <= blk; end
        if( ph == 4'd2 && vis ) obj_clr <= 1;
    end
end

`ifdef SIMULATION

reg [95:0] scr_l = 0;
wire [95:0] scr_now = {scr01_i,scr02_i,scr09_i,scr0a_i,scr11_i,scr12_i,scr19_i,scr1a_i,
                      scr21_i,scr22_i,scr29_i,scr2a_i};
always @(posedge clk) begin
    scr_l <= scr_now;
    if( scr_now != scr_l ) $display("SCRWR v=%0d h=%0d %024X", vcnt, hcnt, scr_now);
end

integer lclk=0, m3=0,m2=0,m1=0,mt=0,mo=0, ovf=0, ovo=0;
always @(posedge clk) begin
    if( lstart ) begin
        if( pf3_busy || pf2_busy || pf1_busy || txt_busy ) ovf = ovf + 1;
        if( obj_busy ) ovo = ovo + 1;
        lclk = 0;
        if( vcnt == 8'd255 ) begin
            $display("LINEBUD pf3=%0d pf2=%0d pf1=%0d txt=%0d obj=%0d ovf_pf=%0d ovf_obj=%0d", m3,m2,m1,mt,mo,ovf,ovo);
            m3=0; m2=0; m1=0; mt=0; mo=0; ovf=0; ovo=0;
        end
    end else begin
        lclk = lclk + 1;
        if( pf3_busy && lclk > m3 ) m3 = lclk;
        if( pf2_busy && lclk > m2 ) m2 = lclk;
        if( pf1_busy && lclk > m1 ) m1 = lclk;
        if( txt_busy && lclk > mt ) mt = lclk;
        if( obj_busy && lclk > mo ) mo = lclk;
    end
end
`endif

endmodule
