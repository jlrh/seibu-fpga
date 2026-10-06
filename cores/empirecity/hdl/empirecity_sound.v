module empirecity_sound(
    input                rst,
    input                clk,
    input                cen3,
    input                cen1p5,

    input      [ 7:0]    snd_latch,
    input                snd_wr,
    input                fm_wr,
    output     [ 7:0]    fm_dout,

    output     [15:0]    rom_addr,
    output               rom_cs,
    input      [ 7:0]    rom_data,
    input                rom_ok,

    output        [ 9:0] psg0, psg1,
    output signed [15:0] fm0,  fm1,

    output        [ 7:0] snd_dbg,
    output        [ 7:0] snd_dbg2,

    output        [ 7:0] snd_dbg3
);
`ifndef NOSOUND
wire [15:0] A;
wire        iorq_n, m1_n, wr_n, rd_n, mreq_n, rfsh_n;
wire [ 7:0] ram_dout, dout, fm0_dout, fm1_dout;
reg  [ 7:0] din;
reg         fm0_cs, fm1_cs, latch_cs, ram_cs, rom_csr;

assign rom_addr = A;
assign rom_cs   = rom_csr;

always @(*) begin
    rom_csr  = 1'b0;
    ram_cs   = 1'b0;
    latch_cs = 1'b0;
    fm0_cs   = 1'b0;
    fm1_cs   = 1'b0;
    if( rfsh_n && !mreq_n )
        casez( A[15:11] )
            5'b0????: rom_csr  = 1'b1;
            5'b11000: fm0_cs   = 1'b1;
            5'b11001: fm1_cs   = 1'b1;
            5'b11110: latch_cs = 1'b1;
            5'b11111: ram_cs   = 1'b1;
            default:;
        endcase
end

reg  [7:0] fm_data;
reg        swr_l, fwr_l, latch_rd_l, wr_seen;
wire       wr_edge  = (snd_wr & ~swr_l) | (fm_wr & ~fwr_l);
wire       latch_rd = latch_cs && !rd_n;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        fm_data <= 8'h00; swr_l <= 1'b0; fwr_l <= 1'b0; latch_rd_l <= 1'b0; wr_seen <= 1'b0;
    end else begin
        swr_l <= snd_wr; fwr_l <= fm_wr; latch_rd_l <= latch_rd;

        if( !latch_rd )     wr_seen <= 1'b0;
        else if( wr_edge )  wr_seen <= 1'b1;
        if( wr_edge )
            fm_data <= { 1'b1, snd_latch[6:0] };
        else if( latch_rd_l && !latch_rd && !wr_seen )
            fm_data[7] <= 1'b0;
    end
end
assign fm_dout = fm_data;

localparam [14:0] IRQ_DIV = 15'd24999;
reg  [14:0] irq_cnt;
reg         snd_int, snd_int_l, int_n;
wire        irq_ack = ~iorq_n & ~m1_n;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        irq_cnt <= 15'd0; snd_int <= 1'b0; snd_int_l <= 1'b0; int_n <= 1'b1;
    end else if( cen3 ) begin

        if( irq_cnt==IRQ_DIV ) begin irq_cnt <= 15'd0; snd_int <= 1'b1; end
        else                   begin irq_cnt <= irq_cnt + 15'd1; snd_int <= 1'b0; end

        snd_int_l <= snd_int;
        if( irq_ack )                 int_n <= 1'b1;
        else if( snd_int & ~snd_int_l ) int_n <= 1'b0;
    end
end

reg  [1:0] fm_wait;
reg        wait_n, last_fmx, last_rom, rom_lock;
wire       fmx_cs = fm0_cs | fm1_cs;
wire       fmx_posedge = fmx_cs & ~last_fmx;
wire       fm_lock = |fm_wait;

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        fm_wait <= 2'b00; last_fmx <= 1'b0;
    end else if( cen3 ) begin
        last_fmx <= fmx_cs;
        fm_wait  <= { fm_wait[0], fmx_posedge };
    end
end

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        wait_n <= 1'b1; last_rom <= 1'b0; rom_lock <= 1'b0;
    end else begin
        last_rom <= rom_csr;
        if( rom_csr && !last_rom ) rom_lock <= 1'b1;
        if( rom_ok )               rom_lock <= 1'b0;
        wait_n   <= !fm_lock && !rom_lock;
    end
end

reg  [5:0] ini_cnt;
reg        init_done, ini_cs0, ini_cs1, ini_wrn;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        ini_cnt <= 6'd0; init_done <= 1'b0; ini_cs0 <= 1'b0; ini_cs1 <= 1'b0; ini_wrn <= 1'b1;
    end else if( cen1p5 && !init_done ) begin
        ini_cnt <= ini_cnt + 6'd1;
        case( ini_cnt )
            6'd8:  begin ini_cs0 <= 1'b1; ini_wrn <= 1'b0; end
            6'd10: begin ini_wrn <= 1'b1; end
            6'd12: begin ini_cs0 <= 1'b0; end
            6'd16: begin ini_cs1 <= 1'b1; ini_wrn <= 1'b0; end
            6'd18: begin ini_wrn <= 1'b1; end
            6'd20: begin ini_cs1 <= 1'b0; init_done <= 1'b1; end
            default:;
        endcase
    end
end

wire       ym0_csn = init_done ? ~fm0_cs : ~ini_cs0;
wire       ym1_csn = init_done ? ~fm1_cs : ~ini_cs1;
wire       ym_wrn  = init_done ? wr_n    : ini_wrn;
wire       ym_addr = init_done ? A[0]    : 1'b0;
wire [7:0] ym_din  = init_done ? dout    : 8'h2f;

always @(posedge clk) begin
    case( 1'b1 )
        rom_csr:  din <= rom_data;
        fm0_cs:   din <= fm0_dout;
        fm1_cs:   din <= fm1_dout;
        latch_cs: din <= fm_data;
        ram_cs:   din <= ram_dout;
        default:  din <= 8'hff;
    endcase
end

jtframe_ram #(.AW(11)) u_ram(
    .clk    ( clk               ),
    .cen    ( 1'b1              ),
    .data   ( dout              ),
    .addr   ( A[10:0]           ),
    .we     ( ram_cs && !wr_n   ),
    .q      ( ram_dout          )
);

jtframe_z80 u_cpu(
    .rst_n      ( ~rst & init_done ),
    .clk        ( clk         ),
    .cen        ( cen3        ),
    .wait_n     ( wait_n      ),
    .int_n      ( int_n       ),
    .nmi_n      ( 1'b1        ),
    .busrq_n    ( 1'b1        ),
    .m1_n       ( m1_n        ),
    .mreq_n     ( mreq_n      ),
    .iorq_n     ( iorq_n      ),
    .rd_n       ( rd_n        ),
    .wr_n       ( wr_n        ),
    .rfsh_n     ( rfsh_n      ),
    .halt_n     (             ),
    .busak_n    (             ),
    .A          ( A           ),
    .din        ( din         ),
    .dout       ( dout        )
);

wire [7:0] ym0_dbg, ym1_dbg;

jt03 u_fm0(
    .rst    ( rst        ),
    .clk    ( clk        ),
    .cen    ( cen1p5     ),
    .din    ( ym_din     ),
    .addr   ( ym_addr    ),
    .cs_n   ( ym0_csn    ),
    .wr_n   ( ym_wrn     ),
    .psg_snd( psg0       ),
    .fm_snd ( fm0        ),
    .snd_sample (        ),
    .dout   ( fm0_dout   ),
    .irq_n  (            ),
    .IOA_in ( 8'd0       ),  .IOB_in ( 8'd0 ),
    .IOA_out(            ),  .IOB_out(      ),
    .IOA_oe (            ),  .IOB_oe (      ),
    .psg_A  (            ),  .psg_B  (      ),  .psg_C(  ),
    .snd    (            ),
    .debug_view( ym0_dbg  )
);

jt03 u_fm1(
    .rst    ( rst        ),
    .clk    ( clk        ),
    .cen    ( cen1p5     ),
    .din    ( ym_din     ),
    .addr   ( ym_addr    ),
    .cs_n   ( ym1_csn    ),
    .wr_n   ( ym_wrn     ),
    .psg_snd( psg1       ),
    .fm_snd ( fm1        ),
    .snd_sample (        ),
    .dout   ( fm1_dout   ),
    .irq_n  (            ),
    .IOA_in ( 8'd0       ),  .IOB_in ( 8'd0 ),
    .IOA_out(            ),  .IOB_out(      ),
    .IOA_oe (            ),  .IOB_oe (      ),
    .psg_A  (            ),  .psg_B  (      ),  .psg_C(  ),
    .snd    (            ),
    .debug_view( ym1_dbg  )
);

reg  [15:0] fm0_pk;
reg  [21:0] pkwin;
wire [15:0] fm0_abs = fm0[15] ? (~fm0 + 16'd1) : fm0;
always @(posedge clk or posedge rst) begin
    if( rst ) begin fm0_pk <= 16'd0; pkwin <= 22'd0; end
    else begin
        pkwin <= pkwin + 22'd1;
        if( fm0_abs > fm0_pk ) fm0_pk <= fm0_abs;
        if( &pkwin ) fm0_pk <= 16'd0;
    end
end
assign snd_dbg3 = { fm0_pk[15:12], ym0_dbg[3:0] };

reg  [3:0] hb_m1;
reg        m1_dl;
always @(posedge clk or posedge rst) begin
    if( rst ) begin hb_m1 <= 4'd0; m1_dl <= 1'b1; end
    else begin
        m1_dl <= m1_n;
        if( !m1_n && m1_dl ) hb_m1 <= hb_m1 + 4'd1;
    end
end
assign snd_dbg = { wait_n, rom_lock, int_n, fm_lock, hb_m1 };

reg  [3:0] ym_wr_hb;
reg        ymwr_l;
wire       ymwr = (fm0_cs | fm1_cs) & ~wr_n;
reg [15:0] fm0_p, fm1_p;
reg [ 9:0] psg0_p, psg1_p;
reg        fm0_c, fm1_c, psg0_c, psg1_c;
reg        fm0_a, fm1_a, psg0_a, psg1_a;
reg [15:0] awin;
always @(posedge clk or posedge rst) begin
    if( rst ) begin
        ym_wr_hb<=4'd0; ymwr_l<=1'b0; awin<=16'd0;
        fm0_c<=0; fm1_c<=0; psg0_c<=0; psg1_c<=0;
        fm0_a<=0; fm1_a<=0; psg0_a<=0; psg1_a<=0;
        fm0_p<=0; fm1_p<=0; psg0_p<=0; psg1_p<=0;
    end else begin
        ymwr_l <= ymwr;
        if( ymwr && !ymwr_l ) ym_wr_hb <= ym_wr_hb + 4'd1;
        awin  <= awin + 16'd1;
        fm0_p <= fm0; fm1_p <= fm1; psg0_p <= psg0; psg1_p <= psg1;
        if( fm0 !=fm0_p  ) fm0_c  <= 1'b1;
        if( fm1 !=fm1_p  ) fm1_c  <= 1'b1;
        if( psg0!=psg0_p ) psg0_c <= 1'b1;
        if( psg1!=psg1_p ) psg1_c <= 1'b1;
        if( &awin ) begin
            fm0_a<=fm0_c; fm1_a<=fm1_c; psg0_a<=psg0_c; psg1_a<=psg1_c;
            fm0_c<=0; fm1_c<=0; psg0_c<=0; psg1_c<=0;
        end
    end
end
assign snd_dbg2 = { ym_wr_hb, fm1_a, fm0_a, psg1_a, psg0_a };
`else
    assign rom_addr = 16'd0;
    assign rom_cs   = 1'b0;
    assign fm_dout  = 8'd0;
    assign psg0     = 10'd0;
    assign psg1     = 10'd0;
    assign fm0      = 16'd0;
    assign fm1      = 16'd0;
    assign snd_dbg  = 8'd0;
    assign snd_dbg2 = 8'd0;
    assign snd_dbg3 = 8'd0;
