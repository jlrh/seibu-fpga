/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_sei80bu -- SEI80BU Z80 ROM decryption, combinational. Transcribed from MAME 0.288
    src/mame/seibu/sei80bu.cpp:54-91 (data_r / opcode_r). Only 0000-1FFF is encrypted.
    `m1` selects the opcode table. Verified exhaustively against the MAME formula
    (ver/sei80bu: 8192 addresses x 256 values x {data, opcode}).
*/

module deadang_sei80bu(
    input      [15:0] a,
    input       [7:0] din,
    input             m1,
    output reg  [7:0] dout
);

function [7:0] swp;
    input [7:0] s; input [2:0] i, j;
    begin swp = s; swp[i] = s[j]; swp[j] = s[i]; end
endfunction

reg [7:0] s;
always @(*) begin
    s = din;

    if( a[9]  &  a[8]          ) s = s ^ 8'h80;
    if( a[11] &  a[4]  &  a[1] ) s = s ^ 8'h40;
    if( m1 ) begin
        if( ~a[13] &  a[12]        ) s = s ^ 8'h20;
        if( ~a[6]  &  a[1]         ) s = s ^ 8'h10;
        if( ~a[12] &  a[2]         ) s = s ^ 8'h08;
    end
    if( a[11] & ~a[8]  &  a[1] ) s = s ^ 8'h04;
    if( a[13] & ~a[6]  &  a[4] ) s = s ^ 8'h02;
    if( ~a[11] & a[9]  &  a[2] ) s = s ^ 8'h01;

    if( a[13] & a[4] ) s = swp(s, 3'd1, 3'd0);
    if( a[8]  & a[4] ) s = swp(s, 3'd3, 3'd2);
    if( m1 ) begin
        if( a[12] & a[9]  ) s = swp(s, 3'd5, 3'd4);
        if( a[11] & ~a[6] ) s = swp(s, 3'd7, 3'd6);
    end
    dout = s;
end

endmodule
