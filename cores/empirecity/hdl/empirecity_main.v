module empirecity_main(
    input             rst, clk, cen3, LVBL, dip_pause,

    output reg [17:0] main_addr,
    output reg        main_cs,
    input      [ 7:0] main_data,
    input             main_ok,

    input      [ 1:0] cab_1p, coin,
    input      [ 7:0] joystick1, joystick2,
    input             service,
    input      [ 7:0] dipsw_a, dipsw_b,

    output     [12:0] cpu_addr,
    output     [ 7:0] cpu_dout,
    output            cpu_rnw,
    output reg        vram_cs,
    input      [ 7:0] vram_dout,
    output reg        pal_cs,
    input      [ 7:0] pal_dout,
    output reg        vreg_cs, spr_cs,
    input      [ 7:0] vreg_dout, spr_dout,
    output     [ 9:0] sprbank_o,
    output reg        flip,

    output reg [ 7:0] snd_latch,
    output reg        snd_wr, fm_wr,
    input      [ 7:0] fm_dout,

    output     [ 7:0] cpu2mcu,
    output reg        mcu_we,
    input      [ 1:0] coin_valid,
    input             mcu_nmi_n
);
`ifndef NOMAIN
wire [15:0] A;
wire        rd_n, wr_n, mreq_n, rfsh_n, iorq_n, m1_n, rst_n, cpu_cen, busak_n;
reg  [ 7:0] cpu_din, cab_dout;
wire [ 7:0] ram_dout8;
reg         ram_cs, in_cs, coin_cs, io_cs, sprbank_cs;
reg  [ 1:0] bank;
reg  [ 9:0] sprbank;
reg  [ 1:0] coin_state;

assign cpu_addr  = A[12:0];
assign cpu_rnw   = wr_n;
assign sprbank_o = sprbank;
assign cpu2mcu   = cpu_dout;

always @(*) begin
    main_cs    = 1'b0;
    ram_cs     = 1'b0;
    pal_cs     = 1'b0;
    vram_cs    = 1'b0;
    vreg_cs    = 1'b0;
    spr_cs     = 1'b0;
    in_cs      = 1'b0;
    coin_cs    = 1'b0;
    io_cs      = 1'b0;
    sprbank_cs = 1'b0;
    snd_wr     = 1'b0;
    fm_wr      = 1'b0;
    mcu_we     = 1'b0;
    if( rfsh_n && !mreq_n ) begin
        casez( A[15:13] )
            3'b0??: main_cs = 1'b1;
            3'b10?: main_cs = 1'b1;
            3'b110: begin
                casez( A[12:8] )
                    5'b0000?: pal_cs  = 1'b1;
                    5'b00010: begin
                        in_cs   = (A[2:0] != 3'd5);
                        coin_cs = (A[2:0] == 3'd5);
                    end
                    5'b00101: begin
                        snd_wr = !wr_n; fm_wr = !wr_n;
                    end
                    5'b00110: mcu_we = !wr_n;
                    5'b00111: coin_cs = 1'b1;
                    5'b01000: begin
                        io_cs      = (A[3:0]==4'h4) && !wr_n;
                        sprbank_cs = (A[3:0]==4'h7) && !wr_n;
                    end
                    5'b10???: vram_cs = 1'b1;
                    5'b11???: vreg_cs = 1'b1;
                    default:;
                endcase
            end
            3'b111: begin
                ram_cs = !A[12];
                spr_cs =  A[12];
            end
        endcase
    end
end

always @(posedge clk) begin
    if( rst ) begin
        bank <= 2'd0; sprbank <= 10'd0; flip <= 1'b0; snd_latch <= 8'd0;
    end else if( cen3 ) begin

        if( sprbank_cs ) sprbank <= { cpu_dout[2], cpu_dout[0], 8'd0 };
        if( snd_wr )     snd_latch <= cpu_dout;
    end
end

always @(posedge clk) begin
    if( rst ) coin_state <= 2'b11;
    else begin
        if( cen3 && coin_cs && !wr_n ) begin
            if( !cpu_dout[0] ) coin_state[0] <= 1'b1;
            if( !cpu_dout[1] ) coin_state[1] <= 1'b1;
        end
        if( coin_valid[0] ) coin_state[0] <= 1'b0;
        if( coin_valid[1] ) coin_state[1] <= 1'b0;
    end
end

`ifdef SIMULATION

