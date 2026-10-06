module v30_core (
    input             CLK,
    input             CE,
`ifdef V30_MUXED_AD
    input             CE_HALF,

`endif
    input             RESET,
    input             READY,
    input             INT,
    input             NMI,
    input             POLL_N,
`ifdef V30_MUXED_AD

    inout      [19:0] AD,
    output     [19:0] AD_OE,
`else

    input      [15:0] DATA_I,
`endif

    output     [19:0] ADDR_O,
    output     [15:0] DATA_O,
    output      [3:0] STATUS_O,
    output      [1:0] QS,
    output      [2:0] BS,
    output            RD_N,
    output            UBE_N,
    output            BUSLOCK_N,
    input [v30_ss_pkg::SS_ADDR_W-1:0] SS_ADDR,
    input      [15:0] SS_WDATA,
    input             SS_WE,
    output     [15:0] SS_RDATA,
    output reg        SS_ERR,
    output            SS_BUS_QUIET
`ifdef V30_BACKDOOR
    ,
    input             bkd_load,
    input     [223:0] bkd_regs,
    input      [47:0] bkd_queue,
    input       [2:0] bkd_qlen,
    input      [15:0] bkd_fetch_ip,
    input             scr_en,
    input       [1:0] scr_qop,
    output    [223:0] dbg_regs,
    output            dbg_first_pop,
    output            dbg_pend
`endif
);

import v30_ss_pkg::*;

`ifndef V30_BACKDOOR
logic         bkd_load = 1'b0;
logic [223:0] bkd_regs = '0;
logic  [47:0] bkd_queue = '0;
logic   [2:0] bkd_qlen = '0;
logic  [15:0] bkd_fetch_ip = '0;
logic         scr_en = 1'b0;
logic   [1:0] scr_qop = '0;
`endif

wire  [7:0] q_byte;
wire        q_ripe, q_ripe_lead_n;
wire  [3:0] q_cnt;
wire        eu_ghost_full, eu_ghost_idle, eu_ghost_stack_first;

wire        eu_ghost_row, eu_ghost_acc;
wire [19:0] eu_ghost_sp, eu_ghost_bare;
wire        eu_pop, eu_first, eu_flush;
wire        eu_flush_pre, eu_flush_rep, eu_flush_stage, eu_flush_pend;
wire        eu_flush_nmi, eu_flush_int_live;
wire [15:0] eu_flush_cs, eu_flush_cs_old, eu_flush_ip;
wire        eu_flush_cs_we;
wire        eu_post, eu_post_hold, eu_halt_irq, eu_vector_post;
wire        eu_word, eu_pair, eu_pair2, eu_split;
wire        eu_slot_busy, eu_slot_busy_n, eu_access_active;
wire        eu_direct_fetch, eu_fetch_tail;
wire  [2:0] eu_bs;
wire [19:0] eu_addr, eu_addr2;
wire  [1:0] eu_seg, eu_seg2;
wire [15:0] eu_wdata, eu_rdata_n;
wire        eu_rd_done_n, eu_wr_done_n, eu_wr_eval;
wire        eu_rd_edge;
wire [15:0] eu_rd_edge_d;
wire        eu_opr_free;
wire        eu_susp, eu_resume, eu_halt, eu_unhalt, biu_halted;
wire        eu_unhalt_disp;
wire        eu_bnd_take, eu_bnd_post;
wire        psw_ie, md8080;
wire [15:0] ss_eu_rdata, ss_biu_rdata;
wire        ss_biu_bus_quiet;
reg   [8:0] ss_addr_q;
reg  [15:0] ss_wdata_q;
reg         ss_we_q;
reg         ss_sel_eu_q, ss_sel_tag_q;

always_ff @(posedge CLK) begin
    ss_addr_q    <= SS_ADDR;
    ss_wdata_q   <= SS_WDATA;
    ss_we_q      <= SS_WE;
    ss_sel_eu_q  <= ss_addr_q[8];
    ss_sel_tag_q <= (ss_addr_q == SSA_TAG);
end

assign SS_RDATA = ss_sel_tag_q ? SS_TAG
                : ss_sel_eu_q  ? ss_eu_rdata : ss_biu_rdata;

always_ff @(posedge CLK) begin
    if (RESET) SS_ERR <= 1'b0;
    else if (ss_we_q && ss_addr_q == SSA_TAG)
        SS_ERR <= (ss_wdata_q != SS_TAG);
end

assign SS_BUS_QUIET = ss_biu_bus_quiet;

`ifndef SYNTHESIS
`ifdef V30_MUXED_AD

logic ce_half_since_ce = 1'b1;

always @(posedge CLK) begin
    if (CE && CE_HALF)
        $fatal(1, "v30_core: ce/ce_half CONTRACT VIOLATED (C-a) at %0t -- CE and CE_HALF asserted on the SAME fabric clock.  They may be adjacent; they may not coincide.  USER RULING 2026-08-13; see hdl/nec_test.sdc and docs/notes/ce_contract_correction_prereg_2026-08-13.md.",
               $time);

    if (CE && !ce_half_since_ce)
        $fatal(1, "v30_core: ce/ce_half REQUIREMENT VIOLATED (S-1) at %0t -- two CEs with NO CE_HALF between them.  CE_HALF is the only enable on t1_half2, which is the T1 address->data turnaround gating ad_oe_data: without it the BIU leaves the ADDRESS on AD for a whole write cycle.",
               $time);

    if (CE_HALF)  ce_half_since_ce <= 1'b1;
    else if (CE)  ce_half_since_ce <= 1'b0;
end
`endif

always @(posedge CLK) begin
    if (SS_WE && CE)    $error("SS_WE asserted while CE high (core not frozen)");
    if (SS_WE && RESET) $error("SS_WE asserted during RESET");

    if (CE && ss_we_q)  $error("CE resumed with SS command staging undrained (ss_we_q high)");
end
`endif

wire q_pop   = scr_en ? (scr_qop == 2'b01 || scr_qop == 2'b11) : eu_pop;
wire q_first = scr_en ? (scr_qop == 2'b01)                     : eu_first;
wire q_flush = scr_en ? (scr_qop == 2'b10)                     : eu_flush;
wire [15:0] flush_cs = scr_en ? bkd_regs[144 +: 16] : eu_flush_cs;
wire [15:0] flush_ip = scr_en ? bkd_fetch_ip        : eu_flush_ip;

`ifdef V30_MUXED_AD
wire [19:0] ad_o;
wire        ad_oe_addr, ad_oe_ps, ad_oe_data;
`endif

v30u_biu u_biu (
    .clk        (CLK),
    .ce         (CE),
`ifdef V30_MUXED_AD
    .ce_half    (CE_HALF),
`endif
    .srst       (RESET),
    .bs         (BS),
`ifdef V30_MUXED_AD
    .ad_o       (ad_o),
    .ad_oe_addr (ad_oe_addr),
    .ad_oe_ps   (ad_oe_ps),
    .ad_oe_data (ad_oe_data),
    .ad_i       (AD[15:0]),
`else
    .ad_i       (DATA_I),
`endif
    .addr_o     (ADDR_O),
    .data_o     (DATA_O),
    .status_o   (STATUS_O),
    .ube_n      (UBE_N),
    .rd_n       (RD_N),
    .qs         (QS),
    .ready      (READY),
    .psw_ie     (psw_ie),
    .md8080     (md8080),
    .q_byte     (q_byte),
    .q_ripe     (q_ripe),
    .q_ripe_lead_n(q_ripe_lead_n),
    .q_cnt_o    (q_cnt),
    .q_pop      (q_pop),
    .q_first    (q_first),
    .q_flush    (q_flush),
    .flush_pre  (scr_en ? 1'b0 : eu_flush_pre),
    .flush_rep  (scr_en ? 1'b0 : eu_flush_rep),
    .flush_stage(scr_en ? 1'b0 : eu_flush_stage),
    .flush_pend (scr_en ? 1'b0 : eu_flush_pend),
    .flush_nmi  (scr_en ? 1'b0 : eu_flush_nmi),
    .flush_int_live(scr_en ? 1'b0 : eu_flush_int_live),
    .flush_cs   (flush_cs),
    .flush_cs_old(eu_flush_cs_old),
    .flush_cs_we(scr_en ? 1'b0 : eu_flush_cs_we),
    .flush_ip   (flush_ip),
    .eu_post    (scr_en ? 1'b0 : eu_post),
    .eu_post_hold(scr_en ? 1'b0 : eu_post_hold),
    .eu_halt_irq(scr_en ? 1'b0 : eu_halt_irq),
    .eu_vector_post(scr_en ? 1'b0 : eu_vector_post),
    .eu_bs      (eu_bs),
    .eu_addr    (eu_addr),
    .eu_addr2   (eu_addr2),
    .eu_split   (eu_split),
    .eu_seg     (eu_seg),
    .eu_seg2    (eu_seg2),
    .eu_word    (eu_word),
    .eu_slot_busy (eu_slot_busy),
    .eu_slot_busy_n (eu_slot_busy_n),
    .eu_access_active(eu_access_active),
    .eu_direct_fetch(eu_direct_fetch),
    .eu_fetch_tail(eu_fetch_tail),
    .eu_ghost_full(eu_ghost_full),
    .eu_ghost_idle(eu_ghost_idle),
    .eu_ghost_stack_first(eu_ghost_stack_first),
    .eu_ghost_row(eu_ghost_row),
    .eu_ghost_acc(eu_ghost_acc),
    .eu_ghost_sp(eu_ghost_sp),
    .eu_ghost_bare(eu_ghost_bare),
    .eu_pair    (scr_en ? 1'b0 : eu_pair),
    .eu_pair2   (eu_pair2),
    .eu_wdata   (eu_wdata),
    .eu_rdata_n (eu_rdata_n),
    .eu_rd_done_n (eu_rd_done_n),
    .eu_rd_edge (eu_rd_edge),
    .eu_rd_edge_d (eu_rd_edge_d),
    .eu_wr_done_n (eu_wr_done_n),
    .eu_wr_eval   (eu_wr_eval),
    .eu_opr_free(eu_opr_free),
    .eu_susp    (scr_en ? 1'b0 : eu_susp),
    .eu_resume  (scr_en ? 1'b0 : eu_resume),
    .eu_halt    (scr_en ? 1'b0 : eu_halt),
    .eu_unhalt  (scr_en ? 1'b0 : eu_unhalt),
    .eu_unhalt_disp(scr_en ? 1'b0 : eu_unhalt_disp),
    .halted_o   (biu_halted),
    .eu_bnd_take(scr_en ? 1'b0 : eu_bnd_take),
    .eu_bnd_post(eu_bnd_post),
    .bkd_load   (bkd_load),
    .bkd_cs     (bkd_regs[144 +: 16]),
    .bkd_ip     (bkd_fetch_ip),
    .bkd_queue  (bkd_queue),
    .bkd_qlen   (bkd_qlen),
    .ss_addr    (ss_addr_q),
    .ss_wdata   (ss_wdata_q),
    .ss_we      (ss_we_q),
    .ss_rdata   (ss_biu_rdata),
    .ss_bus_quiet(ss_biu_bus_quiet)
);

v30u_eu u_eu (
    .clk        (CLK),
    .ce         (CE),
    .srst       (RESET),
    .q_byte     (q_byte),
    .q_ripe     (q_ripe),
    .q_ripe_lead_n(q_ripe_lead_n),
    .q_cnt      (q_cnt),
    .q_pop      (eu_pop),
    .q_first    (eu_first),
    .q_flush    (eu_flush),
    .flush_pre  (eu_flush_pre),
    .flush_rep  (eu_flush_rep),
    .flush_stage(eu_flush_stage),
    .flush_pend (eu_flush_pend),
    .flush_nmi  (eu_flush_nmi),
    .flush_int_live(eu_flush_int_live),
    .flush_cs   (eu_flush_cs),
    .flush_cs_old(eu_flush_cs_old),
    .flush_cs_we(eu_flush_cs_we),
    .flush_ip   (eu_flush_ip),
    .eu_post    (eu_post),
    .eu_post_hold(eu_post_hold),
    .eu_halt_irq(eu_halt_irq),
    .eu_vector_post(eu_vector_post),
    .eu_bs      (eu_bs),
    .eu_addr    (eu_addr),
    .eu_addr2   (eu_addr2),
    .eu_split   (eu_split),
    .eu_seg     (eu_seg),
    .eu_seg2    (eu_seg2),
    .eu_word    (eu_word),
    .eu_slot_busy (eu_slot_busy),
    .eu_slot_busy_n (eu_slot_busy_n),
    .eu_access_active(eu_access_active),
    .eu_direct_fetch(eu_direct_fetch),
    .eu_fetch_tail(eu_fetch_tail),
    .eu_ghost_full(eu_ghost_full),
    .eu_ghost_idle(eu_ghost_idle),
    .eu_ghost_stack_first(eu_ghost_stack_first),
    .eu_ghost_row(eu_ghost_row),
    .eu_ghost_acc(eu_ghost_acc),
    .eu_ghost_sp(eu_ghost_sp),
    .eu_ghost_bare(eu_ghost_bare),
    .eu_pair    (eu_pair),
    .eu_pair2   (eu_pair2),
    .eu_wdata   (eu_wdata),
    .eu_rdata_n (eu_rdata_n),
    .eu_rd_done_n (eu_rd_done_n),
    .eu_rd_edge (eu_rd_edge),
    .eu_rd_edge_d (eu_rd_edge_d),
    .eu_wr_done_n (eu_wr_done_n),
    .eu_wr_eval   (eu_wr_eval),
    .eu_opr_free(eu_opr_free),
    .eu_susp    (eu_susp),
    .eu_resume  (eu_resume),
    .eu_halt    (eu_halt),
    .eu_unhalt  (eu_unhalt),
    .eu_unhalt_disp(eu_unhalt_disp),
    .halted     (biu_halted),
    .eu_bnd_take(eu_bnd_take),
    .eu_bnd_post(eu_bnd_post),
    .psw_ie     (psw_ie),
    .md8080     (md8080),
    .pin_int    (INT),
    .pin_nmi    (NMI),
    .pin_poll_n (POLL_N),
    .bkd_load   (bkd_load),
    .bkd_regs   (bkd_regs),
`ifdef V30_BACKDOOR
    .dbg_regs      (dbg_regs),
    .dbg_first_pop (dbg_first_pop),
    .dbg_pend      (dbg_pend),
`else
    /* verilator lint_off PINCONNECTEMPTY */
    .dbg_regs      (),
    .dbg_first_pop (),
    .dbg_pend      (),
    /* verilator lint_on PINCONNECTEMPTY */
`endif
    .ss_addr    (ss_addr_q),
    .ss_wdata   (ss_wdata_q),
    .ss_we      (ss_we_q),
    .ss_rdata   (ss_eu_rdata)
);

`ifdef V30_MUXED_AD

assign AD[15:0]  = (ad_oe_addr | ad_oe_data) ? ad_o[15:0]  : 16'hzzzz;
assign AD[19:16] = (ad_oe_addr | ad_oe_ps)   ? ad_o[19:16] : 4'hz;

assign AD_OE = {{4{ad_oe_addr | ad_oe_ps}}, {16{ad_oe_addr | ad_oe_data}}};
`endif

assign BUSLOCK_N = 1'b1;

endmodule
