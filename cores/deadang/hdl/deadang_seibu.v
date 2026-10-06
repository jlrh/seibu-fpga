/*  This file is part of the deadang core (Dead Angle, Seibu 1988) for MiSTer. GPL v3 or later.

    deadang_seibu -- the SEI0100 "YM3931" side of the Seibu Sound System as MAME 0.288 models it
    (src/mame/shared/seibusound.cpp:137-316):
      main side (umask 0x00FF, offset = A[3:1]):
        w0/w1 main2sub[0/1]   w4 RST18 assert   w2/w6 sub2main_pending=0, main2sub_pending=1
        r2/r3 sub2main[0/1]   r5 main2sub_pending   other reads 0xFF
      Z80 side: 4000 pending_w (main2sub_pending=0, sub2main_pending=1)  4001 RST18 EOI
                4002 RST10 EOI  4003 RST18 EOI  4010/4011 main2sub  4012 sub2main_pending
                4013 coins  4018/4019 sub2main
      Z80 INT = (rst10 && !rst10_service) || (rst18 && !rst18_service); IM0 vector on INTA:
      0xDF (RST18, priority) -> rst18_service=1, rst18=0 ; else 0xD7 (RST10) -> rst10_service=1.
      rst10 follows the YM2203 #1 IRQ line (level).
*/

module deadang_seibu(
    input             rst,
    input             clk,

    input       [2:0] m_addr,
    input       [7:0] m_din,
    input             m_wr,
    input             m_rd,
    output reg  [7:0] m_dout,

    input       [4:0] z_addr,
    input       [7:0] z_din,
    input             z_wr,
    output reg  [7:0] z_dout,
    input             z_inta,
    output      [7:0] z_vector,
    output            z_int_n,

    input             ym_irq,
    input       [1:0] coin
);

reg [7:0] main2sub[0:1], sub2main[0:1];
reg       main2sub_pending, sub2main_pending;
reg       rst10, rst18, rst10_srv, rst18_srv;

assign z_int_n  = ~((rst10 && !rst10_srv) || (rst18 && !rst18_srv));
assign z_vector = (rst18 && !rst18_srv) ? 8'hDF : (rst10 && !rst10_srv) ? 8'hD7 : 8'h00;

always @(*) begin
    case( m_addr )
        3'd2: m_dout = sub2main[0];
        3'd3: m_dout = sub2main[1];
        3'd5: m_dout = { 7'd0, main2sub_pending };
        default: m_dout = 8'hFF;
    endcase
    case( z_addr )
        5'h10: z_dout = main2sub[0];
        5'h11: z_dout = main2sub[1];
        5'h12: z_dout = { 7'd0, sub2main_pending };
        5'h13: z_dout = { 6'd0, coin };
        default: z_dout = 8'hFF;
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        main2sub[0] <= 0; main2sub[1] <= 0;
        sub2main[0] <= 0; sub2main[1] <= 0;
        main2sub_pending <= 0; sub2main_pending <= 0;
        rst10 <= 0; rst18 <= 0; rst10_srv <= 0; rst18_srv <= 0;
    end else begin
        rst10 <= ym_irq;

        if( z_inta ) begin
            if( rst18 && !rst18_srv ) begin rst18_srv <= 1; rst18 <= 0; end
            else if( rst10 && !rst10_srv ) rst10_srv <= 1;
        end
        if( m_wr ) case( m_addr )
            3'd0: main2sub[0] <= m_din;
            3'd1: main2sub[1] <= m_din;
            3'd4: rst18 <= 1;
            3'd2, 3'd6: begin sub2main_pending <= 0; main2sub_pending <= 1; end
            default:;
        endcase
        if( z_wr ) case( z_addr )
            5'h00: begin main2sub_pending <= 0; sub2main_pending <= 1; end
            5'h01: rst18_srv <= 0;
            5'h02: rst10_srv <= 0;
            5'h03: rst18_srv <= 0;
            5'h18: sub2main[0] <= z_din;
            5'h19: sub2main[1] <= z_din;
            default:;
        endcase
    end
end

endmodule
