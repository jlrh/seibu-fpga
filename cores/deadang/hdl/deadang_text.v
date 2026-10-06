/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_text -- one line of the 32x32 8x8 text layer (deadang.cpp:232-238, 693-702), unflipped.
      word = videoram[row*32 + col]; code = (w & 0xFF) | ((w >> 6) & 0x300); colour = (w >> 8) & 0xF
    charlayout: RGN_FRAC(1,2) -> char ROM 32 kB = two 16 kB halves (7.21j | 8.21l), 16 bytes per char,
    2 bytes per row. Pixel x (k = x&3, byte = x<4 ? 0 : 1):
      pen = { H[4+k], H[k], L[4+k], L[k] }   (H = second half, L = first half)
    Char ROM in BRAM (8 bit): address {half, code[9:0], row[2:0], byte}.
*/

module deadang_text(
    input             rst,
    input             clk,
    input             start,
    input       [7:0] line,

    output reg  [9:0] vram_addr,
    input      [15:0] vram_data,

    output reg [14:0] rom_addr,
    input       [7:0] rom_data,

    output reg  [7:0] buf_addr,
    output reg  [7:0] buf_data,
    output reg        buf_we,
    output            busy
);

reg [3:0] st;
localparam IDLE=0, VRD=1, R0=2, R1=3, R2=4, R3=5, R4=6, DRAW=7;
reg [5:0] col;
reg [9:0] code;
reg [3:0] color;
reg [7:0] l0, l1, h0, h1;
reg [1:0] w;
reg [2:0] k;
assign busy = st != IDLE;

wire [7:0] hb = k[2] ? h1 : h0;
wire [7:0] lb = k[2] ? l1 : l0;
wire [1:0] kk = k[1:0];
wire [3:0] pen = { hb[4+kk], hb[kk], lb[4+kk], lb[kk] };

always @(posedge clk) begin
    if( rst ) begin st <= IDLE; buf_we <= 0; end
    else begin
        buf_we <= 0;
        case( st )
            IDLE: if( start ) begin col <= 0; st <= VRD; end
            VRD: begin
                vram_addr <= { line[7:3], col[4:0] };
                w <= 0; st <= R0;
            end
            R0: begin
                w <= w + 2'd1;
                if( w == 2'd2 ) begin
                    code  <= { vram_data[15:14], vram_data[7:0] };
                    color <= vram_data[11:8];
                    rom_addr <= { 1'b0, vram_data[15:14], vram_data[7:0], line[2:0], 1'b0 };
                    w <= 0; st <= R1;
                end
            end
            R1: begin w <= w + 2'd1; if( w == 2'd2 ) begin l0 <= rom_data; rom_addr[0] <= 1; w <= 0; st <= R2; end end
            R2: begin w <= w + 2'd1; if( w == 2'd2 ) begin l1 <= rom_data; rom_addr <= { 1'b1, code, line[2:0], 1'b0 }; w <= 0; st <= R3; end end
            R3: begin w <= w + 2'd1; if( w == 2'd2 ) begin h0 <= rom_data; rom_addr[0] <= 1; w <= 0; st <= R4; end end
            R4: begin w <= w + 2'd1; if( w == 2'd2 ) begin h1 <= rom_data; k <= 0; st <= DRAW; end end
            DRAW: begin
                buf_addr <= { col[4:0], k };
                buf_data <= { color, pen };
                buf_we   <= 1;
                k <= k + 3'd1;
                if( k == 3'd7 ) begin
                    col <= col + 6'd1;
                    st  <= col == 6'd31 ? IDLE : VRD;
                end
            end
            default: st <= IDLE;
        endcase
    end
end

endmodule
