//  synthesis attribute "shape"` came from a COMMENT on this line.  Harmless

module v30u_ucrom #(

    //   Quartus     cwd = hdl/            (hdl/nec_test.qpf)

`ifdef UCORE_HEXDIR
    parameter string HEXDIR = `UCORE_HEXDIR
`else
    parameter string HEXDIR = ""
`endif
) (

    input      [12:0] dec_addr,
    output            dec_valid,
    output      [8:0] dec_bank,

    input      [10:0] rom_addr,
    output     [28:0] rom_word
);

// synthesis, and `dec_w[9:0]` below is the word.
reg [11:0] ucdecode [0:8191];
reg [28:0] ucrom    [0:1027];

initial begin
    $readmemh({HEXDIR, "ucdecode.hex"}, ucdecode);
    $readmemh({HEXDIR, "ucrom.hex"}, ucrom);
`ifndef SYNTHESIS
    if (ucrom[0] === 29'd0 || (^ucrom[0]) === 1'bx)
        $fatal(1, "v30u_ucrom: ucrom.hex did not load from '%s' -- the ROM is EMPTY (F44)", HEXDIR);
    if (ucrom[1027] === 29'd0 || (^ucrom[1027]) === 1'bx)
        $fatal(1, "v30u_ucrom: ucrom.hex is SHORT from '%s' -- row 1027 never loaded (F44)", HEXDIR);
    if (ucdecode[13'h0000] === 12'd0 || (^ucdecode[13'h0000]) === 1'bx)
        $fatal(1, "v30u_ucrom: ucdecode.hex did not load from '%s' -- the decode table is EMPTY (F44)", HEXDIR);
    if (ucdecode[13'h1E43] === 12'd0 || (^ucdecode[13'h1E43]) === 1'bx)
        $fatal(1, "v30u_ucrom: ucdecode.hex is SHORT from '%s' -- the last valid entry (0x1E43) never loaded (F44)", HEXDIR);
`endif
end

`ifndef SYNTHESIS

// SYNTHESIS side of F44 is therefore not this assertion: it is the `ifdef`ed

`endif

wire [9:0] dec_w = ucdecode[dec_addr][9:0];

assign dec_valid = dec_w[9];
assign dec_bank  = dec_w[8:0];
assign rom_word  = ucrom[rom_addr];

endmodule
