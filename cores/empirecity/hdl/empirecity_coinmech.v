module empirecity_coinmech #( parameter W = 19, parameter [W-1:0] WIDTH = 19'd399000 )(
    input            rst,
    input            clk,
    input            cen,
    input      [1:0] coin_btn,
    output     [1:0] coin_mech
);

genvar gi;
generate
    for( gi=0; gi<2; gi=gi+1 ) begin : gen_mech
        reg [W-1:0] cnt;
        reg         act, arm, btn_l;
        always @(posedge clk or posedge rst) begin
            if( rst ) begin
                cnt <= {W{1'b0}}; act <= 1'b0; arm <= 1'b1; btn_l <= 1'b1;
            end else if( cen ) begin
                btn_l <= coin_btn[gi];
                if( arm && btn_l && !coin_btn[gi] ) begin
                    act <= 1'b1; arm <= 1'b0; cnt <= WIDTH;
                end else if( act ) begin
                    if( cnt!={W{1'b0}} ) cnt <= cnt-1'd1; else act <= 1'b0;
                end
                if( !act && coin_btn[gi] ) arm <= 1'b1;
            end
        end
        assign coin_mech[gi] = ~act;
    end
endgenerate

endmodule
