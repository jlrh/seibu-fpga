module empirecity_mcu(
    input             rst, clk, cen3,

    input      [ 7:0] cpu2mcu,
    input             mcu_we,

    output            mcu_nmi_n,
    output reg [ 1:0] coin_valid,

    input      [ 1:0] coin,

    output     [ 7:0] adpcm_start,
    output            adpcm_rst,
    input             mcu_irq,

    output     [10:0] rom_addr,
    input      [ 7:0] rom_data
);
`ifndef NOMAIN
wire [7:0] pa_out, pb_out, mcu_db;
wire [3:0] pc_out;
wire [12:0] mcu_ab;
wire        mcu_wr;
reg  [3:0] c2m_data;
reg        c2m_empty;
reg  [7:0] pcout_r;
reg        nmin_r, arst_r;

wire [1:0] coin_mech;

empirecity_coinmech u_coinmech(
    .rst      ( rst       ),
    .clk      ( clk       ),
    .cen      ( cen3      ),
    .coin_btn ( coin      ),
    .coin_mech( coin_mech )
);

wire [7:0] pb_in = { coin_mech[1:0], 1'b0, c2m_empty, c2m_data };

wire pb_ack = mcu_wr && (mcu_ab==13'd1) && !mcu_db[5];

wire pc_wr = mcu_wr && cen3 && (mcu_ab==13'd2);
assign adpcm_start = pa_out;
assign adpcm_rst   = arst_r;
assign mcu_nmi_n   = nmin_r;

always @(posedge clk or posedge rst) begin
    if( rst ) begin
        c2m_data <= 4'd0; c2m_empty <= 1'b1; coin_valid <= 2'b00;
        pcout_r <= 8'hff; nmin_r <= 1'b1; arst_r <= 1'b1;
    end else begin
        coin_valid <= 2'b00;

        if( mcu_we )        begin c2m_data <= cpu2mcu[3:0]; c2m_empty <= 1'b0; end
        else if( pb_ack )   c2m_empty <= 1'b1;

        if( pc_wr ) begin
            if( pcout_r[0] && !mcu_db[0] ) coin_valid[0] <= 1'b1;
            if( pcout_r[1] && !mcu_db[1] ) coin_valid[1] <= 1'b1;
            arst_r  <= mcu_db[2];
            nmin_r  <= mcu_db[3];
            pcout_r <= mcu_db;
        end
    end
end

`ifdef SIMULATION

reg [10:0] ra_p; integer nra=0, nw=0;
always @(posedge clk) if(cen3 && !rst) begin
    if( rom_addr!=ra_p && nra<40 ) begin
        $display("[MCU] fetch addr=%h data=%h irq=%b", rom_addr, rom_data, mcu_irq); nra=nra+1;
    end
    ra_p <= rom_addr;
    if( mcu_wr && mcu_ab<13'd10 && nw<30 ) begin
        $display("[MCU] wr reg%0d = %h", mcu_ab, mcu_db); nw=nw+1;
    end
end

reg [1:0] cin_p=2'b11, cmech_p=2'b11;
integer n_pcwr=0;
always @(posedge clk) if(!rst) begin
    if( coin != cin_p )
        $display("[MCU-COIN] BOTON coin %b -> %b (0=pulsado)", cin_p, coin);
    cin_p <= coin;

    if( coin_mech != cmech_p )
        $display("[MCU-COIN] pb_in[7:6] (mech) %b -> %b (0=moneda)", cmech_p, coin_mech);
    cmech_p <= coin_mech;
    if( pc_wr ) begin
        n_pcwr = n_pcwr+1;
        if( n_pcwr<200 || mcu_db[1:0]!=2'b11 )
            $display("[MCU-COIN] portC wr %h -> %h (bit0/1=coin valid en flanco bajo)",
                     pcout_r, mcu_db);
    end
end
reg nmin_p=1;
always @(posedge clk) begin
    if( nmin_p && !nmin_r ) $display("[MCU] >>> NMI ASSERT (pcout=%h)", pcout_r);
    if( !nmin_p && nmin_r ) $display("[MCU] >>> NMI clear");
    nmin_p <= nmin_r;
end
`endif

jtframe_6805mcu u_mcu(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .cen    ( cen3      ),
    .wr     ( mcu_wr    ),
    .addr   ( mcu_ab    ),
    .dout   ( mcu_db    ),
    .irq    ( mcu_irq   ),
    .timer  ( 1'b0      ),
    .pa_in  ( 8'hff     ),
    .pa_out ( pa_out    ),
    .pb_in  ( pb_in     ),
    .pb_out ( pb_out    ),
    .pc_in  ( 4'hf      ),
    .pc_out ( pc_out    ),
    .rom_addr( rom_addr ),
    .rom_data( rom_data ),
    .rom_cs (           )
);
`else
assign mcu_nmi_n=1; assign adpcm_start=0; assign adpcm_rst=1; assign rom_addr=0;
initial coin_valid=0;
`endif
endmodule
