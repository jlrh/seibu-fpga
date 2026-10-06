/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_sound -- Seibu Sound System as used by Dead Angle (MAME 0.288 deadang.cpp:554-575, 822-851)
      Z80 @ 3.579545 MHz, IM0 vectors from the YM3931 (deadang_seibu)
      0000-1FFF ROM 13.b1, SEI80BU-encrypted (deadang_sei80bu, opcode table when M1)
      2000-27FF RAM (2 kB, inside jtframe_sysz80)
      4000-401F YM3931 registers  4005/4006 ADPCM1 start/end  4007 bank  4008/4009 YM2203 #1
      401A ADPCM1 ctl  401B coin counters
      6005/6006 ADPCM2 start/end  6008/6009 YM2203 #2  601A ADPCM2 ctl
      8000-FFFF 32 kB bank of 14.c1 (bank bit 0), NOT encrypted
    Sound ROM bus: region "audiocpu" as in MAME: 13.b1 @0x00000, 14.c1 @0x10000 (128 kB).
*/

module deadang_sound(
    input             rst,
    input             clk,
    input             cen_fm,
    input             cen375,

    input       [2:0] m_addr,
    input       [7:0] m_din,
    input             m_wr,
    input             m_rd,
    output      [7:0] m_dout,

    input       [1:0] coin,

    output     [16:0] rom_addr,
    output            rom_cs,
    input       [7:0] rom_data,
    input             rom_ok,

    output     [15:0] pcm0_addr,
    output            pcm0_cs,
    input       [7:0] pcm0_data,
    input             pcm0_ok,
    output     [15:0] pcm1_addr,
    output            pcm1_cs,
    input       [7:0] pcm1_data,
    input             pcm1_ok,

    output signed [15:0] fm0, fm1,
    output        [ 9:0] psg0, psg1,
    output signed [11:0] pcm0, pcm1,

    output        [ 7:0] dbg
);

wire [15:0] A;
wire  [7:0] cpu_dout, ram_dout, sb_dout, ym0_dout, ym1_dout, z_vector;
reg   [7:0] cpu_din;
wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, int_n, cpu_cen;
wire        ym0_irq_n, ym1_irq_n;
reg         bank;

wire mem    = !mreq_n && rfsh_n;
wire enc_cs = mem && A[15:13] == 3'b000;
wire ram_cs = mem && A[15:11] == 5'b0010_0;
wire bnk_cs = mem && A[15];
wire io4_cs = mem && A[15:5] == 11'b0100_0000_000;
wire io6_cs = mem && A[15:5] == 11'b0110_0000_000;
assign rom_cs   = enc_cs || bnk_cs;
assign rom_addr = A[15] ? { 1'b1, bank, A[14:0] } : { 4'd0, A[12:0] };

wire [7:0] dec_data;
deadang_sei80bu u_dec( .a( A ), .din( rom_data ), .m1( ~m1_n ), .dout( dec_data ) );

reg wr_l;
always @(posedge clk) wr_l <= !wr_n;
wire wr = !wr_n && !wr_l;
wire w4 = wr && io4_cs, w6 = wr && io6_cs;

reg inta_l;
reg [7:0] vec_l;
wire inta_now = !m1_n && !iorq_n;
always @(posedge clk) inta_l <= inta_now;
wire z_inta = inta_now && !inta_l;

always @(posedge clk) if( z_inta ) vec_l <= z_vector;
wire [7:0] vector = z_inta ? z_vector : vec_l;