`endif
`ifdef SIMULATION

reg [15:0] pc_max=0; reg [31:0] n_lat=0, n_rd=0, n_col=0, n_irq=0, n_irqtk=0, n_disp=0, n_pcyc=0; reg [19:0] sdbg=0;
reg [6:0] n_lrd=0; reg saw_pend=0; reg [7:0] last_cmd=0, last_pdin=0, cmd_h0=0, cmd_h1=0, cmd_h2=0, cmd_h3=0; reg [31:0] n_5be=0;
reg signed [15:0] fm0_min=16'sh7fff, fm0_max=16'sh8000;
reg m1_sl;
always @(posedge clk) begin
    m1_sl <= m1_n;
    if( wr_edge && latch_rd_l && !latch_rd ) n_col <= n_col + 1;
    if( !m1_n && m1_sl && A>pc_max && A<16'h8000 ) pc_max <= A;

    if( latch_rd_l && !latch_rd ) begin
        if( n_lrd<7'd40 ) begin n_lrd <= n_lrd + 7'd1;
            $display("[DIN] lectura 0xf000: din=%02h fm_data=%02h t=%0t", din, fm_data, $time); end
        if( din[7] ) begin saw_pend <= 1'b1; last_pdin <= din; end
    end
    if( fm_data[7] ) n_pcyc <= n_pcyc + 1;
    if( wr_edge ) begin last_cmd <= snd_latch;
        cmd_h0<=snd_latch; cmd_h1<=cmd_h0; cmd_h2<=cmd_h1; cmd_h3<=cmd_h2; end
    if( !m1_n && m1_sl && A==16'h05be ) n_5be <= n_5be + 1;

    if( snd_int & ~snd_int_l ) n_irq <= n_irq + 1;
    if( !m1_n && m1_sl && A==16'h0038 ) begin n_irqtk <= n_irqtk + 1;
        if( n_irqtk<3 ) $display("[IRQ] Z80 entra handler 0x0038 (#%0d) t=%0t", n_irqtk, $time); end

    if( !m1_n && m1_sl && A>=16'h0200 && A<16'h0700 ) begin n_disp <= n_disp + 1;
        if( n_disp<5 ) $display("[DISP] Z80 M1 en region FM @%04h t=%0t", A, $time); end
    if( wr_edge ) n_lat <= n_lat + 1;
    if( latch_cs && !latch_rd_l ) n_rd <= n_rd + 1;
    if( $signed(fm0) < fm0_min ) fm0_min <= fm0;
    if( $signed(fm0) > fm0_max ) fm0_max <= fm0;

    if( ymwr && !ymwr_l )
        $display("[YMW] %s a0=%b din=%02h  cmd=%02h  t=%0t",
                 fm0_cs?"YM0":"YM1", A[0], dout, fm_data, $time);
    sdbg <= sdbg + 1;
    if( sdbg==20'd0 )
        $display("[SND] lat_in=%0d n5be=%0d saw_pend=%b cmds=[%02h %02h %02h %02h] pdin=%02h | div=%b%b fm0=[%d,%d]",
                 n_lat, n_5be, saw_pend, cmd_h3, cmd_h2, cmd_h1, cmd_h0, last_pdin, ym0_dbg[1:0], ym1_dbg[1:0], fm0_min, fm0_max);
end
`endif
endmodule
