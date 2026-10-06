set clk48 [get_clocks {emu|clk_sys}]
set clk96 [get_clocks {emu|pll|pll_inst|altera_pll_i|*[0].*|divclk}]

set_multicycle_path -from $clk48 -to $clk96 -setup 2
set_multicycle_path -from $clk48 -to $clk96 -hold  1
set_multicycle_path -from $clk96 -to $clk48 -setup 2
set_multicycle_path -from $clk96 -to $clk48 -hold  1
