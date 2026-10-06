/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_main -- main V30 and its memory map (MAME 0.288 deadang.cpp:490-507):
      00000-037FF work RAM          03800-03FFF sprite RAM (video reads it)
      04000-04FFF shared RAM (+ lock, see deadang_shared)
      06000-0600F Seibu sound interface, low byte lane (offset = A[3:1])
      08000-087FF text RAM (video)  0A000 P1_P2   0A002 DSW
      0C000-0CFFF palette (video)   0E000-0E0FF "scroll RAM" (video registers, low byte used)
      C0000-FFFFF ROM (SDRAM)
    Unmapped reads return 0 (MAME unmap value). Text RAM and palette read back their contents
    (MAME: write-only -> 0; the game never reads them, measured in the boot trace).
    0xE068 bit 7 = shared-RAM lock (0 = main owns it). Reset value 0 (locked): the game clears the
    shared RAM BEFORE its first write to 0xE068 (research/DEADANG-PLAN.md §4-R1).
*/

module deadang_main(
    input             rst,
    input             clk,
    input             cpu_cen,

    output     [17:1] rom_addr,
    output            rom_cs,
    input      [15:0] rom_data,
    input             rom_ok,

    input             irq_l240,
    input             irq_l0,

    output     [11:1] sh_addr,
    output     [15:0] sh_din,
    output      [1:0] sh_we,
    input      [15:0] sh_dout,
    output reg        lock,

    output      [2:0] snd_addr,
    output      [7:0] snd_din,
    output            snd_wr,
    output            snd_rd,
    input       [7:0] snd_dout,

    input       [9:0] vtxt_addr,  output [15:0] vtxt_dout,
    input       [9:0] vspr_addr,  output [15:0] vspr_dout,
    input      [10:0] vpal_addr,  output [15:0] vpal_dout,

    output reg  [7:0] scr01, scr02, scr09, scr0a,
    output reg  [7:0] scr11, scr12, scr19, scr1a,
    output reg  [7:0] scr21, scr22, scr29, scr2a,
    output reg  [7:0] ctl34,
    output reg        spr_dma,

    input      [15:0] p1p2,
    input      [15:0] dsw,

    output     [19:0] dbg_addr
);

wire [19:0] A;
wire  [1:0] be;
wire [15:0] cpu_dout;
reg  [15:0] cpu_din;
wire        mem_rd, mem_wr, int_ack;
reg         int_req;
reg   [7:0] int_vec;

assign dbg_addr = A;

wire ram_cs  = A < 20'h03800;
wire spr_cs  = A[19:11] == 9'b0000_0011_1;
wire sh_cs   = A[19:12] == 8'h04;
wire snd_cs  = A[19:4]  == 16'h0600;
wire txt_cs  = A[19:11] == 9'b0000_1000_0;
wire in_cs   = A[19:2]  == 18'h02800;
wire pal_cs  = A[19:12] == 8'h0C;
wire scr_cs  = A[19:8]  == 12'h0E0;
assign rom_cs = mem_rd && A[19:18] == 2'b11;
assign rom_addr = A[17:1];

wire [1:0] we = mem_wr ? be : 2'b00;

reg [17:1] last_addr;
reg  [1:0] age;
always @(posedge clk) begin
    if( rom_addr != last_addr ) begin last_addr <= rom_addr; age <= 0; end
    else if( age != 2'd3 ) age <= age + 2'd1;
end
wire rom_good = rom_ok && age >= 2'd2;
wire ready = !(rom_cs && !rom_good);

wire [15:0] ram_dout, spr_dout, txt_dout, pal_dout, scr_dout;

jtframe_ram16 #(.AW(13)) u_ram(
    .clk  ( clk               ),
    .data ( cpu_dout          ),
    .addr ( A[13:1]           ),
    .we   ( ram_cs ? we : 2'b0),
    .q    ( ram_dout          )
);

jtframe_dual_ram16 #(.AW(10)) u_spr(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( A[10:1] ), .we0( spr_cs ? we : 2'b0 ), .q0( spr_dout ),
    .clk1 ( clk ), .data1( 16'd0    ), .addr1( vspr_addr), .we1( 2'b0 ),              .q1( vspr_dout )
);

jtframe_dual_ram16 #(.AW(10)) u_txt(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( A[10:1] ), .we0( txt_cs ? we : 2'b0 ), .q0( txt_dout ),
    .clk1 ( clk ), .data1( 16'd0    ), .addr1( vtxt_addr), .we1( 2'b0 ),              .q1( vtxt_dout )
);

