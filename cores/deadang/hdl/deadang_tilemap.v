/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_tilemap -- renders ONE line of a 16x16 4bpp playfield into a line buffer.
    Coordinates are UNFLIPPED (flip is a full mirror, done by the caller).
      ROMMAP=1  PF3/PF2: 128x256 tiles, map in ROM, bg_scan order (deadang.cpp:204-207):
                idx = (col&0xF) | (row&0xF)<<4 | (col&0x70)<<4 | (row&0xF0)<<7
                tile = word & 0x7FF, colour = word >> 12          (deadang.cpp:209-221)
      ROMMAP=0  PF1: 32x32 tiles, map in the sub's RAM, TILEMAP_SCAN_COLS idx = col*32+row,
                tile = (word & 0xFFF) + bank*0x1000, colour = word >> 12   (deadang.cpp:223-230)
    Screen pixel x of line L comes from map pixel ((x + scrx) mod W, (L + scry) mod H).
    GFX (spritelayout, deadang.cpp:704-713): 128 bytes/tile, one 32-bit word per 8-pixel row half,
    word address = tile*32 + half*16 + fine_y. Pixel k of a half (k = x&3) from bytes
    {b1,b0} (x<4) or {b3,b2} (x>=4): pen = { hi[4+k], hi[k], lo[4+k], lo[k] }.
    Line buffer data = {colour[3:0], pen[3:0]}.
*/

module deadang_tilemap #(parameter ROMMAP = 1, RW = 18)(
    input             rst,
    input             clk,
    input             start,
    input       [7:0] line,
    input      [11:0] scrx,
    input      [11:0] scry,
    input             bank,

    output reg [14:0] map_addr,
    input      [15:0] map_data,

    output reg [RW-1:0] rom_addr,
    output reg        rom_cs,
    input      [31:0] rom_data,
    input             rom_ok,

    output reg  [7:0] buf_addr,
    output reg  [7:0] buf_data,
    output reg        buf_we,
    output            busy
);

localparam [11:0] WMASK = ROMMAP ? 12'd2047 : 12'd511;
localparam [11:0] HMASK = ROMMAP ? 12'd4095 : 12'd511;

reg  [3:0] st;
localparam IDLE=0, MAP=1, MAPW=2, ROM=3, ROMW=4, DRAW=5;

reg  [4:0] t;
reg  [3:0] fx;
reg [11:0] my;
reg  [7:0] col;
reg  [7:0] row;
reg [15:0] tile;
reg  [3:0] color;
reg        half;
reg  [2:0] k;
reg  [1:0] wait_cnt;
reg [31:0] gfx;

assign busy = st != IDLE;

wire [11:0] mx0 = scrx & WMASK;

always @(*) begin
    if( ROMMAP )
        map_addr = { row[7:4], col[6:4], row[3:0], col[3:0] };
    else
        map_addr = { 5'd0, col[4:0], row[4:0] };
end

wire [7:0] hi = k[2] ? gfx[31:24] : gfx[15:8];
wire [7:0] lo = k[2] ? gfx[23:16] : gfx[ 7:0];
wire [1:0] kk = k[1:0];
wire [3:0] pen = { hi[4+kk], hi[kk], lo[4+kk], lo[kk] };

wire [9:0] sx = { 1'b0, t, 4'd0 } - { 6'd0, fx } + { 6'd0, half, 3'd0 } + { 7'd0, k };

always @(posedge clk) begin
    if( rst ) begin
        st <= IDLE; rom_cs <= 0; buf_we <= 0;
    end else begin
        buf_we <= 0;
        case( st )
            IDLE: if( start ) begin
                my  <= ({4'd0, line} + scry) & HMASK;
                fx  <= mx0[3:0];
                col <= mx0[11:4];
                t   <= 0;
                st  <= MAP;
            end
            MAP: begin
                row <= my[11:4];
                wait_cnt <= 0;
                st <= MAPW;
            end
            MAPW: begin
                wait_cnt <= wait_cnt + 2'd1;
                if( wait_cnt == 2'd2 ) begin
                    color <= map_data[15:12];
                    tile  <= ROMMAP ? { 5'd0, map_data[10:0] } :
                                      { 3'd0, bank, map_data[11:0] };
                    half  <= 0;
                    st    <= ROM;
                end
            end
            ROM: begin
                rom_addr <= { tile[RW-6:0], half, my[3:0] };
                rom_cs   <= 1;
                wait_cnt <= 0;
                st       <= ROMW;
            end
            ROMW: begin

                if( wait_cnt != 2'd3 ) wait_cnt <= wait_cnt + 2'd1;
                if( rom_ok && wait_cnt >= 2'd2 ) begin
                    gfx    <= rom_data;
                    rom_cs <= 0;
                    k      <= 0;
                    st     <= DRAW;
                end
            end
            DRAW: begin
                if( !sx[9] && sx[8] == 1'b0 ) begin
                    buf_addr <= sx[7:0];
                    buf_data <= { color, pen };
                    buf_we   <= 1;
                end
                k <= k + 3'd1;
                if( k == 3'd7 ) begin
                    if( !half ) begin
                        half <= 1;
                        st   <= ROM;
                    end else begin
                        t   <= t + 5'd1;
                        col <= (col + 8'd1) & (ROMMAP ? 8'h7F : 8'h1F);
                        st  <= t == 5'd16 ? IDLE : MAP;
                    end
                end
            end
            default: st <= IDLE;
        endcase
    end
end

endmodule
