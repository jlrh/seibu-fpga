// Paleta xBRG_444 -> RGB (4 bits/canal) + CLUTs por capa. Ver golden: mix_txlayer 5 pasadas.
module empirecity_colmix(
    input clk, input [7:0] pal_idx, output [3:0] red, green, blue
);
// TODO Fase 2: RAM de paleta (256x16 xBRG_444) -> RGB. bases bg0x00/fg0x40/spr0x80/tx0xc0.
assign red=0; assign green=0; assign blue=0;
endmodule
