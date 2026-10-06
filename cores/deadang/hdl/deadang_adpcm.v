/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_adpcm -- "Seibu ADPCM" (MSM5205 + address counter in the YM3931), MAME 0.288
    src/mame/shared/seibusound.cpp:384-451, plus the MSM5205 itself (jt5205, 375 kHz, S48 -> 7.8125 kHz).
      adr_w offset 0: current = data<<8, nibble = 4 (HIGH nibble first)   offset 1: end = data<<8
      ctl_w 0: MSM reset, stop   1: MSM run, play   2: nothing
      on each VCK: if playing, feed (rom[current] >> nibble) & 15; after the low nibble current++,
      and when current >= end: MSM reset, stop.
    The sample ROM is stored as dumped; the line swap of init_adpcm()/decrypt()
    (bitswap<8>(v, 7,5,3,1,6,4,2,0)) is applied here.
*/

module deadang_adpcm(
    input             rst,
    input             clk,
    input             cen375,

    input             adr_wr,
    input             adr_hi,
    input             ctl_wr,
    input       [7:0] din,

    output     [15:0] rom_addr,
    output reg        rom_cs,
    input       [7:0] rom_data,
    input             rom_ok,

    output signed [11:0] snd,
    output            sample
);

reg  [15:0] cur, last;
reg         nib_hi, playing, msm_rst;
reg   [3:0] msm_din;
wire        vck;

assign rom_addr = cur;

wire [7:0] dec = { rom_data[7], rom_data[5], rom_data[3], rom_data[1],
                   rom_data[6], rom_data[4], rom_data[2], rom_data[0] };

always @(posedge clk) begin
    if( rst ) begin
        cur <= 0; last <= 0; nib_hi <= 1; playing <= 0; msm_rst <= 1; msm_din <= 0; rom_cs <= 0;
    end else begin
        rom_cs <= playing;
        if( adr_wr ) begin
            if( adr_hi ) last <= { din, 8'd0 };
            else begin cur <= { din, 8'd0 }; nib_hi <= 1; end
        end
        if( ctl_wr ) begin
            if( din == 8'd0 ) begin msm_rst <= 1; playing <= 0; end
            if( din == 8'd1 ) begin msm_rst <= 0; playing <= 1; end
        end
        if( vck && playing ) begin

            msm_din <= nib_hi ? dec[7:4] : dec[3:0];
            nib_hi  <= ~nib_hi;
            if( !nib_hi ) begin
                if( cur + 16'd1 >= last ) begin msm_rst <= 1; playing <= 0; end
                cur <= cur + 16'd1;
            end
        end
    end
end

`ifdef SIMULATION
always @(posedge clk) if( vck && playing && !rom_ok ) $display("[ADPCM] dato no listo en VCK, cur=%04X", cur);
`endif

jt5205 #(.INTERPOL(0)) u_msm(
    .rst    ( rst | msm_rst ),
    .clk    ( clk           ),
    .cen    ( cen375        ),
    .sel    ( 2'b10         ),
    .din    ( msm_din       ),
    .sound  ( snd           ),
    .sample ( sample        ),
    .irq    ( vck           ),
    .vclk_o (               )
);

endmodule