always @(posedge clk) begin
    if( rst ) bank <= 0;
    else if( w4 && A[4:0] == 5'h07 ) bank <= cpu_dout[0];
end

always @(*) begin
    cpu_din = 8'hFF;
    if( inta_now )     cpu_din = vector;
    else if( enc_cs )  cpu_din = dec_data;
    else if( bnk_cs )  cpu_din = rom_data;
    else if( ram_cs )  cpu_din = ram_dout;
    else if( io4_cs )  cpu_din = A[4:1] == 4'b0100 ? ym0_dout : sb_dout;
    else if( io6_cs && A[4:1] == 4'b0100 ) cpu_din = ym1_dout;
end

deadang_seibu u_seibu(
    .rst      ( rst        ),
    .clk      ( clk        ),
    .m_addr   ( m_addr     ),
    .m_din    ( m_din      ),
    .m_wr     ( m_wr       ),
    .m_rd     ( m_rd       ),
    .m_dout   ( m_dout     ),
    .z_addr   ( A[4:0]     ),
    .z_din    ( cpu_dout   ),
    .z_wr     ( w4         ),
    .z_dout   ( sb_dout    ),
    .z_inta   ( z_inta     ),
    .z_vector ( z_vector   ),
    .z_int_n  ( int_n      ),
    .ym_irq   ( ~ym0_irq_n ),
    .coin     ( coin       )
);

jtframe_sysz80 #(.RAM_AW(11)) u_cpu(
    .rst_n    ( ~rst      ),
    .clk      ( clk       ),
    .cen      ( cen_fm    ),
    .cpu_cen  ( cpu_cen   ),
    .int_n    ( int_n     ),
    .nmi_n    ( 1'b1      ),
    .busrq_n  ( 1'b1      ),
    .m1_n     ( m1_n      ),
    .mreq_n   ( mreq_n    ),
    .iorq_n   ( iorq_n    ),
    .rd_n     ( rd_n      ),
    .wr_n     ( wr_n      ),
    .rfsh_n   ( rfsh_n    ),
    .halt_n   (           ),
    .busak_n  (           ),
    .A        ( A         ),
    .cpu_din  ( cpu_din   ),
    .cpu_dout ( cpu_dout  ),
    .ram_dout ( ram_dout  ),
    .ram_cs   ( ram_cs    ),
    .rom_cs   ( rom_cs    ),
    .rom_ok   ( rom_ok    )
);

wire ym0_cs_n = !(io4_cs && A[4:1] == 4'b0100);
wire ym1_cs_n = !(io6_cs && A[4:1] == 4'b0100);

jt03 u_ym0(
    .rst(rst), .clk(clk), .cen(cen_fm), .din(cpu_dout), .addr(A[0]), .cs_n(ym0_cs_n), .wr_n(wr_n),
    .dout(ym0_dout), .irq_n(ym0_irq_n),
    .IOA_in(8'hFF), .IOB_in(8'hFF), .IOA_out(), .IOB_out(), .IOA_oe(), .IOB_oe(),
    .psg_A(), .psg_B(), .psg_C(), .fm_snd(fm0), .psg_snd(psg0), .snd(), .snd_sample(), .debug_view()
);
jt03 u_ym1(
    .rst(rst), .clk(clk), .cen(cen_fm), .din(cpu_dout), .addr(A[0]), .cs_n(ym1_cs_n), .wr_n(wr_n),
    .dout(ym1_dout), .irq_n(ym1_irq_n),
    .IOA_in(8'hFF), .IOB_in(8'hFF), .IOA_out(), .IOB_out(), .IOA_oe(), .IOB_oe(),
    .psg_A(), .psg_B(), .psg_C(), .fm_snd(fm1), .psg_snd(psg1), .snd(), .snd_sample(), .debug_view()
);

deadang_adpcm u_pcm0(
    .rst(rst), .clk(clk), .cen375(cen375),
    .adr_wr( w4 && (A[4:0] == 5'h05 || A[4:0] == 5'h06) ), .adr_hi( A[4:0] == 5'h06 ),
    .ctl_wr( w4 && A[4:0] == 5'h1A ), .din( cpu_dout ),
    .rom_addr(pcm0_addr), .rom_cs(pcm0_cs), .rom_data(pcm0_data), .rom_ok(pcm0_ok),
    .snd(pcm0), .sample()
);
deadang_adpcm u_pcm1(
    .rst(rst), .clk(clk), .cen375(cen375),
    .adr_wr( w6 && (A[4:0] == 5'h05 || A[4:0] == 5'h06) ), .adr_hi( A[4:0] == 5'h06 ),
    .ctl_wr( w6 && A[4:0] == 5'h1A ), .din( cpu_dout ),
    .rom_addr(pcm1_addr), .rom_cs(pcm1_cs), .rom_data(pcm1_data), .rom_ok(pcm1_ok),
    .snd(pcm1), .sample()
);

assign dbg = { ~int_n, bank, ~ym0_irq_n, 5'd0 };

endmodule
