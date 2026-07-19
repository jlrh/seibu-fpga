# SDC — cruce clk48 <-> clk96 (SDRAM). Obligatorio en todo core CLK48+SDRAM96 (GOTCHAS E1).
# Multicycle setup2/hold1 en el cruce de dominios; sin esto -> slack negativo -> freeze board-dependent.
set clk48 [get_clocks {emu|clk_sys}]
set clk96 [get_clocks {emu|pll|pll_inst|altera_pll_i|*[0].*|divclk}]

set_multicycle_path -from $clk48 -to $clk96 -setup 2
set_multicycle_path -from $clk48 -to $clk96 -hold  1
set_multicycle_path -from $clk96 -to $clk48 -setup 2
set_multicycle_path -from $clk96 -to $clk48 -hold  1
# Nota: los nombres de reloj se afinan tras el primer fit (Fase 5); jtframe suele proveer el .sdc base.