jtframe_dual_ram16 #(.AW(11)) u_pal(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( A[11:1] ), .we0( pal_cs ? we : 2'b0 ), .q0( pal_dout ),
    .clk1 ( clk ), .data1( 16'd0    ), .addr1( vpal_addr), .we1( 2'b0 ),              .q1( vpal_dout )
);

jtframe_ram16 #(.AW(7)) u_scr(
    .clk  ( clk               ),
    .data ( cpu_dout          ),
    .addr ( A[7:1]            ),
    .we   ( scr_cs ? we : 2'b0),
    .q    ( scr_dout          )
);

reg mem_wr_l;
always @(posedge clk) mem_wr_l <= mem_wr;
wire wr_edge = mem_wr && !mem_wr_l;

always @(posedge clk) begin
    if( rst ) begin
        { scr01, scr02, scr09, scr0a, scr11, scr12, scr19, scr1a,
          scr21, scr22, scr29, scr2a } <= 0;
        ctl34   <= 8'h00;
        lock    <= 1;
        spr_dma <= 0;
    end else begin
        spr_dma <= 0;
        if( scr_cs && wr_edge && be[0] ) begin
            case( A[7:1] )
                7'h01: scr01 <= cpu_dout[7:0];
                7'h02: scr02 <= cpu_dout[7:0];
                7'h09: scr09 <= cpu_dout[7:0];
                7'h0a: scr0a <= cpu_dout[7:0];
                7'h11: scr11 <= cpu_dout[7:0];
                7'h12: scr12 <= cpu_dout[7:0];
                7'h19: scr19 <= cpu_dout[7:0];
                7'h1a: scr1a <= cpu_dout[7:0];
                7'h21: scr21 <= cpu_dout[7:0];
                7'h22: scr22 <= cpu_dout[7:0];
                7'h29: scr29 <= cpu_dout[7:0];
                7'h2a: scr2a <= cpu_dout[7:0];
                7'h30: spr_dma <= 1;
                7'h34: begin ctl34 <= cpu_dout[7:0]; lock <= ~cpu_dout[7]; end
                default:;
            endcase
        end
    end
end

assign sh_addr = A[11:1];
assign sh_din  = cpu_dout;
assign sh_we   = sh_cs ? we : 2'b0;

assign snd_addr = A[3:1];
assign snd_din  = cpu_dout[7:0];
assign snd_wr   = snd_cs && wr_edge && be[0];
reg mem_rd_l;
always @(posedge clk) mem_rd_l <= mem_rd;
assign snd_rd   = snd_cs && mem_rd && !mem_rd_l;

always @(*) begin
    cpu_din = 16'h0000;
    if( A[19:18] == 2'b11 ) cpu_din = rom_data;
    else if( ram_cs )  cpu_din = ram_dout;
    else if( spr_cs )  cpu_din = spr_dout;
    else if( sh_cs  )  cpu_din = sh_dout;
    else if( snd_cs )  cpu_din = { 8'h00, snd_dout };
    else if( txt_cs )  cpu_din = txt_dout;
    else if( in_cs  )  cpu_din = A[1] ? dsw : p1p2;
    else if( pal_cs )  cpu_din = pal_dout;
    else if( scr_cs )  cpu_din = scr_dout;
end

always @(posedge clk) begin
    if( rst ) begin
        int_req <= 0;
        int_vec <= 8'h32;
    end else begin
        if( int_ack ) int_req <= 0;
        if( irq_l240 ) begin int_req <= 1; int_vec <= 8'h31; end
        if( irq_l0   ) begin int_req <= 1; int_vec <= 8'h32; end
    end
end

deadang_v30 u_cpu(
    .clk        ( clk       ),
    .rst        ( rst       ),
    .ce         ( cpu_cen   ),
    .ready      ( ready     ),
    .addr       ( A         ),
    .be         ( be        ),
    .dout       ( cpu_dout  ),
    .din        ( cpu_din   ),
    .mem_rd     ( mem_rd    ),
    .mem_wr     ( mem_wr    ),
    .code       (           ),
    .io_rd      (           ),
    .io_wr      (           ),
    .int_req    ( int_req   ),
    .int_vector ( int_vec   ),
    .int_ack    ( int_ack   )
);

endmodule
