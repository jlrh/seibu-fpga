/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_obj -- sprites for one line, unflipped (deadang.cpp:286-327):
      w0: b14 = 0 -> flipY (inverted), b13 flipX, b7-0 Y      w1: colour[15:12], code[11:0]
      w2: pri[15:14], b8 sign: x = x - 255 (sic, MAME), b7-0 X  w3: active iff (w3 & 0xFF00) == 0x0F00
    MAME draws entries 0..255 with prio_transpen (pmask |= 1<<31, priority = 31 on every opaque
    pixel) => the FIRST opaque sprite pixel wins and blocks later sprites even when it is itself
    hidden by a playfield. Equivalent here: entries are drawn 255 -> 0, overwriting, and the line
    buffer keeps the class so the mixer decides sprite vs playfield.
    No wrap: a sprite covers lines y..y+15 of the 256-line bitmap and is clipped (drawgfx).
    Line buffer data = {cls[1:0], colour[3:0], pen[3:0]}; pen 15 = transparent (not written).

    Three overlapped stages (the line budget is 3120 clk and the game parks most of its 256 always-
    "active" entries off-screen; with real SDRAM latency a serial engine overflowed, measured):
      scanner -> FIFO of sprite descriptors -> fetcher (one 32-bit ROM word per half, the next
      request issued the clock its predecessor's data arrives) -> draw queue -> drawer (8 px/word).
    Drawing order is preserved (FIFOs), so the overwrite semantics above hold.
*/

module deadang_obj(
    input             rst,
    input             clk,
    input             start,
    input       [7:0] line,

    output reg  [9:0] ram_addr,
    input      [15:0] ram_data,

    output reg [16:0] rom_addr,
    output reg        rom_cs,
    input      [31:0] rom_data,
    input             rom_ok,

    output reg  [7:0] buf_addr,
    output reg  [9:0] buf_data,
    output reg        buf_we,
    output            busy
);

localparam DW = 33;
reg  [2:0] sst;
localparam S_IDLE=0, S1=1, S2=2, S3=3, S4=4, S5=5, S6=6, S_PUSH=7;
reg  [7:0] idx;
reg [15:0] w0, w1;
reg  [3:0] fine;
reg        fx;
reg [DW-1:0] desc_in;
wire [7:0] idx_m1 = idx - 8'd1;
wire [8:0] dy = { 1'b0, line } - { 1'b0, ram_data[7:0] };

reg [DW-1:0] dfifo[0:3];
reg  [1:0] dwr, drd;
reg  [2:0] dcnt;
wire       dfull = dcnt == 3'd4;
wire       dempty = dcnt == 3'd0;
reg        dpush, dpop;

always @(posedge clk) begin
    if( rst ) begin
        sst <= S_IDLE; dpush <= 0;
    end else begin
        dpush <= 0;
        case( sst )
            S_IDLE: if( start ) begin idx <= 8'd255; ram_addr <= { 8'd255, 2'd3 }; sst <= S1; end
            S1: begin ram_addr <= { idx, 2'd0 }; sst <= S2; end
            S2: begin
                if( ram_data[15:8] != 8'h0F ) begin
                    if( idx == 8'd0 ) sst <= S_IDLE;
                    else begin idx <= idx_m1; ram_addr <= { idx_m1, 2'd3 }; sst <= S1; end
                end else sst <= S3;
            end
            S3: begin
                if( dy[8:4] != 0 ) begin
                    if( idx == 8'd0 ) sst <= S_IDLE;
                    else begin idx <= idx_m1; ram_addr <= { idx_m1, 2'd3 }; sst <= S1; end
                end else begin
                    fine <= ram_data[14] ? dy[3:0] : ~dy[3:0];
                    fx   <= ram_data[13];
                    ram_addr <= { idx, 2'd1 };
                    sst <= S4;
                end
            end
            S4: begin ram_addr <= { idx, 2'd2 }; sst <= S5; end
            S5: begin w1 <= ram_data; sst <= S6; end
            S6: begin
                if( ram_data[8] && ram_data[7:0] < 8'd240 ) begin

                    if( idx == 8'd0 ) sst <= S_IDLE;
                    else begin idx <= idx_m1; ram_addr <= { idx_m1, 2'd3 }; sst <= S1; end
                end else begin
                    desc_in <= { w1[11:0], fine, fx,
                                 ram_data[8] ? ({ 2'd0, ram_data[7:0] } - 10'd255) : { 2'd0, ram_data[7:0] },
                                 ram_data[15:14], w1[15:12] };
                    sst <= S_PUSH;
                end
            end
            S_PUSH: if( !dfull ) begin
                dpush <= 1;
                if( idx == 8'd0 ) sst <= S_IDLE;
                else begin idx <= idx_m1; ram_addr <= { idx_m1, 2'd3 }; sst <= S1; end
            end
            default: sst <= S_IDLE;
        endcase
    end
end

always @(posedge clk) begin
    if( rst || start ) begin
        dwr <= 0; drd <= 0; dcnt <= 0;
    end else begin
        if( dpush ) begin dfifo[dwr] <= desc_in; dwr <= dwr + 2'd1; end
        dcnt <= dcnt + {2'd0, dpush} - {2'd0, dpop};
        if( dpop ) drd <= drd + 2'd1;
    end
end
wire [DW-1:0] dhead = dfifo[drd];

localparam QW = 32 + 1 + 1 + 10 + 2 + 4;
reg [QW-1:0] q[0:1];
reg          qwr, qrd;
reg  [1:0]   qcnt;
wire         qfull = qcnt == 2'd2;
reg          qpush, qpop;
reg [QW-1:0] q_in;

reg        fbusy, fhalf;
reg  [1:0] w;
wire       got = fbusy && rom_ok && w >= 2'd2;

always @(posedge clk) begin
    if( rst || start ) begin
        fbusy <= 0; fhalf <= 0; rom_cs <= 0; qpush <= 0; dpop <= 0; w <= 0;
    end else begin
        qpush <= 0; dpop <= 0;
        if( w != 2'd3 ) w <= w + 2'd1;
        if( got && !qfull ) begin

            q_in  <= { rom_data, fhalf, dhead[16], dhead[15:6], dhead[5:4], dhead[3:0] };
            qpush <= 1;
            if( !fhalf ) begin

                fhalf    <= 1;
                rom_addr <= { dhead[32:21], 1'b1, dhead[20:17] };
                w <= 0;
            end else begin
                fhalf <= 0;
                dpop  <= 1;
                fbusy <= 0;
                rom_cs <= 0;
            end
        end else if( !fbusy && !dempty && !dpop ) begin
            fbusy    <= 1;
            fhalf    <= 0;
            rom_addr <= { dhead[32:21], 1'b0, dhead[20:17] };
            rom_cs   <= 1;
            w        <= 0;
        end
    end
end

always @(posedge clk) begin
    if( rst || start ) begin
        qwr <= 0; qrd <= 0; qcnt <= 0;
    end else begin
        if( qpush ) begin q[qwr] <= q_in; qwr <= ~qwr; end
        qcnt <= qcnt + {1'b0, qpush} - {1'b0, qpop};
        if( qpop ) qrd <= ~qrd;
    end
end

reg [QW-1:0] cur;
reg          drawing;
reg  [2:0]   k;
wire [31:0] gfx  = cur[QW-1 -: 32];
wire        half = cur[17];
wire        cfx  = cur[16];
wire  [9:0] xpos = cur[15:6];
wire  [1:0] cls  = cur[5:4];
wire  [3:0] col  = cur[3:0];
wire  [7:0] hi = k[2] ? gfx[31:24] : gfx[15:8];
wire  [7:0] lo = k[2] ? gfx[23:16] : gfx[ 7:0];
wire  [1:0] kk = k[1:0];
wire  [3:0] pen = { hi[4+kk], hi[kk], lo[4+kk], lo[kk] };
wire  [3:0] p   = { half, k };
wire  [3:0] pp  = cfx ? ~p : p;
wire  [9:0] sx  = xpos + { 6'd0, pp };

always @(posedge clk) begin
    if( rst || start ) begin
        drawing <= 0; buf_we <= 0; qpop <= 0;
    end else begin
        buf_we <= 0; qpop <= 0;
        if( !drawing ) begin
            if( qcnt != 0 && !qpop ) begin cur <= q[qrd]; qpop <= 1; drawing <= 1; k <= 0; end
        end else begin
            if( pen != 4'hF && !sx[9] && !sx[8] ) begin
                buf_addr <= sx[7:0];
                buf_data <= { cls, col, pen };
                buf_we   <= 1;
            end
            k <= k + 3'd1;
            if( k == 3'd7 ) drawing <= 0;
        end
    end
end

assign busy = sst != S_IDLE || !dempty || fbusy || qcnt != 0 || drawing || dpush || qpush;

endmodule
