/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_shared -- 4 kB RAM shared by the two V30 ("share1", MAME deadang.cpp:494/540).
    True dual port: port 0 = main, port 1 = sub. The main serialises its accesses with the lock bit
    (0xE068 bit 7 = 0); while it is held the sub's accesses wait (sub_wait -> READY low).
    MAME does not emulate the lock ("0x80: Always set?"), see GAPS-REPORT.md O1.
*/

module deadang_shared(
    input             clk,
    input             lock,

    input      [11:1] main_addr,
    input      [15:0] main_din,
    input       [1:0] main_we,
    output     [15:0] main_dout,

    input      [11:1] sub_addr,
    input      [15:0] sub_din,
    input       [1:0] sub_we,
    output     [15:0] sub_dout,
    output            sub_wait
);

assign sub_wait = lock;

jtframe_dual_ram16 #(.AW(11)) u_ram(
    .clk0 ( clk ), .data0( main_din ), .addr0( main_addr ), .we0( main_we ), .q0( main_dout ),
    .clk1 ( clk ), .data1( sub_din  ), .addr1( sub_addr  ), .we1( sub_we  ), .q1( sub_dout  )
);

endmodule
