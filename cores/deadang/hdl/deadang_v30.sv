/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer.
    GPL v3 or later.

    deadang_v30 -- NEC V30 (wickerwaka's cycle-exact "ucore", nec_test ed50fb4e, GPL-2.0) plus a
    max-mode bus controller that turns BS/RD_N/UBE_N into a word bus with strobes.

    Distilled from v30_bus.sv of Irem M72 (Martin Donlon) as adapted by Raiden_MiSTer (Umberto
    Parisi, GPL-3.0), WITHOUT the save-state machinery. The timing rules kept from there were all
    measured on hardware by those projects (their comments, summarised):
      * READY is registered at the CPU clock (ce), like the BIU's ready_prev, or tracker and BIU
        desynchronise under real memory latency.
      * BS is captured 4 clocks after ce (the BS cone is long; consumers only read it at a ce).
      * UBE_N is only valid while the core is IN T1 -> byte enables are latched at T1->T2,
        A0 together with the address at T1 entry. Sampling UBE_N at T1 entry gives the PREVIOUS
        cycle's lane (wrong-lane writes).
      * The INTA vector is fed on DATA_I during the INTA cycles.
    Requirement on `ce`: at least 5 clk between pulses (BS capture at +4).
*/

module deadang_v30(
    input             clk,
    input             rst,
    input             ce,
    input             ready,

    output     [19:0] addr,
    output      [1:0] be,
    output     [15:0] dout,
    input      [15:0] din,
    output            mem_rd,
    output            mem_wr,
    output            code,
    output            io_rd,
    output            io_wr,

    input             int_req,
    input       [7:0] int_vector,
    output            int_ack
);

import v30_ss_pkg::*;

localparam [2:0] BS_INTA=3'b000, BS_IOR=3'b001, BS_IOW=3'b010, BS_HALT=3'b011,
                 BS_CODE=3'b100, BS_MEMR=3'b101, BS_MEMW=3'b110, BS_PASV=3'b111;
localparam [2:0] ST_TI=3'd0, ST_T1=3'd1, ST_T2=3'd2, ST_T3=3'd3, ST_TW=3'd4, ST_T4=3'd5;

wire  [2:0] BS;
wire        RD_N, UBE_N;
wire [19:0] ADDR_O;
wire [15:0] DATA_O;
reg  [15:0] rdata_q;

reg  [2:0] t_state, lat_type;
reg        ready_r;
wire       rd_cycle = lat_type == BS_CODE || lat_type == BS_MEMR || lat_type == BS_IOR;
wire       cce      = ce && !(t_state == ST_T2 && rd_cycle && !ready_r);
always @(posedge clk) ready_r <= ready;

/* verilator lint_off PINCONNECTEMPTY */
v30_core u_core(
    .CLK        ( clk       ),
    .CE         ( cce       ),
    .RESET      ( rst       ),
    .READY      ( ready     ),
    .INT        ( int_req   ),
    .NMI        ( 1'b0      ),
    .POLL_N     ( 1'b1      ),
    .DATA_I     ( rdata_q   ),
    .ADDR_O     ( ADDR_O    ),
    .DATA_O     ( DATA_O    ),
    .STATUS_O   (           ),
    .QS         (           ),
    .BS         ( BS        ),
    .RD_N       ( RD_N      ),
    .UBE_N      ( UBE_N     ),
    .BUSLOCK_N  (           ),
    .SS_ADDR    ( '0        ),
    .SS_WDATA   ( 16'd0     ),
    .SS_WE      ( 1'b0      ),
    .SS_RDATA   (           ),
    .SS_ERR     (           ),
    .SS_BUS_QUIET(          )
);
/* verilator lint_on PINCONNECTEMPTY */

reg  [3:0] ce_pipe;
reg  [2:0] bs_q;
always @(posedge clk) begin
    ce_pipe <= { ce_pipe[2:0], cce };
    if( ce_pipe[3] ) bs_q <= BS;
end

reg        addr_valid, inta_prev, inta_second, ready_q, a0_lat;
reg [19:0] addr_lat;
reg  [1:0] be_lat;
reg [15:0] dout_lat;

wire bs_active = bs_q != BS_PASV;

always @(posedge clk) begin
    if( rst )    ready_q <= 1;
    else if( cce ) ready_q <= ready;
end

wire [2:0] next_t =
    (t_state == ST_TI) ? (bs_active ? ST_T1 : ST_TI) :
    (t_state == ST_T1) ? ST_T2 :
    (t_state == ST_T2) ? ST_T3 :
    (t_state == ST_T3) ? (ready_q ? ST_T4 : ST_TW) :
    (t_state == ST_TW) ? (ready_q ? ST_T4 : ST_TW) :
                         (bs_active ? ST_T1 : ST_TI);

always @(posedge clk) begin
    if( rst ) begin
        t_state     <= ST_TI;
        lat_type    <= BS_PASV;
        addr_valid  <= 0;
        inta_prev   <= 0;
        inta_second <= 0;
        be_lat      <= 0;
        addr_lat    <= 0;
        a0_lat      <= 0;
        dout_lat    <= 0;
    end else if( cce ) begin
        t_state <= next_t;
        if( next_t == ST_T1 ) begin
            lat_type   <= bs_q;
            addr_lat   <= { ADDR_O[19:1], 1'b0 };
            a0_lat     <= ADDR_O[0];
            addr_valid <= 1;
            if( bs_q == BS_INTA ) begin
                inta_second <= inta_prev;
                inta_prev   <= 1;
            end else begin
                inta_second <= 0;
                inta_prev   <= 0;
            end
        end else if( next_t == ST_T4 || next_t == ST_TI ) begin
            addr_valid <= 0;
        end
        if( t_state == ST_T1 ) be_lat <= { ~UBE_N, ~a0_lat };
        if( (t_state == ST_T2 || t_state == ST_T3) && (lat_type == BS_MEMW || lat_type == BS_IOW) )
            dout_lat <= DATA_O;
    end
end

always @(posedge clk)
    rdata_q <= lat_type == BS_INTA ? { 8'h00, int_vector } : din;

assign addr    = addr_lat;
assign be      = be_lat;
assign dout    = dout_lat;
assign code    = lat_type == BS_CODE;
assign mem_rd  = addr_valid && (lat_type == BS_CODE || lat_type == BS_MEMR);
assign io_rd   = addr_valid &&  lat_type == BS_IOR;
assign mem_wr  = lat_type == BS_MEMW && (t_state == ST_T3 || t_state == ST_TW);
assign io_wr   = lat_type == BS_IOW  && (t_state == ST_T3 || t_state == ST_TW);
assign int_ack = lat_type == BS_INTA && inta_second && t_state == ST_T3;

endmodule
