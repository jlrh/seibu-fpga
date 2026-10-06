/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_sub -- sub V30 and its memory map (MAME 0.288 deadang.cpp:536-544):
      00000-037FF work RAM          03800-03FFF PF1 ("foreground") VRAM, 32x32 words (video reads)
      04000-04FFF shared RAM        08000 tile bank (bit 0)     0C000 watchdog
      E0000-FFFFF ROM (SDRAM)
    The sub does NOT take the lock: its shared-RAM accesses wait (READY low) while the main holds it
    (sh_wait from deadang_shared). Measured in MAME: 3.48 M sub accesses while the main held the lock,
    a race the hardware must prevent (research/DEADANG-PLAN.md §4-R1).
*/

module deadang_sub(
    input             rst,
    input             clk,
    input             cpu_cen,

    output     [16:1] rom_addr,
    output            rom_cs,
    input      [15:0] rom_data,
    input             rom_ok,

    input             irq_l240,
    input             irq_l0,

    output     [11:1] sh_addr,
    output     [15:0] sh_din,
    output      [1:0] sh_we,
    output            sh_cs,
    input      [15:0] sh_dout,
    input             sh_wait,

    input       [9:0] vpf1_addr,
    output     [15:0] vpf1_dout,
    output reg        tilebank,
    output reg        wdog,

    output     [19:0] dbg_addr
);

wire [19:0] A;
wire  [1:0] be;
wire [15:0] cpu_dout;
reg  [15:0] cpu_din;
wire        mem_rd, mem_wr, mem_wr_cyc, int_ack;
reg         int_req;
reg   [7:0] int_vec;

assign dbg_addr = A;

wire ram_cs  = A < 20'h03800;
wire pf1_cs  = A[19:11] == 9'b0000_0011_1;
assign sh_cs = (mem_rd || mem_wr) && A[19:12] == 8'h04;
wire bank_cs = A[19:1]  == 19'h04000;
wire wd_cs   = A[19:1]  == 19'h06000;
assign rom_cs   = mem_rd && A[19:17] == 3'b111;
assign rom_addr = A[16:1];

wire [1:0] we = mem_wr ? be : 2'b00;

reg [16:1] last_addr;
reg  [1:0] age;
always @(posedge clk) begin
    if( rom_addr != last_addr ) begin last_addr <= rom_addr; age <= 0; end
    else if( age != 2'd3 ) age <= age + 2'd1;
end
wire rom_good = rom_ok && age >= 2'd2;

wire sh_cyc = (mem_rd || mem_wr_cyc) && A[19:12] == 8'h04;
reg  sh_gnt;
always @(posedge clk) begin
    if( rst || !sh_cyc ) sh_gnt <= 0;
    else if( !sh_wait ) sh_gnt <= 1;
end
wire sh_blk = sh_cyc && sh_wait && !sh_gnt;
wire ready  = !(rom_cs && !rom_good) && !sh_blk;

wire [15:0] ram_dout, pf1_dout;

jtframe_ram16 #(.AW(13)) u_ram(
    .clk  ( clk               ),
    .data ( cpu_dout          ),
    .addr ( A[13:1]           ),
    .we   ( ram_cs ? we : 2'b0),
    .q    ( ram_dout          )
);

jtframe_dual_ram16 #(.AW(10)) u_pf1(
    .clk0 ( clk ), .data0( cpu_dout ), .addr0( A[10:1] ), .we0( pf1_cs ? we : 2'b0 ), .q0( pf1_dout ),
    .clk1 ( clk ), .data1( 16'd0    ), .addr1( vpf1_addr), .we1( 2'b0 ),              .q1( vpf1_dout )
);

assign sh_addr = A[11:1];
assign sh_din  = cpu_dout;
assign sh_we   = (sh_cs && !sh_blk) ? we : 2'b0;

reg mem_wr_l;
always @(posedge clk) mem_wr_l <= mem_wr;

`ifdef SIMULATION

reg sh_wr_done;
always @(posedge clk) begin
    if( !mem_wr ) sh_wr_done <= 0;
    else if( sh_cs && !sh_blk ) sh_wr_done <= 1;
    if( mem_wr_l && !mem_wr && A[19:12]==8'h04 && !sh_wr_done )
        $display("SUBWR_LOST %05X be=%b data=%04X t=%0t", A, be, cpu_dout, $time);
end
`endif
always @(posedge clk) begin
    if( rst ) begin
        tilebank <= 0;
        wdog     <= 0;
    end else begin
        wdog <= 0;
        if( mem_wr && !mem_wr_l ) begin
            if( bank_cs && be[0] ) tilebank <= cpu_dout[0];
            if( wd_cs ) wdog <= 1;
        end
    end
end

always @(*) begin
    cpu_din = 16'h0000;
    if( A[19:17] == 3'b111 ) cpu_din = rom_data;
    else if( ram_cs ) cpu_din = ram_dout;
    else if( pf1_cs ) cpu_din = pf1_dout;
    else if( A[19:12] == 8'h04 ) cpu_din = sh_dout;
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
    .mem_wr_cyc ( mem_wr_cyc),
    .code       (           ),
    .io_rd      (           ),
    .io_wr      (           ),
    .int_req    ( int_req   ),
    .int_vector ( int_vec   ),
    .int_ack    ( int_ack   )
);

endmodule
