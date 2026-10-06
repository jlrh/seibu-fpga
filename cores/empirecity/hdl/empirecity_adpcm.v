module empirecity_adpcm(
    input                rst, clk, cenp384,
    input      [ 7:0]    start_hi,
    input                adpcm_rst,
    output reg           mcu_irq,
    output     [14:0]    rom_addr,
    output               rom_cs,
    input      [ 7:0]    rom_data,
    input                rom_ok,
    output signed [11:0] pcm
);
`ifndef NOSOUND
wire signed [11:0] pcm_raw;

jtframe_dcrm #(.SW(12), .SIGNED_INPUT(1)) u_pcm_dcrm(
    .rst( rst ), .clk( clk ), .sample( cenp384 ), .din( pcm_raw ), .dout( pcm )
);
reg  [15:0] offs;
reg  [ 3:0] nibble;
reg         adpcm_rst_l, irq_l;
wire        vck_irq;

assign rom_addr = offs[15:1];
assign rom_cs   = ~adpcm_rst;

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        offs <= 16'd0; nibble <= 4'd0; adpcm_rst_l <= 1'b1; irq_l <= 1'b0; mcu_irq <= 1'b0;
    end else begin
        adpcm_rst_l <= adpcm_rst;
        irq_l       <= vck_irq;

        if( adpcm_rst_l && !adpcm_rst ) offs <= { start_hi[6:0], 9'd0 };

        if( vck_irq && !irq_l ) begin
            mcu_irq <= ~mcu_irq;
            if( !adpcm_rst ) begin
                nibble <= offs[0] ? rom_data[3:0] : rom_data[7:4];
                offs   <= offs + 16'd1;
            end
        end
    end
end

`ifdef SIMULATION
reg [31:0] vckcnt=0, p384cnt=0; reg [19:0] ac=0; reg vl;
always @(posedge clk) begin
    ac<=ac+1; if(cenp384) p384cnt<=p384cnt+1; vl<=vck_irq; if(vck_irq&&!vl) vckcnt<=vckcnt+1;
    if(ac==20'd0) $display("[ADPCM] cenp384_pulsos=%0d VCK_pulsos=%0d mcu_irq=%b", p384cnt, vckcnt, mcu_irq);
end
`endif

jt5205 #(.INTERPOL(0)) u_msm(
    .rst    ( rst              ),
    .clk    ( clk              ),
    .cen    ( cenp384          ),
    .sel    ( 2'b10            ),
    .din    ( adpcm_rst ? 4'd8 : nibble ),
    .sound  ( pcm_raw          ),
    .sample (                  ),
    .irq    ( vck_irq          ),
    .vclk_o (                  )
);
`else
    assign rom_addr = 0; assign rom_cs = 0; assign pcm = 0;
    initial mcu_irq = 0;
`endif
endmodule