integer n_coinw=0, n_coinvalid=0, n_coinr=0;
reg [1:0] cst_p=2'b11, cline_p=2'b11;
always @(posedge clk) if( !rst ) begin
    if( cen3 && coin_cs && !wr_n ) begin
        n_coinw = n_coinw+1;
        $display("[COIN] L1 coin_w  A=%h d=%h -> arma (coin_state=%b) n=%0d", A, cpu_dout, coin_state, n_coinw);
    end
    if( coin_valid!=2'b00 ) begin
        n_coinvalid = n_coinvalid+1;
        $display("[COIN] L2 coin_valid=%b (MCU valida) n=%0d", coin_valid, n_coinvalid);
    end
    if( cen3 && coin_cs && !rd_n && A[2:0]==3'd5 ) begin
        n_coinr = n_coinr+1;
        if( coin_state!=2'b11 )
            $display("[COIN] L3 coin_r  <- %b  (!=11: el main VE la moneda) n=%0d", coin_state, n_coinr);
    end
    if( coin_state != cst_p )
        $display("[COIN] ** coin_state %b -> %b", cst_p, coin_state);
    cst_p <= coin_state;
    if( coin != cline_p ) begin
        $display("[COIN] linea de cabina coin %b -> %b (0=pulsado)", cline_p, coin);
    end
    cline_p <= coin;
end

`endif

always @(*) begin
    case( A[2:0] )
        3'd0: cab_dout = joystick1;
        3'd1: cab_dout = joystick2;

        3'd2: cab_dout = { 3'b111, cab_1p[1], cab_1p[0], 3'b111 };
        3'd3: cab_dout = dipsw_a;
        3'd4: cab_dout = dipsw_b;
        3'd5: cab_dout = { 6'h00, coin_state };
        default: cab_dout = 8'hff;
    endcase
end

wire is_opcode = ~m1_n;
always @(*) begin
    if( !A[15] )
        main_addr = { 3'b000, A[14:0] };
    else
        main_addr = { 2'b01, bank, A[13:0] };
end

function [7:0] dec_opc(input [7:0] s, input [14:0] a);
    dec_opc = { s[7], s[1]^s[3], s[5], ~(s[6]^a[7]), ~(s[0]^a[1]), s[2], s[1], s[1]^s[4] };
endfunction
function [7:0] dec_opr(input [7:0] s, input [14:0] a);
    dec_opr = { s[7], ~(s[1]^s[0]), s[5], s[3]^a[0], s[4]^a[4], s[2], s[1], ~(s[6]^a[0]) };
endfunction

wire [7:0] main_dec = !A[15] ? ( is_opcode ? dec_opc( main_data, A[14:0] )
                                           : dec_opr( main_data, A[14:0] ) )
                             : main_data;

jtframe_ram #(.AW(12)) u_ram(
    .clk ( clk ), .cen ( 1'b1 ), .data ( cpu_dout ),
    .addr( A[11:0] ), .we ( ram_cs && !wr_n ), .q ( ram_dout8 )
);

wire irq_ack = ~iorq_n && ~m1_n;
reg  [7:0] int_vec;
always @(posedge clk) begin
    cpu_din <= main_cs ? main_dec   :
               ram_cs  ? ram_dout8  :
               vram_cs ? vram_dout  :
               spr_cs  ? spr_dout   :
               vreg_cs ? vreg_dout  :
               pal_cs  ? pal_dout   :
               in_cs   ? cab_dout   :
               coin_cs ? { 6'h00, coin_state } : 8'hff;
    if( irq_ack ) cpu_din <= int_vec;
end

localparam [14:0] T120 = 15'd24999;
reg        irqn, LVBLl;
reg [14:0] tcnt;
reg        tarm;
always @(posedge clk) begin
    if( rst ) begin
        irqn <= 1'b1; LVBLl <= 1'b0; tcnt <= 15'd0; tarm <= 1'b0; int_vec <= 8'hcf;
    end else begin
        LVBLl <= LVBL;

        if( !LVBL && LVBLl ) begin
            if( dip_pause ) begin irqn <= 1'b0; int_vec <= 8'hcf; end
            tcnt <= 15'd0; tarm <= 1'b1;
        end

        if( tarm && cen3 ) begin
            if( tcnt==T120 ) begin
                tarm <= 1'b0;
                if( dip_pause ) begin irqn <= 1'b0; int_vec <= 8'hd7; end
            end else tcnt <= tcnt + 15'd1;
        end
        if( irq_ack ) irqn <= 1'b1;
    end
end

`ifdef SIMULATION

reg  m1_l2, lvbl_l, nmi_l; reg [15:0] pc_prev, js_l, jd_l; integer njmp=0;

reg [15:0] n_cf=0, n_d7=0;
always @(posedge clk) if( irq_ack ) begin
    if( int_vec==8'hcf ) n_cf <= n_cf + 16'd1;
    if( int_vec==8'hd7 ) n_d7 <= n_d7 + 16'd1;
end
reg  seen_pal, seen_tx, seen_mcu; reg [19:0] dbgcnt=0; reg [31:0] cencnt=0;
always @(posedge clk) begin
    lvbl_l <= LVBL; nmi_l <= mcu_nmi_n;
    if( cpu_cen && rst_n ) begin
        m1_l2 <= m1_n;
        if( !m1_n && m1_l2 ) begin
            if( (A > pc_prev+16'd8 || A+16'd8 < pc_prev) && njmp<120
                && !(pc_prev==js_l && A==jd_l) ) begin
                $display("[MAIN] PC %h -> %h", pc_prev, A); njmp=njmp+1;
                js_l<=pc_prev; jd_l<=A;
            end
            pc_prev <= A;
        end
    end

    dbgcnt <= dbgcnt + 1;
    if( cpu_cen ) cencnt <= cencnt + 1;
    if( dbgcnt == 20'd0 ) $display("[MAIN] tick PC=%h cencnt=%0d  IRQ cf=%0d d7=%0d  E00F=%h E43B=%h",
        pc_prev, cencnt, n_cf, n_d7, u_ram.mem[12'h00f], u_ram.mem[12'h43b]);
    if( mcu_we && !seen_mcu ) begin $display("[MAIN] >>> write MCU (0xc600) D=%h", cpu_dout); seen_mcu<=1; end
    if( nmi_l && !mcu_nmi_n ) $display("[MAIN] >>> NMI de la MCU");
    if( pal_cs && !wr_n && !seen_pal ) begin $display("[MAIN] >>> 1er write PALETA A=%h", A); seen_pal<=1; end
    if( vram_cs && !wr_n && !seen_tx ) begin $display("[MAIN] >>> 1er write TXRAM A=%h", A); seen_tx<=1; end
end
`endif

jt12_rst u_rst( .rst(rst), .clk(clk), .rst_n(rst_n) );

jtframe_z80wait #(.DEVCNT(1)) u_wait(
    .rst_n   ( rst_n            ),
    .clk     ( clk              ),
    .cen_in  ( cen3             ),
    .cen_out ( cpu_cen          ),
    .gate    (                  ),
    .mreq_n  ( mreq_n & m1_n    ),
    .iorq_n  ( iorq_n           ),
    .busak_n ( busak_n          ),
    .dev_busy( 1'b0             ),
    .rom_cs  ( main_cs          ),
    .rom_ok  ( main_ok          )
);

jtframe_z80 u_cpu(
    .rst_n  ( rst_n     ),
    .clk    ( clk       ),
    .cen    ( cpu_cen   ),
    .wait_n ( 1'b1      ),
    .int_n  ( irqn      ),
    .nmi_n  ( mcu_nmi_n ),
    .busrq_n( 1'b1      ),
    .m1_n   ( m1_n      ),
    .mreq_n ( mreq_n    ),
    .iorq_n ( iorq_n    ),
    .rd_n   ( rd_n      ),
    .wr_n   ( wr_n      ),
    .rfsh_n ( rfsh_n    ),
    .halt_n (           ),
    .busak_n( busak_n   ),
    .A      ( A         ),
    .din    ( cpu_din   ),
    .dout   ( cpu_dout  )
);
`else
assign main_addr=0; assign main_cs=0; assign cpu_addr=0; assign cpu_dout=0; assign cpu_rnw=1;
assign vram_cs=0; assign pal_cs=0; assign vreg_cs=0; assign spr_cs=0; assign flip=0;
assign sprbank_o=0;
assign snd_latch=0; assign snd_wr=0; assign fm_wr=0; assign cpu2mcu=0; assign mcu_we=0;
`endif
endmodule
