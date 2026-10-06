module v30u_biu (
    input             clk,
    input             ce,
`ifdef V30_MUXED_AD
    input             ce_half,
`endif
    input             srst,

    output      [2:0] bs,
`ifdef V30_MUXED_AD

    output     [19:0] ad_o,
    output            ad_oe_addr,
    output            ad_oe_ps,
    output            ad_oe_data,
`endif

    output     [19:0] addr_o,
    output     [15:0] data_o,
    output      [3:0] status_o,
    output            ube_n,
    output            rd_n,
    output      [1:0] qs,
    input      [15:0] ad_i,
    input             ready,

    input             psw_ie,
    input             md8080,

    output      [7:0] q_byte,
    output            q_ripe,
    output            q_ripe_lead_n,
    output      [3:0] q_cnt_o,
    input             q_pop,
    input             q_first,
    input             q_flush,
    input             flush_pre,
    input             flush_rep,
    input             flush_stage,
    input             flush_pend,
    input             flush_nmi,
    input             flush_int_live,
    input      [15:0] flush_cs,
    input      [15:0] flush_cs_old,
    input             flush_cs_we,
    input      [15:0] flush_ip,

    input             eu_post,
    input             eu_post_hold,
    input             eu_halt_irq,
    input             eu_vector_post,
    input       [2:0] eu_bs,
    input      [19:0] eu_addr,
    input      [19:0] eu_addr2,
    input             eu_split,
    input       [1:0] eu_seg,
    input       [1:0] eu_seg2,
    input             eu_word,
    output            eu_slot_busy,
    output            eu_slot_busy_n,
    output            eu_access_active,
    output            eu_direct_fetch,
    output            eu_fetch_tail,
    output            eu_ghost_full,
    output            eu_ghost_idle,
    output            eu_ghost_stack_first,

    input             eu_ghost_row,
    input             eu_ghost_acc,
    input      [19:0] eu_ghost_sp,
    input      [19:0] eu_ghost_bare,
    input             eu_pair,
    input             eu_pair2,
    input      [15:0] eu_wdata,
    output     [15:0] eu_rdata_n,
    output            eu_rd_done_n,
    output            eu_rd_edge,
    output     [15:0] eu_rd_edge_d,
    output            eu_wr_done_n,
    output            eu_wr_eval,
    output            eu_opr_free,

    input             eu_susp,
    input             eu_resume,
    input             eu_halt,
    input             eu_unhalt,
    input             eu_unhalt_disp,

    output            halted_o,

    input             eu_bnd_take,
    input             eu_bnd_post,

    input             bkd_load,
    input      [15:0] bkd_cs,
    input      [15:0] bkd_ip,
    input      [47:0] bkd_queue,
    input       [2:0] bkd_qlen,

    input       [8:0] ss_addr,
    input      [15:0] ss_wdata,
    input             ss_we,
    output reg [15:0] ss_rdata,
    output            ss_bus_quiet
);

import v30_ss_pkg::*;

localparam bit [2:0] BS_INTA = 3'd0, BS_IOR = 3'd1, BS_IOW = 3'd2,
                     BS_HALT = 3'd3, BS_CODE = 3'd4, BS_MEMR = 3'd5,
                     BS_MEMW = 3'd6, BS_PASV = 3'd7;
localparam bit [2:0] TS_TI = 3'd0, TS_T1 = 3'd1, TS_T2 = 3'd2,
                     TS_T3 = 3'd3, TS_TW = 3'd4, TS_T4 = 3'd5;
localparam bit [1:0] QS_NONE = 2'd0, QS_FIRST = 2'd1,
                     QS_EMPTY = 2'd2, QS_SUBSEQ = 2'd3;

reg        run;
reg  [2:0] ts;
reg  [2:0] cur_bs;
reg [19:0] cur_addr;
reg [15:0] cur_data;
reg        cur_ube_n;

reg        cur_odd;
reg  [1:0] cur_seg;
reg        cur_fetch;
reg        cur_halt;
reg        cur_noaddr;
reg        cur_wr;
reg        cur_need;
reg        cur_rd_last;
reg  [1:0] cur_pn;
reg        cur_late_t1;
reg        evald;
reg  [1:0] sev;
reg  [2:0] dage;

reg        cmt_valid;
reg  [2:0] cmt_bs;
reg [19:0] cmt_addr;
reg [15:0] cmt_data;
reg        cmt_ube_n;
reg        cmt_odd;
reg  [1:0] cmt_seg;
reg        cmt_fetch;
reg        cmt_halt;
reg        cmt_noaddr;
reg        cmt_wr;
reg        cmt_need;
reg        cmt_rd_last;
reg  [1:0] cmt_pn;
reg  [2:0] cdage;
reg [15:0] cmt_prev_fp;
reg        cmt_was_owed;

reg        last_ube;
reg [15:0] last_fetch_addr;

reg  [3:0] last_ad_hi;
reg [15:0] last_ad_lo;

reg  [7:0] q_mem [0:5];
reg  [2:0] q_head;
reg  [3:0] q_cnt;
reg  [1:0] grn_n;
reg  [1:0] grn_ttl;
reg [15:0] fetch_ptr;
reg [15:0] cs_r;

reg        suspended;
reg        halted;
reg        halt_pending;
reg        pf_owed;
reg        pf_arm;

reg  [1:0] infl_ttl;
reg  [1:0] infl_n;
reg  [1:0] absorb_ttl;
reg        no_eval;
reg        flush_eval;
reg        e_pend;

reg  [1:0] rq_n;
reg  [2:0] rq_bs   [0:1];
reg [19:0] rq_addr [0:1];
reg [15:0] rq_data [0:1];
reg        rq_ube  [0:1];
reg        rq_odd  [0:1];
reg  [1:0] rq_seg  [0:1];
reg        rq_noaddr [0:1];
reg        rq_wr   [0:1];
reg        rq_need [0:1];
reg        rq_last [0:1];
reg        rq_late [0:1];

reg        rq_ghost [0:1];
reg        cmt_ghost;
reg [19:0] g_sp;
reg [19:0] g_bare;
reg  [1:0] g_age;
reg        g_row_q;
reg        slot_busy;
reg        slot_accept;
reg  [1:0] opr_held;
reg  [7:0] rd_first_hi;
reg        rd_was_split;
integer    pk;

reg        pair_odd;
reg        inta_halt_l;
reg  [1:0] done_ctr;
reg        done_wr;
reg        rd_done_p;

reg        wr_done_p;
reg        opr_free_p;
reg [15:0] rd_val;

reg [15:0] rd_land;

reg        ready_prev;

`ifdef V30_MUXED_AD
reg        t1_half2;
`endif

reg r_run;
reg [2:0] r_ts;
reg [2:0] r_cur_bs;
reg [19:0] r_cur_addr;
reg [15:0] r_cur_data;
reg r_cur_ube_n;
reg r_cur_odd;
reg [1:0] r_cur_seg;
reg r_cur_fetch;
reg r_cur_halt;
reg r_cur_noaddr;
reg r_cur_wr;
reg r_cur_need;
reg r_cur_rd_last;
reg [1:0] r_cur_pn;
reg r_cur_late_t1;
reg r_evald;
reg [1:0] r_sev;
reg [2:0] r_dage;
reg r_cmt_valid;
reg [2:0] r_cmt_bs;
reg [19:0] r_cmt_addr;
reg [15:0] r_cmt_data;
reg r_cmt_ube_n;
reg r_cmt_odd;
reg [1:0] r_cmt_seg;
reg r_cmt_fetch;
reg r_cmt_halt;
reg r_cmt_noaddr;
reg r_cmt_wr;
reg r_cmt_need;
reg r_cmt_rd_last;
reg [1:0] r_cmt_pn;
reg [2:0] r_cdage;
reg [15:0] r_cmt_prev_fp;
reg r_cmt_was_owed;
reg [15:0] r_last_fetch_addr;
reg [2:0] r_q_head;
reg [3:0] r_q_cnt;
reg [1:0] r_grn_n;
reg [1:0] r_grn_ttl;
reg [15:0] r_fetch_ptr;
reg [15:0] r_cs_r;
reg r_suspended;
reg r_halted;
reg r_halt_pending;
reg r_pf_owed;
reg r_pf_arm;
reg [1:0] r_infl_ttl;
reg [1:0] r_infl_n;
reg [1:0] r_absorb_ttl;
reg r_no_eval;
reg r_flush_eval;
reg r_e_pend;
reg [1:0] r_rq_n;
reg r_slot_busy;
reg r_slot_accept;
reg [1:0] r_opr_held;
reg [7:0] r_rd_first_hi;
reg r_rd_was_split;
reg [1:0] r_done_ctr;
reg r_done_wr;
reg r_rd_done_p;
reg r_wr_done_p;
reg r_opr_free_p;
reg [15:0] r_rd_val;
reg [15:0] r_rd_land;
reg r_ready_prev;
reg [7:0] r_q_mem [0:5];
reg [2:0] r_rq_bs [0:1];
reg [19:0] r_rq_addr [0:1];
reg [15:0] r_rq_data [0:1];
reg r_rq_ube [0:1];
reg r_rq_odd [0:1];
reg [1:0] r_rq_seg [0:1];
reg r_rq_noaddr [0:1];
reg r_rq_wr [0:1];
reg r_rq_need [0:1];
reg r_rq_last [0:1];
reg r_rq_late [0:1];
reg r_rq_ghost [0:1];
reg r_cmt_ghost;
reg [19:0] r_g_sp;
reg [19:0] r_g_bare;
reg [1:0] r_g_age;
reg r_g_row_q;

integer ri;
integer rj;

function automatic [3:0] data_ps(input [1:0] segc);
    data_ps = {md8080, psw_ie, segc};
endfunction

wire ann_kill  = (q_flush ||
                  ((eu_susp || eu_post) &&
                   !(r_cmt_was_owed && qs_e_now))) &&
                 r_cmt_valid && r_cmt_fetch && (r_cdage == 3'd0);

wire display   = r_cmt_valid && !ann_kill;

wire flush_idle = !r_run && !r_cmt_valid && (r_rq_n == 2'd0) && !eu_post;
wire flush_nmi_young = flush_nmi && (r_dage <= 3'd4);
wire flush_src_live = flush_int_live || flush_nmi;
wire flush_staged_eval = flush_stage && flush_pend && flush_src_live &&
                         flush_idle;
wire flush_direct = !flush_stage && !flush_nmi_young && !flush_int_live;
wire flush_fast = flush_rep && flush_idle && flush_direct;

wire inta_tail_replace = eu_post && (eu_bs == BS_INTA) &&
                         !eu_post_hold &&
                         r_run && r_cur_fetch && (r_ts == TS_T4) &&
                         r_cmt_valid && r_cmt_fetch;

wire inta_follow_preview = eu_post && (eu_bs == BS_INTA) &&
                           r_rd_was_split;
wire inta_preview = inta_tail_replace || inta_follow_preview;
wire vector_follow_preview = eu_vector_post && r_rd_was_split;

assign eu_direct_fetch = r_run && r_cur_fetch && (r_cdage == 3'd0);
assign eu_fetch_tail = (r_absorb_ttl == 2'd1) &&
                       ((!q_ripe && (r_dage <= 3'd4)) ||
                        (q_ripe && (r_dage == 3'd5)));

assign eu_ghost_full = r_run && r_cur_fetch &&
                       ((r_ts == TS_T1) ||
                        ((r_ts == TS_T2) && !r_ready_prev) ||
                        (((r_ts == TS_T3) || (r_ts == TS_TW)) && !r_ready_prev));

assign eu_ghost_idle = r_run && r_cur_fetch && (r_ts == TS_T4);
assign eu_ghost_stack_first = r_run && r_cur_fetch &&
                              (r_ts == TS_T3) && r_ready_prev &&
                              (r_q_cnt >= 4'd2);

wire eval_inst = r_run && !r_evald &&
                 (r_cur_halt ? (r_dage >= 3'd2)
                           : ((r_dage >= 3'd3) && r_ready_prev));

wire st_rel    = r_evald || eval_inst ||
                 (r_run && r_cur_noaddr && r_cur_odd &&
                  (r_ts >= TS_T2));

wire halt_free = r_run && r_cur_halt && r_evald;

wire done_fire   = (r_done_ctr == 2'd1);
wire rd_done_nxt = done_fire && !r_done_wr;
wire wr_done_nxt = done_fire &&  r_done_wr;

wire rd_data_edge = r_run && !r_cur_wr && !r_cur_fetch && !r_cur_halt &&
                    r_cur_rd_last &&
                    ((r_ts == TS_T3) || (r_ts == TS_TW)) && ready;

wire [15:0] rd_edge_val = r_rd_was_split
                          ? {r_cur_data[7:0], r_rd_first_hi}
                          : (r_cur_addr[0] ? {r_cur_data[7:0], r_cur_data[15:8]}
                                           : r_cur_data);
assign eu_rd_edge   = rd_data_edge;
assign eu_rd_edge_d = rd_edge_val;

wire [3:0] poppable = (r_grn_ttl != 2'd0) ? (r_q_cnt - {2'b0, r_grn_n}) : r_q_cnt;
assign q_ripe   = poppable != 4'd0;
assign q_byte   = r_q_mem[r_q_head];
assign q_cnt_o  = r_q_cnt;
assign halted_o = r_halted;

wire qs_port_fetch = r_run && r_cur_fetch && !r_evald;
wire pop_now       = q_pop && q_ripe;

wire e_from_block = q_flush && r_run && r_cur_fetch;
wire qs_e_now = (r_e_pend || q_flush ||
                (flush_pre && flush_direct)) &&
                !(q_flush && flush_rep &&
                  (flush_direct ||
                   (flush_pend && !flush_src_live &&
                    !(r_run && !r_cur_fetch && (r_ts < TS_T3))))) &&
                !pop_now && !e_from_block &&
                (r_absorb_ttl == 2'd0) && !qs_port_fetch &&

                (((r_rq_n == 2'd0) && !eu_post) || q_flush ||
                 (flush_pre && flush_direct) ||
                 (r_cmt_valid && !r_cmt_fetch) || (r_run && !r_cur_fetch));

assign qs = qs_e_now ? QS_EMPTY
          : pop_now  ? (q_first ? QS_FIRST : QS_SUBSEQ)
                     : QS_NONE;

assign eu_slot_busy   = r_slot_busy;
assign eu_slot_busy_n = slot_busy;
assign eu_access_active = r_run && !r_cur_fetch && !r_cur_halt;
assign eu_wr_done_n   = wr_done_nxt;
assign eu_wr_eval     = eval_inst && r_cur_wr && r_cur_rd_last;

assign eu_opr_free    = (r_opr_held == 2'd0);
assign eu_rdata_n     = r_rd_land;
assign eu_rd_done_n   = rd_done_nxt;

wire [3:0] poppable_n = (grn_ttl != 2'd0) ? (q_cnt - {2'b0, grn_n}) : q_cnt;
assign q_ripe_lead_n  = (poppable_n != 4'd0) ||
                        ((grn_ttl == 2'd1) && (q_cnt != 4'd0));

assign ss_bus_quiet = !r_run && !r_cmt_valid && (r_rq_n == 2'd0) && !r_halt_pending;

wire disp_inta = display && r_cmt_noaddr;
wire cur_inta  = r_run && (r_ts == TS_T1) && r_cur_noaddr;

wire halt_addr = r_run && r_cur_halt && (r_ts == TS_T1);

wire [19:0] flush_fast_addr = {flush_cs, 4'd0} + {4'd0, flush_ip};

assign bs = inta_preview ? BS_INTA
          : vector_follow_preview ? BS_MEMR
          : flush_fast     ? BS_CODE
          : display        ? r_cmt_bs
          : (r_run && !st_rel) ? r_cur_bs
                             : BS_PASV;

assign ube_n = (display && (r_cdage != 3'd0)) ? r_cmt_ube_n
             : (r_run && (r_ts == TS_T1))     ? r_cur_ube_n
                                            : last_ube;

wire [15:0] cmt_cs_live = flush_cs & flush_cs_old;
wire [19:0] cmt_addr_live = {cmt_cs_live, 4'd0} +
                            {4'd0, r_cmt_prev_fp};
wire cmt_cs_retarget = flush_cs_we && r_cmt_valid && r_cmt_fetch;
wire [19:0] display_addr = cmt_cs_retarget ? cmt_addr_live : r_cmt_addr;

wire        pair_now   = eu_pair && r_run && r_cur_wr && r_cur_need;
wire [15:0] cur_data_o = pair_now
                       ? (r_cur_addr[0] ? {eu_wdata[7:0], eu_wdata[15:8]}
                                        : eu_wdata)
                       : r_cur_data;

wire bus_t1 = r_run && (r_ts == TS_T1);

`ifdef V30_MUXED_AD
wire bus_half = t1_half2;
`else
wire bus_half = bus_t1 || vector_follow_preview;
`endif

wire bus_vfp_pub = vector_follow_preview && bus_half;

assign addr_o = bus_vfp_pub ? eu_addr
              : flush_fast  ? flush_fast_addr
              : disp_inta   ? 20'h0
              : cur_inta    ? 20'h0
              : display     ? display_addr
                            : r_cur_addr;

assign data_o = cur_data_o;

assign status_o = data_ps((disp_inta || (display && !cur_inta)) ? r_cmt_seg
                                                               : r_cur_seg);

`ifndef V30_MUXED_AD
wire [19:0] ad_o;
wire        ad_oe_addr, ad_oe_ps, ad_oe_data;
`endif

wire bus_ph_hi = bus_vfp_pub ? 1'b1
               : flush_fast  ? 1'b1
               : disp_inta   ? (r_cdage == 3'd0)
               : cur_inta    ? !r_cur_late_t1
               : display     ? (r_cdage == 3'd0)
               : halt_addr   ? 1'b1
               : bus_t1      ? ((r_cur_wr && bus_half) || !r_cur_late_t1)
                             : 1'b0;

wire bus_ph_lo = (bus_vfp_pub || flush_fast || disp_inta || cur_inta ||
                  display || halt_addr) ? 1'b1
               : bus_t1 ? !(r_cur_wr && bus_half)
                        : 1'b0;

assign ad_o = {bus_ph_hi ? addr_o[19:16] : status_o,
               bus_ph_lo ? addr_o[15:0]  : data_o};

assign ad_oe_addr = (flush_fast || display || bus_t1 || halt_addr) &&
                    !disp_inta && !cur_inta;

assign ad_oe_ps   = (!ad_oe_addr && r_run && !r_cur_halt &&
                     (r_ts != TS_T1) && (r_ts != TS_TI)) ||
                    disp_inta || cur_inta;
assign ad_oe_data = bus_vfp_pub ||
                    (r_run && r_cur_wr && !r_cur_halt && !r_cur_noaddr &&
                     (r_ts != TS_TI) && !display);

assign rd_n = !(r_run && ((r_ts == TS_T2) || (r_ts == TS_T3) || (r_ts == TS_TW)) &&
                !r_cur_wr && !r_cur_halt);

`ifdef V30_MUXED_AD
always @(posedge clk)
    if (ss_we && ss_addr == SSA_B_T1_HALF2) t1_half2 <= ss_wdata[0];
    else if (ce_half) t1_half2 <= (r_run && (r_ts == TS_T1)) ||
                                  vector_follow_preview;

`ifndef SYNTHESIS

always @(posedge clk)
    if (ce && !srst &&
        (t1_half2 !== ((r_run && (r_ts == TS_T1)) || vector_follow_preview)))
        $fatal(1, "v30u_biu: bus_half EQUIVALENCE FAILED at %0t -- t1_half2 %b but (bus_t1 || vfp) %b at a CE instant.  The de-muxed configuration derives the T1 half from these registers and would disagree with the multiplexed one; see docs/notes/demux_bus_prereg_2026-08-14.md.",
               $time, t1_half2,
               ((r_run && (r_ts == TS_T1)) || vector_follow_preview));

wire [19:0] t1_addr_ref = r_cur_late_t1 ? {data_ps(r_cur_seg), r_cur_addr[15:0]}
                                        : r_cur_addr;
wire  [3:0] disp_hi_ref  = (r_cdage == 3'd0) ? display_addr[19:16]
                                             : data_ps(r_cmt_seg);
wire  [3:0] dinta_hi_ref = (r_cdage == 3'd0) ? 4'h0
                                             : data_ps(r_cmt_seg);
wire  [3:0] cinta_hi_ref = r_cur_late_t1 ? data_ps(r_cur_seg) : 4'h0;

wire [19:0] ad_o_ref = (vector_follow_preview && t1_half2) ? eu_addr
                     : flush_fast               ? flush_fast_addr
                     : disp_inta                ? {dinta_hi_ref, 16'h0}
                     : cur_inta                 ? {cinta_hi_ref, 16'h0}
                     : display                  ? {disp_hi_ref, display_addr[15:0]}
                     : halt_addr                ? r_cur_addr
                     : (r_run && (r_ts == TS_T1))  ? (r_cur_wr && t1_half2
                                                  ? {r_cur_addr[19:16], cur_data_o}
                                                  : t1_addr_ref)
                                               : {data_ps(r_cur_seg), cur_data_o};

always @(posedge clk)
    if ((^ad_o_ref !== 1'bx) && (ad_o !== ad_o_ref))
        $fatal(1, "v30u_biu: DE-MUX RECONSTRUCTION FAILED at %0t -- composed AD %05x, muxed law %05x (addr_o %05x data_o %04x status_o %01x hi %b lo %b).  The de-muxed ports and the multiplexed view have DRIFTED; see docs/notes/demux_bus_prereg_2026-08-14.md §4.",
               $time, ad_o, ad_o_ref, addr_o, data_o, status_o,
               bus_ph_hi, bus_ph_lo);
`endif
`endif

integer i;
integer lfa_need;
reg [15:0] lfa_p;
reg [19:0] lfa_a;

reg        ne_now, kill_l, evi_l, hfree_l, pop_l, qse_l;
reg  [1:0] sev_now;
reg        infl_now;
reg  [1:0] infl_n_now;
reg        set_oprfree;

reg        ev_here, ev_latch, did_grant, gr_ok, rmw_yield;
reg  [4:0] occ;
reg  [1:0] land_ttl;
reg  [3:0] qi;
reg [19:0] fetch_lin;
reg  [1:0] rq_n_pre;
reg        set_grn, set_infl, set_absorb, set_noeval;
reg  [1:0] new_ttl;

reg            run_rst;
reg      [2:0] ts_rst;
reg      [2:0] cur_bs_rst;
reg     [19:0] cur_addr_rst;
reg     [15:0] cur_data_rst;
reg            cur_ube_n_rst;
reg            cur_odd_rst;
reg      [1:0] cur_seg_rst;
reg            cur_fetch_rst;
reg            cur_halt_rst;
reg            cur_noaddr_rst;
reg            cur_wr_rst;
reg            cur_need_rst;
reg            cur_rd_last_rst;
reg      [1:0] cur_pn_rst;
reg            cur_late_t1_rst;
reg            evald_rst;
reg      [1:0] sev_rst;
reg      [2:0] dage_rst;
reg            cmt_valid_rst;
reg      [2:0] cmt_bs_rst;
reg     [19:0] cmt_addr_rst;
reg     [15:0] cmt_data_rst;
reg            cmt_ube_n_rst;
reg            cmt_odd_rst;
reg      [1:0] cmt_seg_rst;
reg            cmt_fetch_rst;
reg            cmt_halt_rst;
reg            cmt_noaddr_rst;
reg            cmt_wr_rst;
reg            cmt_need_rst;
reg            cmt_rd_last_rst;
reg      [1:0] cmt_pn_rst;
reg      [2:0] cdage_rst;
reg     [15:0] cmt_prev_fp_rst;
reg            cmt_was_owed_rst;
reg     [15:0] last_fetch_addr_rst;
reg      [2:0] q_head_rst;
reg      [3:0] q_cnt_rst;
reg      [1:0] grn_n_rst;
reg      [1:0] grn_ttl_rst;
reg     [15:0] fetch_ptr_rst;
reg     [15:0] cs_r_rst;
reg            suspended_rst;
reg            halted_rst;
reg            halt_pending_rst;
reg            pf_owed_rst;
reg            pf_arm_rst;
reg      [1:0] infl_ttl_rst;
reg      [1:0] infl_n_rst;
reg      [1:0] absorb_ttl_rst;
reg            no_eval_rst;
reg            flush_eval_rst;
reg            e_pend_rst;
reg      [1:0] rq_n_rst;
reg            slot_busy_rst;
reg            slot_accept_rst;
reg      [1:0] opr_held_rst;
reg      [7:0] rd_first_hi_rst;
reg            rd_was_split_rst;
reg      [1:0] done_ctr_rst;
reg            done_wr_rst;
reg            rd_done_p_rst;
reg            wr_done_p_rst;
reg            opr_free_p_rst;
reg     [15:0] rd_val_rst;
reg     [15:0] rd_land_rst;
reg            ready_prev_rst;
reg      [7:0] q_mem_rst [0:5];
reg      [2:0] rq_bs_rst [0:1];
reg     [19:0] rq_addr_rst [0:1];
reg     [15:0] rq_data_rst [0:1];
reg            rq_ube_rst [0:1];
reg            rq_odd_rst [0:1];
reg      [1:0] rq_seg_rst [0:1];
reg            rq_noaddr_rst [0:1];
reg            rq_wr_rst [0:1];
reg            rq_need_rst [0:1];
reg            rq_last_rst [0:1];
reg            rq_late_rst [0:1];
reg            rq_ghost_rst [0:1];
reg            cmt_ghost_rst;
reg     [19:0] g_sp_rst;
reg     [19:0] g_bare_rst;
reg      [1:0] g_age_rst;
reg            g_row_q_rst;

integer i_rst;
reg [15:0] lfa_p_rst;
integer    lfa_need_rst;
reg [19:0] lfa_a_rst;
always_comb begin
    lfa_p_rst = 16'd0; lfa_need_rst = 0; lfa_a_rst = 20'd0; i_rst = 0;

    run_rst = r_run;
    ts_rst = r_ts;
    cur_bs_rst = r_cur_bs;
    cur_addr_rst = r_cur_addr;
    cur_data_rst = r_cur_data;
    cur_ube_n_rst = r_cur_ube_n;
    cur_odd_rst = r_cur_odd;
    cur_seg_rst = r_cur_seg;
    cur_fetch_rst = r_cur_fetch;
    cur_halt_rst = r_cur_halt;
    cur_noaddr_rst = r_cur_noaddr;
    cur_wr_rst = r_cur_wr;
    cur_need_rst = r_cur_need;
    cur_rd_last_rst = r_cur_rd_last;
    cur_pn_rst = r_cur_pn;
    cur_late_t1_rst = r_cur_late_t1;
    evald_rst = r_evald;
    sev_rst = r_sev;
    dage_rst = r_dage;
    cmt_valid_rst = r_cmt_valid;
    cmt_bs_rst = r_cmt_bs;
    cmt_addr_rst = r_cmt_addr;
    cmt_data_rst = r_cmt_data;
    cmt_ube_n_rst = r_cmt_ube_n;
    cmt_odd_rst = r_cmt_odd;
    cmt_seg_rst = r_cmt_seg;
    cmt_fetch_rst = r_cmt_fetch;
    cmt_halt_rst = r_cmt_halt;
    cmt_noaddr_rst = r_cmt_noaddr;
    cmt_wr_rst = r_cmt_wr;
    cmt_need_rst = r_cmt_need;
    cmt_rd_last_rst = r_cmt_rd_last;
    cmt_pn_rst = r_cmt_pn;
    cdage_rst = r_cdage;
    cmt_prev_fp_rst = r_cmt_prev_fp;
    cmt_was_owed_rst = r_cmt_was_owed;
    last_fetch_addr_rst = r_last_fetch_addr;
    q_head_rst = r_q_head;
    q_cnt_rst = r_q_cnt;
    grn_n_rst = r_grn_n;
    grn_ttl_rst = r_grn_ttl;
    fetch_ptr_rst = r_fetch_ptr;
    cs_r_rst = r_cs_r;
    suspended_rst = r_suspended;
    halted_rst = r_halted;
    halt_pending_rst = r_halt_pending;
    pf_owed_rst = r_pf_owed;
    pf_arm_rst = r_pf_arm;
    infl_ttl_rst = r_infl_ttl;
    infl_n_rst = r_infl_n;
    absorb_ttl_rst = r_absorb_ttl;
    no_eval_rst = r_no_eval;
    flush_eval_rst = r_flush_eval;
    e_pend_rst = r_e_pend;
    rq_n_rst = r_rq_n;
    slot_busy_rst = r_slot_busy;
    slot_accept_rst = r_slot_accept;
    opr_held_rst = r_opr_held;
    rd_first_hi_rst = r_rd_first_hi;
    rd_was_split_rst = r_rd_was_split;
    done_ctr_rst = r_done_ctr;
    done_wr_rst = r_done_wr;
    rd_done_p_rst = r_rd_done_p;
    wr_done_p_rst = r_wr_done_p;
    opr_free_p_rst = r_opr_free_p;
    rd_val_rst = r_rd_val;
    rd_land_rst = r_rd_land;
    ready_prev_rst = r_ready_prev;
    for (i_rst = 0; i_rst < $size(r_q_mem); i_rst = i_rst + 1) q_mem_rst[i_rst] = r_q_mem[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_bs); i_rst = i_rst + 1) rq_bs_rst[i_rst] = r_rq_bs[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_addr); i_rst = i_rst + 1) rq_addr_rst[i_rst] = r_rq_addr[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_data); i_rst = i_rst + 1) rq_data_rst[i_rst] = r_rq_data[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_ube); i_rst = i_rst + 1) rq_ube_rst[i_rst] = r_rq_ube[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_odd); i_rst = i_rst + 1) rq_odd_rst[i_rst] = r_rq_odd[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_seg); i_rst = i_rst + 1) rq_seg_rst[i_rst] = r_rq_seg[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_noaddr); i_rst = i_rst + 1) rq_noaddr_rst[i_rst] = r_rq_noaddr[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_wr); i_rst = i_rst + 1) rq_wr_rst[i_rst] = r_rq_wr[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_need); i_rst = i_rst + 1) rq_need_rst[i_rst] = r_rq_need[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_last); i_rst = i_rst + 1) rq_last_rst[i_rst] = r_rq_last[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_late); i_rst = i_rst + 1) rq_late_rst[i_rst] = r_rq_late[i_rst];
    for (i_rst = 0; i_rst < $size(r_rq_ghost); i_rst = i_rst + 1) rq_ghost_rst[i_rst] = r_rq_ghost[i_rst];
    cmt_ghost_rst = r_cmt_ghost;
    g_sp_rst = r_g_sp;
    g_bare_rst = r_g_bare;
    g_age_rst = r_g_age;
    g_row_q_rst = r_g_row_q;

        run_rst  = 1'b0; ts_rst  = TS_TI;
        cur_bs_rst  = BS_PASV; cur_addr_rst  = 20'd0; cur_data_rst  = 16'd0;
        cur_ube_n_rst  = 1'b1; cur_seg_rst  = 2'd2; cur_fetch_rst  = 1'b0; cur_odd_rst = 1'b0;
        cur_halt_rst  = 1'b0; cur_noaddr_rst  = 1'b0; cur_wr_rst  = 1'b0;
        cur_need_rst  = 1'b0; cur_rd_last_rst  = 1'b1; cur_pn_rst  = 2'd0;
        cur_late_t1_rst  = 1'b0; evald_rst  = 1'b0; sev_rst  = 2'd0; dage_rst  = 3'd0;
        cmt_valid_rst  = 1'b0; cmt_bs_rst  = BS_PASV; cmt_addr_rst  = 20'd0;
        cmt_data_rst  = 16'd0; cmt_ube_n_rst  = 1'b1; cmt_seg_rst  = 2'd2; cmt_odd_rst = 1'b0;
        cmt_fetch_rst  = 1'b0; cmt_halt_rst  = 1'b0; cmt_noaddr_rst  = 1'b0;
        cmt_wr_rst  = 1'b0; cmt_need_rst  = 1'b0; cmt_rd_last_rst  = 1'b1;
        cmt_pn_rst  = 2'd0; cdage_rst  = 3'd0; cmt_prev_fp_rst  = 16'd0;
        cmt_was_owed_rst  = 1'b0;
        q_head_rst  = 3'd0; grn_n_rst  = 2'd0; grn_ttl_rst  = 2'd0;
        suspended_rst  = 1'b0; halted_rst  = 1'b0; halt_pending_rst  = 1'b0;
        pf_owed_rst  = 1'b0; pf_arm_rst  = 1'b1;
        infl_ttl_rst  = 2'd0; infl_n_rst  = 2'd0; absorb_ttl_rst  = 2'd0;
        no_eval_rst  = 1'b0; flush_eval_rst  = 1'b0; e_pend_rst  = 1'b0;
        rq_n_rst  = 2'd0;
        for (i_rst = 0; i_rst < 2; i_rst = i_rst + 1) begin
            rq_bs_rst[i_rst]  = BS_PASV; rq_addr_rst[i_rst]  = 20'd0; rq_data_rst[i_rst]  = 16'd0;
            rq_ube_rst[i_rst]  = 1'b1; rq_seg_rst[i_rst]  = 2'd2; rq_noaddr_rst[i_rst]  = 1'b0;
            rq_odd_rst[i_rst]  = 1'b0;
            rq_wr_rst[i_rst]  = 1'b0; rq_need_rst[i_rst]  = 1'b0; rq_last_rst[i_rst]  = 1'b1;
            rq_late_rst[i_rst] = 1'b0;
            rq_ghost_rst[i_rst] = 1'b0;
        end
        cmt_ghost_rst = 1'b0;
        g_sp_rst = 20'd0; g_bare_rst = 20'd0;
        g_age_rst = 2'd2; g_row_q_rst = 1'b0;
        slot_busy_rst  = 1'b0; slot_accept_rst  = 1'b0;
        opr_held_rst  = 2'd0; done_ctr_rst  = 2'd0; done_wr_rst  = 1'b0;
        rd_first_hi_rst = 8'd0; rd_was_split_rst = 1'b0;
        rd_done_p_rst  = 1'b0; wr_done_p_rst  = 1'b0; opr_free_p_rst  = 1'b0;
        rd_val_rst  = 16'd0; rd_land_rst = 16'd0;
        ready_prev_rst  = 1'b1;
        if (bkd_load) begin

            cs_r_rst       = bkd_cs;
            fetch_ptr_rst  = bkd_ip;
            q_cnt_rst      = {1'b0, bkd_qlen};
            for (i_rst = 0; i_rst < 6; i_rst = i_rst + 1) q_mem_rst[i_rst]  = bkd_queue[i_rst*8 +: 8];

            lfa_p_rst    = bkd_ip - {13'd0, bkd_qlen};
            lfa_need_rst = {29'd0, bkd_qlen};
            last_fetch_addr_rst = 16'd0;
            for (i_rst = 0; i_rst < 6; i_rst = i_rst + 1) begin
                if (lfa_need_rst > 0) begin
                    lfa_a_rst = {bkd_cs, 4'd0} + {4'd0, lfa_p_rst};
                    last_fetch_addr_rst = lfa_a_rst[15:0];
                    if (lfa_p_rst[0]) begin
                        lfa_p_rst    = lfa_p_rst + 16'd1;
                        lfa_need_rst = lfa_need_rst - 1;
                    end else begin
                        lfa_p_rst    = lfa_p_rst + 16'd2;
                        lfa_need_rst = lfa_need_rst - 2;
                    end
                end
            end
        end else begin

            cs_r_rst       = 16'hFFFF;
            fetch_ptr_rst  = 16'h0000;
            q_cnt_rst      = 4'd0;
            for (i_rst = 0; i_rst < 6; i_rst = i_rst + 1) q_mem_rst[i_rst]  = 8'h00;
            last_fetch_addr_rst  = 16'd0;
        end
end

always_comb begin

    run = r_run;
    ts = r_ts;
    cur_bs = r_cur_bs;
    cur_addr = r_cur_addr;
    cur_data = r_cur_data;
    cur_ube_n = r_cur_ube_n;
    cur_odd = r_cur_odd;
    cur_seg = r_cur_seg;
    cur_fetch = r_cur_fetch;
    cur_halt = r_cur_halt;
    cur_noaddr = r_cur_noaddr;
    cur_wr = r_cur_wr;
    cur_need = r_cur_need;
    cur_rd_last = r_cur_rd_last;
    cur_pn = r_cur_pn;
    cur_late_t1 = r_cur_late_t1;
    evald = r_evald;
    sev = r_sev;
    dage = r_dage;
    cmt_valid = r_cmt_valid;
    cmt_bs = r_cmt_bs;
    cmt_addr = r_cmt_addr;
    cmt_data = r_cmt_data;
    cmt_ube_n = r_cmt_ube_n;
    cmt_odd = r_cmt_odd;
    cmt_seg = r_cmt_seg;
    cmt_fetch = r_cmt_fetch;
    cmt_halt = r_cmt_halt;
    cmt_noaddr = r_cmt_noaddr;
    cmt_wr = r_cmt_wr;
    cmt_need = r_cmt_need;
    cmt_rd_last = r_cmt_rd_last;
    cmt_pn = r_cmt_pn;
    cdage = r_cdage;
    cmt_prev_fp = r_cmt_prev_fp;
    cmt_was_owed = r_cmt_was_owed;
    last_fetch_addr = r_last_fetch_addr;
    lfa_p = 16'd0; lfa_need = 0; lfa_a = 20'd0;
    q_head = r_q_head;
    q_cnt = r_q_cnt;
    grn_n = r_grn_n;
    grn_ttl = r_grn_ttl;
    fetch_ptr = r_fetch_ptr;
    cs_r = r_cs_r;
    suspended = r_suspended;
    halted = r_halted;
    halt_pending = r_halt_pending;
    pf_owed = r_pf_owed;
    pf_arm = r_pf_arm;
    infl_ttl = r_infl_ttl;
    infl_n = r_infl_n;
    absorb_ttl = r_absorb_ttl;
    no_eval = r_no_eval;
    flush_eval = r_flush_eval;
    e_pend = r_e_pend;
    rq_n = r_rq_n;
    slot_busy = r_slot_busy;
    slot_accept = r_slot_accept;
    opr_held = r_opr_held;
    rd_first_hi = r_rd_first_hi;
    rd_was_split = r_rd_was_split;
    done_ctr = r_done_ctr;
    done_wr = r_done_wr;
    rd_done_p = r_rd_done_p;
    wr_done_p = r_wr_done_p;
    opr_free_p = r_opr_free_p;
    rd_val = r_rd_val;
    rd_land = r_rd_land;
    ready_prev = r_ready_prev;
    pair_odd = 1'b0;
    inta_halt_l = 1'b0;
    for (ri = 0; ri < 6; ri = ri + 1) q_mem[ri] = r_q_mem[ri];
    for (ri = 0; ri < 2; ri = ri + 1) begin
        rq_bs[ri] = r_rq_bs[ri];
        rq_addr[ri] = r_rq_addr[ri];
        rq_data[ri] = r_rq_data[ri];
        rq_ube[ri] = r_rq_ube[ri];
        rq_odd[ri] = r_rq_odd[ri];
        rq_seg[ri] = r_rq_seg[ri];
        rq_noaddr[ri] = r_rq_noaddr[ri];
        rq_wr[ri] = r_rq_wr[ri];
        rq_need[ri] = r_rq_need[ri];
        rq_last[ri] = r_rq_last[ri];
        rq_late[ri] = r_rq_late[ri];
        rq_ghost[ri] = r_rq_ghost[ri];
    end
    cmt_ghost = r_cmt_ghost;
    g_sp = r_g_sp;
    g_bare = r_g_bare;
    g_age = r_g_age;
    g_row_q = r_g_row_q;

    ne_now = 1'b0; kill_l = 1'b0; evi_l = 1'b0;
    hfree_l = 1'b0; pop_l = 1'b0; qse_l = 1'b0; sev_now = 2'd0;
    infl_now = 1'b0; infl_n_now = 2'd0; set_oprfree = 1'b0;
    ev_here = 1'b0; ev_latch = 1'b0; did_grant = 1'b0;
    rmw_yield = 1'b0;
    gr_ok = 1'b0; occ = 5'd0; land_ttl = 2'd0; qi = 4'd0;
    fetch_lin = 20'd0; rq_n_pre = 2'd0;
    set_grn = 1'b0; set_infl = 1'b0; set_absorb = 1'b0;
    set_noeval = 1'b0; new_ttl = 2'd0;
    i = 0; pk = 0;

    if (ss_we) begin

        case (ss_addr)
            SSA_B_RUN:          run           = ss_wdata[0];
            SSA_B_TS:           ts            = ss_wdata[2:0];
            SSA_B_CUR_BS:       cur_bs        = ss_wdata[2:0];
            SSA_B_CUR_ADDR_LO:  cur_addr[15:0]   = ss_wdata;
            SSA_B_CUR_ADDR_HI:  cur_addr[19:16]  = ss_wdata[3:0];
            SSA_B_CUR_DATA:     cur_data      = ss_wdata;
            SSA_B_CUR_UBE_N:    cur_ube_n     = ss_wdata[0];
            SSA_B_CUR_SEG:      cur_seg       = ss_wdata[1:0];
            SSA_B_CUR_FETCH:    cur_fetch     = ss_wdata[0];
            SSA_B_CUR_HALT:     cur_halt      = ss_wdata[0];
            SSA_B_CUR_NOADDR:   cur_noaddr    = ss_wdata[0];
            SSA_B_CUR_WR:       cur_wr        = ss_wdata[0];
            SSA_B_CUR_NEED:     cur_need      = ss_wdata[0];
            SSA_B_CUR_RDLAST:   cur_rd_last   = ss_wdata[0];
            SSA_B_CUR_PN:       cur_pn        = ss_wdata[1:0];
            SSA_B_CUR_LATET1:   cur_late_t1   = ss_wdata[0];
            SSA_B_EVALD:        evald         = ss_wdata[0];
            SSA_B_SEV:          sev           = ss_wdata[1:0];
            SSA_B_DAGE:         dage          = ss_wdata[2:0];
            SSA_B_CMT_VALID:    cmt_valid     = ss_wdata[0];
            SSA_B_CMT_BS:       cmt_bs        = ss_wdata[2:0];
            SSA_B_CMT_ADDR_LO:  cmt_addr[15:0]   = ss_wdata;
            SSA_B_CMT_ADDR_HI:  cmt_addr[19:16]  = ss_wdata[3:0];
            SSA_B_CMT_DATA:     cmt_data      = ss_wdata;
            SSA_B_CMT_UBE_N:    cmt_ube_n     = ss_wdata[0];
            SSA_B_CMT_SEG:      cmt_seg       = ss_wdata[1:0];
            SSA_B_CMT_FETCH:    cmt_fetch     = ss_wdata[0];
            SSA_B_CMT_HALT:     cmt_halt      = ss_wdata[0];
            SSA_B_CMT_NOADDR:   cmt_noaddr    = ss_wdata[0];
            SSA_B_CMT_WR:       cmt_wr        = ss_wdata[0];
            SSA_B_CMT_NEED:     cmt_need      = ss_wdata[0];
            SSA_B_CMT_RDLAST:   cmt_rd_last   = ss_wdata[0];
            SSA_B_CMT_PN:       cmt_pn        = ss_wdata[1:0];
            SSA_B_CDAGE:        cdage         = ss_wdata[2:0];
            SSA_B_CMT_PREV_FP:  cmt_prev_fp   = ss_wdata;
            SSA_B_CMT_WAS_OWED: cmt_was_owed  = ss_wdata[0];
            SSA_B_LAST_FADDR:   last_fetch_addr  = ss_wdata;
            SSA_B_Q0:           q_mem[0]      = ss_wdata[7:0];
            SSA_B_Q1:           q_mem[1]      = ss_wdata[7:0];
            SSA_B_Q2:           q_mem[2]      = ss_wdata[7:0];
            SSA_B_Q3:           q_mem[3]      = ss_wdata[7:0];
            SSA_B_Q4:           q_mem[4]      = ss_wdata[7:0];
            SSA_B_Q5:           q_mem[5]      = ss_wdata[7:0];
            SSA_B_Q_HEAD:       q_head        = ss_wdata[2:0];
            SSA_B_Q_CNT:        q_cnt         = ss_wdata[3:0];
            SSA_B_GRN_N:        grn_n         = ss_wdata[1:0];
            SSA_B_GRN_TTL:      grn_ttl       = ss_wdata[1:0];
            SSA_B_FETCH_PTR:    fetch_ptr     = ss_wdata;
            SSA_B_CS:           cs_r          = ss_wdata;
            SSA_B_SUSPENDED:    suspended     = ss_wdata[0];
            SSA_B_HALTED:       halted        = ss_wdata[0];
            SSA_B_HALT_PEND:    halt_pending  = ss_wdata[0];
            SSA_B_PF_OWED:      pf_owed       = ss_wdata[0];
            SSA_B_PF_ARM:       pf_arm        = ss_wdata[0];
            SSA_B_INFL_TTL:     infl_ttl      = ss_wdata[1:0];
            SSA_B_INFL_N:       infl_n        = ss_wdata[1:0];
            SSA_B_ABSORB_TTL:   absorb_ttl    = ss_wdata[1:0];
            SSA_B_NO_EVAL:      no_eval       = ss_wdata[0];
            SSA_B_FLUSH_EVAL:   flush_eval    = ss_wdata[0];
            SSA_B_E_PEND:       e_pend        = ss_wdata[0];
            SSA_B_RQ_N:         rq_n          = ss_wdata[1:0];
            SSA_B_RQ0_BS:       rq_bs[0]      = ss_wdata[2:0];
            SSA_B_RQ0_ADDR_LO:  rq_addr[0][15:0]   = ss_wdata;
            SSA_B_RQ0_ADDR_HI:  rq_addr[0][19:16]  = ss_wdata[3:0];
            SSA_B_RQ0_DATA:     rq_data[0]    = ss_wdata;
            SSA_B_RQ0_UBE:      rq_ube[0]     = ss_wdata[0];
            SSA_B_RQ0_SEG:      rq_seg[0]     = ss_wdata[1:0];
            SSA_B_RQ0_NOADDR:   rq_noaddr[0]  = ss_wdata[0];
            SSA_B_RQ0_WR:       rq_wr[0]      = ss_wdata[0];
            SSA_B_RQ0_NEED:     rq_need[0]    = ss_wdata[0];
            SSA_B_RQ0_LAST:     rq_last[0]    = ss_wdata[0];
            SSA_B_RQ1_BS:       rq_bs[1]      = ss_wdata[2:0];
            SSA_B_RQ1_ADDR_LO:  rq_addr[1][15:0]   = ss_wdata;
            SSA_B_RQ1_ADDR_HI:  rq_addr[1][19:16]  = ss_wdata[3:0];
            SSA_B_RQ1_DATA:     rq_data[1]    = ss_wdata;
            SSA_B_RQ1_UBE:      rq_ube[1]     = ss_wdata[0];
            SSA_B_RQ1_SEG:      rq_seg[1]     = ss_wdata[1:0];
            SSA_B_RQ1_NOADDR:   rq_noaddr[1]  = ss_wdata[0];
            SSA_B_RQ1_WR:       rq_wr[1]      = ss_wdata[0];
            SSA_B_RQ1_NEED:     rq_need[1]    = ss_wdata[0];
            SSA_B_RQ1_LAST:     rq_last[1]    = ss_wdata[0];
            SSA_B_RQ_LATE: begin
                rq_late[0] = ss_wdata[0];
                rq_late[1] = ss_wdata[1];
            end
            SSA_B_SLOT_BUSY:    slot_busy     = ss_wdata[0];
            SSA_B_SLOT_ACC:     slot_accept   = ss_wdata[0];
            SSA_B_OPR_HELD:     opr_held      = ss_wdata[1:0];
            SSA_B_RD_FIRST_HI:  rd_first_hi   = ss_wdata[7:0];
            SSA_B_RD_WAS_SPLIT: rd_was_split  = ss_wdata[0];

            SSA_B_CUR_ODD:      cur_odd       = ss_wdata[0];
            SSA_B_CMT_ODD:      cmt_odd       = ss_wdata[0];
            SSA_B_RQ0_ODD:      rq_odd[0]     = ss_wdata[0];
            SSA_B_RQ1_ODD:      rq_odd[1]     = ss_wdata[0];
            SSA_B_RD_LAND:      rd_land       = ss_wdata;
            SSA_B_DONE_CTR:     done_ctr      = ss_wdata[1:0];
            SSA_B_DONE_WR:      done_wr       = ss_wdata[0];
            SSA_B_RD_DONE_P:    rd_done_p     = ss_wdata[0];
            SSA_B_WR_DONE_P:    wr_done_p     = ss_wdata[0];
            SSA_B_OPR_FREE_P:   opr_free_p    = ss_wdata[0];
            SSA_B_RD_VAL:       rd_val        = ss_wdata;
            SSA_B_READY_PREV:   ready_prev    = ss_wdata[0];

            SSA_B_GHOST_SP_LO:   g_sp[15:0]    = ss_wdata;
            SSA_B_GHOST_SP_HI:   g_sp[19:16]   = ss_wdata[3:0];
            SSA_B_GHOST_BARE_LO: g_bare[15:0]  = ss_wdata;
            SSA_B_GHOST_BARE_HI: g_bare[19:16] = ss_wdata[3:0];
            SSA_B_GHOST_AGE:     g_age         = ss_wdata[1:0];
            SSA_B_GHOST_TAG: begin
                rq_ghost[0] = ss_wdata[0];
                rq_ghost[1] = ss_wdata[1];
                cmt_ghost   = ss_wdata[2];
                g_row_q     = ss_wdata[3];
            end
            default: ;
        endcase
    end else begin

        g_row_q = eu_ghost_row;
        if (eu_ghost_row && !r_g_row_q) begin
            g_age  = 2'd0;
            g_sp   = eu_ghost_sp;
            g_bare = eu_ghost_bare;
        end else if (g_age != 2'd2) begin
            g_age = g_age + 2'd1;
        end
        ne_now     = no_eval;
        kill_l     = ann_kill;
        evi_l      = eval_inst;
        hfree_l    = halt_free;
        pop_l      = pop_now;
        qse_l      = qs_e_now;
        sev_now    = evald ? sev : 2'd0;
        infl_now   = (infl_ttl != 2'd0);
        infl_n_now = infl_n;
        set_grn = 1'b0; set_infl = 1'b0; set_absorb = 1'b0;
        set_noeval = 1'b0; new_ttl = 2'd0;
        set_oprfree = 1'b0;

        rd_done_p = rd_done_nxt; wr_done_p = wr_done_nxt;
        if (done_ctr != 2'd0) done_ctr = done_ctr - 2'd1;

        rq_n_pre = rq_n;

        if (pop_l) begin
            q_head = (q_head == 3'd5) ? 3'd0 : q_head + 3'd1;
            q_cnt  = q_cnt - 4'd1;
        end
        if (qse_l) e_pend = 1'b0;

        if (kill_l) begin
            cmt_valid = 1'b0;
            fetch_ptr = cmt_prev_fp;
            pf_owed   = cmt_was_owed;
        end

        if (flush_cs_we && cmt_valid && cmt_fetch) begin
            cmt_addr = {cmt_cs_live, 4'd0} + {4'd0, cmt_prev_fp};
            last_fetch_addr = cmt_addr[15:0];
        end
        if (eu_susp)   suspended = 1'b1;
        if (eu_resume) suspended = 1'b0;

        if (eu_bnd_take && eu_bnd_post) suspended = 1'b1;
        if (eu_unhalt) begin halted = 1'b0; halt_pending = 1'b0; end

        if (eu_halt)   halt_pending = 1'b1;

        if (eu_post && (rq_n != 2'd2)) begin

            rq_bs[rq_n[0]]     = eu_bs;
            rq_addr[rq_n[0]]   = eu_addr;
            rq_data[rq_n[0]]   = 16'd0;
            rq_ube[rq_n[0]]    = (eu_word || eu_addr[0]) ? 1'b0 : 1'b1;
            rq_odd[rq_n[0]]    = eu_addr[0];
            rq_seg[rq_n[0]]    = eu_seg;
            rq_noaddr[rq_n[0]] = (eu_bs == BS_INTA);
            rq_wr[rq_n[0]]     = (eu_bs == BS_MEMW) || (eu_bs == BS_IOW);
            rq_need[rq_n[0]]   = (eu_bs == BS_MEMW) || (eu_bs == BS_IOW);
            rq_last[rq_n[0]]   = !eu_split;

            rq_late[rq_n[0]]   = run && !cur_fetch && !cur_wr &&
                                  (ts >= TS_T3);

            rq_ghost[rq_n[0]]  = eu_ghost_acc;
            rq_n            = rq_n + 2'd1;
            if (eu_split) begin
                rq_bs[1]     = eu_bs;
                rq_addr[1]   = eu_addr2;
                rq_data[1]   = 16'd0;
                rq_ube[1]    = eu_addr2[0] ? 1'b0 : 1'b1;
                rq_odd[1]    = eu_addr[0];
                rq_seg[1]    = eu_seg2;
                rq_noaddr[1] = 1'b0;
                rq_wr[1]     = (eu_bs == BS_MEMW) || (eu_bs == BS_IOW);
                rq_need[1]   = (eu_bs == BS_MEMW) || (eu_bs == BS_IOW);
                rq_last[1]   = 1'b1;
                rq_late[1]   = run && !cur_fetch && !cur_wr &&
                               (ts >= TS_T3);
                rq_ghost[1]  = 1'b0;
                rq_n         = 2'd2;
            end
            slot_busy       = 1'b1;
            slot_accept     = 1'b0;
        end

        for (pk = 0; pk < 2; pk = pk + 1)
        if (eu_pair && ((pk == 0) || eu_pair2)) begin
            rd_val = eu_wdata;
            if (run && cur_need) begin
                if (pk == 0) pair_odd = cur_addr[0];
                cur_data = pair_odd ? {eu_wdata[7:0], eu_wdata[15:8]}
                                    : eu_wdata;
                cur_need = 1'b0;

                if (((ts == TS_T1) || (ts == TS_T2)) && (opr_held != 2'd3))
                    opr_held = opr_held + 2'd1;
            end else if (cmt_valid && cmt_need) begin
                if (pk == 0) pair_odd = cmt_addr[0];
                cmt_data = pair_odd ? {eu_wdata[7:0], eu_wdata[15:8]}
                                    : eu_wdata;
                cmt_need = 1'b0;
                if (opr_held != 2'd3) opr_held = opr_held + 2'd1;
            end else if ((rq_n != 2'd0) && rq_need[0]) begin
                if (pk == 0) pair_odd = rq_addr[0][0];
                rq_data[0] = pair_odd ? {eu_wdata[7:0], eu_wdata[15:8]}
                                      : eu_wdata;
                rq_need[0] = 1'b0;
                if (opr_held != 2'd3) opr_held = opr_held + 2'd1;
            end else if ((rq_n == 2'd2) && rq_need[1]) begin
                if (pk == 0) pair_odd = rq_addr[0][0];
                rq_data[1] = pair_odd ? {eu_wdata[7:0], eu_wdata[15:8]}
                                      : eu_wdata;
                rq_need[1] = 1'b0;
                if (opr_held != 2'd3) opr_held = opr_held + 2'd1;
            end
        end

        if (q_flush) begin
            q_cnt = 4'd0; q_head = 3'd0; grn_n = 2'd0; grn_ttl = 2'd0;
            cs_r      = flush_cs;
            fetch_ptr = flush_ip;
            suspended = 1'b0;
            infl_ttl  = 2'd0;  infl_now = 1'b0;

            pf_owed = 1'b1;

            pf_arm = 1'b1;

            no_eval = 1'b0;  ne_now = 1'b0;
            absorb_ttl = 2'd0;

            if (run && cur_fetch)       cur_pn = 2'd0;
            if (cmt_valid && cmt_fetch) cmt_pn = 2'd0;
            flush_eval = 1'b1;

            if (!qse_l && !(flush_rep && !flush_pend && flush_direct))
                e_pend = 1'b1;
        end

        ev_here  = 1'b0;
        ev_latch = 1'b0;
        if (run) begin

            if ((ts == TS_T2) && cur_wr && (opr_held != 2'd0)) begin
                opr_held    = opr_held - 2'd1;
                set_oprfree = 1'b1;
            end

            if (ts == TS_T3) begin
                occ = {1'b0, q_cnt}
                    + (cur_fetch ? {3'b0, cur_pn} : 5'd0)
                    + ((cmt_valid && cmt_fetch) ? {3'b0, cmt_pn} : 5'd0)
                    + (infl_now ? {3'b0, infl_n_now} : 5'd0);
                pf_arm = (occ <= 5'd4) && !halted;
            end

            if (evi_l) begin
                ev_here  = 1'b1;

                ev_latch = !cur_halt;
                evald    = 1'b1;
                sev      = 2'd1;

                set_noeval = 1'b1;
            end
            if (hfree_l) ev_here = 1'b1;

            if (ts == TS_T4) begin

                land_ttl = (sev_now >= 2'd2) ? 2'd0 : (2'd2 - sev_now);
                if (cur_fetch && (cur_pn != 2'd0)) begin
                    qi = {1'b0, q_head} + q_cnt;
                    if (qi >= 4'd6) qi = qi - 4'd6;
                    if (cur_pn == 2'd2) begin
                        q_mem[qi[2:0]] = cur_data[7:0];
                        qi = (qi == 4'd5) ? 4'd0 : qi + 4'd1;
                        q_mem[qi[2:0]] = cur_data[15:8];
                    end else begin

                        q_mem[qi[2:0]] = cur_data[15:8];
                    end
                    q_cnt   = q_cnt + {2'b0, cur_pn};
                    grn_n   = cur_pn;
                    infl_n  = cur_pn;
                    new_ttl = land_ttl;
                    set_grn = 1'b1; set_infl = 1'b1; set_absorb = 1'b1;
                end

                if (!cur_fetch && !cur_halt) begin
                    done_wr = cur_wr;

                    if (cur_wr)
                        done_ctr = (land_ttl == 2'd0) ? 2'd1 : land_ttl;
                end
                run = 1'b0;
                ts  = TS_TI;
            end else begin
                case (ts)
                    TS_T1: ts = TS_T2;
                    TS_T2: begin

                        if (!cur_wr && !cur_halt) cur_data = ad_i;
                        ts = TS_T3;
                    end

                    TS_T3:   ts = ready ? TS_T4 : TS_TW;
                    TS_TW:   ts = ready ? TS_T4 : TS_TW;
                    default: ts = TS_T4;
                endcase
            end

            inta_halt_l = eu_halt_irq && run && cur_halt &&
                          (r_ts == TS_TW) && (ts == TS_T4) &&
                          (r_cdage == 3'd1) && cmt_valid && cmt_fetch;
            if (inta_halt_l) ev_here = 1'b0;

            if (evi_l && !cur_fetch && !cur_halt && !cur_wr) begin
                if (!cur_rd_last) begin
                    rd_first_hi  = cur_data[15:8];
                    rd_was_split = 1'b1;
                end else begin
                    done_wr  = 1'b0;
                    done_ctr = 2'd2;
                    if (rd_was_split) begin
                        rd_val = {cur_data[7:0], rd_first_hi};
                        rd_was_split = 1'b0;
                    end else begin
                        rd_val = cur_addr[0]
                               ? {cur_data[7:0], cur_data[15:8]}
                               : cur_data;
                    end
                    rd_land = rd_val;
                end
            end

            if (evi_l && cur_noaddr && cur_odd)
                rd_was_split = 1'b1;

            if (!run && cur_fetch && flush_eval && (rq_n == 2'd0))
                ev_here = 1'b1;
        end else if (!cmt_valid && !ne_now &&
                     !(flush_rep && flush_pend && !flush_staged_eval) &&
                     !eu_post_hold) begin
            ev_here = 1'b1;
        end
        if (inta_follow_preview) rd_was_split = 1'b0;
        if (vector_follow_preview) rd_was_split = 1'b0;
        if (inta_tail_replace) ev_here = 1'b1;

        did_grant = 1'b0;
        if (ev_here && !cmt_valid) begin
            flush_eval = 1'b0;
            gr_ok = 1'b0;
            occ = {1'b0, q_cnt}
                + ((run && cur_fetch) ? {3'b0, cur_pn} : 5'd0)
                + (infl_now ? {3'b0, infl_n_now} : 5'd0);

            rmw_yield = (rq_n != 2'd0) && rq_late[0] && rq_wr[0] &&
                        (rq_bs[0] == BS_MEMW) && !cur_fetch && !cur_wr &&
                        (cur_bs == BS_MEMR) && cur_rd_last &&
                        (rq_addr[0] == cur_addr) && (dage <= 3'd6) &&
                        !(suspended && !pf_owed) &&
                        (ev_latch ? pf_arm : ((occ <= 5'd4) && !halted));
            if ((rq_n != 2'd0) && !rmw_yield) begin

                cmt_bs = rq_bs[0]; cmt_addr = rq_addr[0];

                cmt_ghost = rq_ghost[0];
                if (rq_ghost[0] && (g_age != 2'd1))
                    cmt_addr = (g_age == 2'd0) ? g_sp : g_bare;
                cmt_data = rq_data[0]; cmt_ube_n = rq_ube[0];
                cmt_odd = rq_odd[0];
                cmt_seg = rq_seg[0]; cmt_noaddr = rq_noaddr[0];
                cmt_wr = rq_wr[0]; cmt_need = rq_need[0];
                cmt_rd_last = rq_last[0];
                cmt_fetch = 1'b0; cmt_halt = 1'b0; cmt_pn = 2'd0;
                rq_bs[0] = rq_bs[1]; rq_addr[0] = rq_addr[1];
                rq_data[0] = rq_data[1]; rq_ube[0] = rq_ube[1];
                rq_odd[0] = rq_odd[1];
                rq_seg[0] = rq_seg[1]; rq_noaddr[0] = rq_noaddr[1];
                rq_wr[0] = rq_wr[1]; rq_need[0] = rq_need[1];
                rq_last[0] = rq_last[1];
                rq_late[0] = rq_late[1];
                rq_ghost[0] = rq_ghost[1];
                rq_n = rq_n - 2'd1;

                if (cmt_rd_last) slot_accept = 1'b1;
                gr_ok = 1'b1;
            end else if (suspended && !pf_owed) begin

                gr_ok = 1'b0;
            end else begin

                if ((eu_post_hold && !eu_post) ||
                    (ev_latch ? !pf_arm : ((occ > 5'd4) || halted)))
                    gr_ok = 1'b0;
                else begin

                    fetch_lin = {flush_cs, 4'd0} + {4'd0, fetch_ptr};
                    cmt_bs = BS_CODE; cmt_addr = fetch_lin; cmt_data = 16'd0;
                    cmt_ghost = 1'b0;
                    cmt_ube_n = 1'b0; cmt_seg = 2'd2; cmt_noaddr = 1'b0;
                    cmt_odd = 1'b0;
                    cmt_wr = 1'b0; cmt_need = 1'b0; cmt_rd_last = 1'b1;
                    cmt_fetch = 1'b1; cmt_halt = 1'b0;

                    cmt_pn = fetch_lin[0] ? 2'd1 : 2'd2;
                    cmt_prev_fp = fetch_ptr;
                    last_fetch_addr = fetch_lin[15:0];
                    fetch_ptr = fetch_ptr + {14'd0, cmt_pn};
                    cmt_was_owed = pf_owed;
                    pf_owed = 1'b0;
                    gr_ok = 1'b1;
                end
            end
            if (gr_ok) begin
                if (!cmt_fetch) cmt_was_owed = pf_owed;
                cmt_valid = 1'b1;
                cdage     = 3'd0;
                did_grant = 1'b1;
            end
        end

        if (eu_halt_irq && cur_halt && (r_cdage == 3'd2) &&
            cmt_valid && cmt_noaddr &&
            !run && (rq_n != 2'd2)) begin
            rq_bs[1] = rq_bs[0]; rq_addr[1] = rq_addr[0];
            rq_data[1] = rq_data[0]; rq_ube[1] = rq_ube[0];
            rq_odd[1] = rq_odd[0]; rq_seg[1] = rq_seg[0];
            rq_noaddr[1] = rq_noaddr[0]; rq_wr[1] = rq_wr[0];
            rq_need[1] = rq_need[0]; rq_last[1] = rq_last[0];
            rq_late[1] = rq_late[0];
            rq_ghost[1] = rq_ghost[0];
            rq_bs[0] = cmt_bs; rq_addr[0] = cmt_addr;
            rq_data[0] = cmt_data; rq_ube[0] = cmt_ube_n;
            rq_odd[0] = cmt_odd; rq_seg[0] = cmt_seg;
            rq_noaddr[0] = cmt_noaddr; rq_wr[0] = cmt_wr;
            rq_need[0] = cmt_need; rq_last[0] = cmt_rd_last;
            rq_late[0] = 1'b0;
            rq_ghost[0] = cmt_ghost;
            rq_n = rq_n + 2'd1;
            slot_accept = 1'b0;
            cmt_valid = 1'b0;
        end

        if (inta_preview && cmt_valid && cmt_noaddr)
            cmt_odd = 1'b1;

        if (cmt_valid && !did_grant && (cdage != 3'd7))
            cdage = cdage + 3'd1;

        if (cmt_valid && !did_grant && (cdage >= 3'd3) &&
            (!run || (ts == TS_T4))) begin
            cmt_valid = 1'b0;
            if (cmt_fetch) begin
                fetch_ptr = cmt_prev_fp;
                pf_owed   = cmt_was_owed;
            end else if (rq_n != 2'd2) begin

                rq_bs[1] = rq_bs[0]; rq_addr[1] = rq_addr[0];
                rq_data[1] = rq_data[0]; rq_ube[1] = rq_ube[0];
                rq_odd[1] = rq_odd[0];
                rq_seg[1] = rq_seg[0]; rq_noaddr[1] = rq_noaddr[0];
                rq_wr[1] = rq_wr[0]; rq_need[1] = rq_need[0];
                rq_last[1] = rq_last[0];
                rq_late[1] = rq_late[0];
                rq_ghost[1] = rq_ghost[0];
                rq_bs[0] = cmt_bs; rq_addr[0] = cmt_addr;
                rq_data[0] = cmt_data; rq_ube[0] = cmt_ube_n;
                rq_odd[0] = cmt_odd;
                rq_seg[0] = cmt_seg; rq_noaddr[0] = cmt_noaddr;
                rq_wr[0] = cmt_wr; rq_need[0] = cmt_need;
                rq_last[0] = cmt_rd_last;

                rq_late[0] = 1'b0;

                rq_ghost[0] = cmt_ghost;
                rq_n = rq_n + 2'd1;
                slot_accept = 1'b0;
            end
        end

        if (inta_halt_l && cmt_valid && cmt_fetch) begin
            cmt_valid = 1'b0;
            fetch_ptr = cmt_prev_fp;
            pf_owed   = cmt_was_owed;

            set_noeval = 1'b1;
        end

        if (!run && cmt_valid &&
            ((cdage != 3'd0) ||
             (flush_fast && did_grant && cmt_fetch) ||
             (vector_follow_preview && did_grant && !cmt_fetch))) begin
            run = 1'b1; ts = TS_T1;
            cur_bs = cmt_bs; cur_addr = cmt_addr; cur_data = cmt_data;
            cur_ube_n = cmt_ube_n; cur_seg = cmt_seg; cur_odd = cmt_odd;
            cur_fetch = cmt_fetch; cur_halt = cmt_halt;
            cur_noaddr = cmt_noaddr; cur_wr = cmt_wr; cur_need = cmt_need;
            cur_rd_last = cmt_rd_last; cur_pn = cmt_pn;
            cur_late_t1 = (flush_fast || vector_follow_preview) ? 1'b0
                        : (cdage != 3'd1) || (cmt_noaddr && cmt_odd);

            dage  = (flush_fast || vector_follow_preview) ? 3'd1 : cdage;
            evald = 1'b0; sev = 2'd0;
            cmt_valid = 1'b0;

            if (!cmt_fetch && cmt_rd_last && slot_accept) begin
                slot_busy   = 1'b0;
                slot_accept = 1'b0;
            end

            if (cur_need && cur_wr)
                cur_data = cur_odd ? {rd_val[7:0], rd_val[15:8]} : rd_val;
        end else if (run) begin
            if (dage != 3'd7) dage = dage + 3'd1;
        end

        if (eu_halt) halted = 1'b1;

        if (halt_pending && !run && !cmt_valid && !set_noeval &&
            !eu_unhalt_disp) begin
            cmt_bs = BS_HALT; cmt_ghost = 1'b0;

            cmt_addr = {last_ad_hi, last_ad_lo};
            cmt_data = last_ad_lo;
            cmt_ube_n = 1'b1; cmt_seg = 2'd2; cmt_noaddr = 1'b0; cmt_odd = 1'b0;
            cmt_wr = 1'b0; cmt_need = 1'b0; cmt_rd_last = 1'b1;
            cmt_fetch = 1'b0; cmt_halt = 1'b1; cmt_pn = 2'd0;
            cmt_valid = 1'b1; cdage = 3'd0; cmt_was_owed = pf_owed;
            halt_pending = 1'b0;
        end

        ready_prev = ready;
        no_eval    = set_noeval;

        opr_free_p = set_oprfree;
        if (set_grn)    grn_ttl    = new_ttl;
        else if (grn_ttl    != 2'd0) grn_ttl    = grn_ttl - 2'd1;
        if (set_infl)   infl_ttl   = new_ttl;
        else if (infl_ttl   != 2'd0) infl_ttl   = infl_ttl - 2'd1;
        if (set_absorb) absorb_ttl = new_ttl;
        else if (absorb_ttl != 2'd0) absorb_ttl = absorb_ttl - 2'd1;
        if (run && evald && (sev != 2'd3) && !evi_l) sev = sev + 2'd1;

    end
end

always_ff @(posedge clk) if (ss_we || srst || ce) begin
    r_run <= (srst && !ss_we) ? run_rst : run;
    r_ts <= (srst && !ss_we) ? ts_rst : ts;
    r_cur_bs <= (srst && !ss_we) ? cur_bs_rst : cur_bs;
    r_cur_addr <= (srst && !ss_we) ? cur_addr_rst : cur_addr;
    r_cur_data <= (srst && !ss_we) ? cur_data_rst : cur_data;
    r_cur_ube_n <= (srst && !ss_we) ? cur_ube_n_rst : cur_ube_n;
    r_cur_odd <= (srst && !ss_we) ? cur_odd_rst : cur_odd;
    r_cur_seg <= (srst && !ss_we) ? cur_seg_rst : cur_seg;
    r_cur_fetch <= (srst && !ss_we) ? cur_fetch_rst : cur_fetch;
    r_cur_halt <= (srst && !ss_we) ? cur_halt_rst : cur_halt;
    r_cur_noaddr <= (srst && !ss_we) ? cur_noaddr_rst : cur_noaddr;
    r_cur_wr <= (srst && !ss_we) ? cur_wr_rst : cur_wr;
    r_cur_need <= (srst && !ss_we) ? cur_need_rst : cur_need;
    r_cur_rd_last <= (srst && !ss_we) ? cur_rd_last_rst : cur_rd_last;
    r_cur_pn <= (srst && !ss_we) ? cur_pn_rst : cur_pn;
    r_cur_late_t1 <= (srst && !ss_we) ? cur_late_t1_rst : cur_late_t1;
    r_evald <= (srst && !ss_we) ? evald_rst : evald;
    r_sev <= (srst && !ss_we) ? sev_rst : sev;
    r_dage <= (srst && !ss_we) ? dage_rst : dage;
    r_cmt_valid <= (srst && !ss_we) ? cmt_valid_rst : cmt_valid;
    r_cmt_bs <= (srst && !ss_we) ? cmt_bs_rst : cmt_bs;
    r_cmt_addr <= (srst && !ss_we) ? cmt_addr_rst : cmt_addr;
    r_cmt_data <= (srst && !ss_we) ? cmt_data_rst : cmt_data;
    r_cmt_ube_n <= (srst && !ss_we) ? cmt_ube_n_rst : cmt_ube_n;
    r_cmt_odd <= (srst && !ss_we) ? cmt_odd_rst : cmt_odd;
    r_cmt_seg <= (srst && !ss_we) ? cmt_seg_rst : cmt_seg;
    r_cmt_fetch <= (srst && !ss_we) ? cmt_fetch_rst : cmt_fetch;
    r_cmt_halt <= (srst && !ss_we) ? cmt_halt_rst : cmt_halt;
    r_cmt_noaddr <= (srst && !ss_we) ? cmt_noaddr_rst : cmt_noaddr;
    r_cmt_wr <= (srst && !ss_we) ? cmt_wr_rst : cmt_wr;
    r_cmt_need <= (srst && !ss_we) ? cmt_need_rst : cmt_need;
    r_cmt_rd_last <= (srst && !ss_we) ? cmt_rd_last_rst : cmt_rd_last;
    r_cmt_pn <= (srst && !ss_we) ? cmt_pn_rst : cmt_pn;
    r_cdage <= (srst && !ss_we) ? cdage_rst : cdage;
    r_cmt_prev_fp <= (srst && !ss_we) ? cmt_prev_fp_rst : cmt_prev_fp;
    r_cmt_was_owed <= (srst && !ss_we) ? cmt_was_owed_rst : cmt_was_owed;
    r_last_fetch_addr <= (srst && !ss_we) ? last_fetch_addr_rst : last_fetch_addr;
    r_q_head <= (srst && !ss_we) ? q_head_rst : q_head;
    r_q_cnt <= (srst && !ss_we) ? q_cnt_rst : q_cnt;
    r_grn_n <= (srst && !ss_we) ? grn_n_rst : grn_n;
    r_grn_ttl <= (srst && !ss_we) ? grn_ttl_rst : grn_ttl;
    r_fetch_ptr <= (srst && !ss_we) ? fetch_ptr_rst : fetch_ptr;
    r_cs_r <= (srst && !ss_we) ? cs_r_rst : cs_r;
    r_suspended <= (srst && !ss_we) ? suspended_rst : suspended;
    r_halted <= (srst && !ss_we) ? halted_rst : halted;
    r_halt_pending <= (srst && !ss_we) ? halt_pending_rst : halt_pending;
    r_pf_owed <= (srst && !ss_we) ? pf_owed_rst : pf_owed;
    r_pf_arm <= (srst && !ss_we) ? pf_arm_rst : pf_arm;
    r_infl_ttl <= (srst && !ss_we) ? infl_ttl_rst : infl_ttl;
    r_infl_n <= (srst && !ss_we) ? infl_n_rst : infl_n;
    r_absorb_ttl <= (srst && !ss_we) ? absorb_ttl_rst : absorb_ttl;
    r_no_eval <= (srst && !ss_we) ? no_eval_rst : no_eval;
    r_flush_eval <= (srst && !ss_we) ? flush_eval_rst : flush_eval;
    r_e_pend <= (srst && !ss_we) ? e_pend_rst : e_pend;
    r_rq_n <= (srst && !ss_we) ? rq_n_rst : rq_n;
    r_slot_busy <= (srst && !ss_we) ? slot_busy_rst : slot_busy;
    r_slot_accept <= (srst && !ss_we) ? slot_accept_rst : slot_accept;
    r_opr_held <= (srst && !ss_we) ? opr_held_rst : opr_held;
    r_rd_first_hi <= (srst && !ss_we) ? rd_first_hi_rst : rd_first_hi;
    r_rd_was_split <= (srst && !ss_we) ? rd_was_split_rst : rd_was_split;
    r_done_ctr <= (srst && !ss_we) ? done_ctr_rst : done_ctr;
    r_done_wr <= (srst && !ss_we) ? done_wr_rst : done_wr;
    r_rd_done_p <= (srst && !ss_we) ? rd_done_p_rst : rd_done_p;
    r_wr_done_p <= (srst && !ss_we) ? wr_done_p_rst : wr_done_p;
    r_opr_free_p <= (srst && !ss_we) ? opr_free_p_rst : opr_free_p;
    r_rd_val <= (srst && !ss_we) ? rd_val_rst : rd_val;
    r_rd_land <= (srst && !ss_we) ? rd_land_rst : rd_land;
    r_ready_prev <= (srst && !ss_we) ? ready_prev_rst : ready_prev;
    for (rj = 0; rj < 6; rj = rj + 1)
        r_q_mem[rj] <= (srst && !ss_we) ? q_mem_rst[rj] : q_mem[rj];
    for (rj = 0; rj < 2; rj = rj + 1) begin
        r_rq_bs[rj] <= (srst && !ss_we) ? rq_bs_rst[rj] : rq_bs[rj];
        r_rq_addr[rj] <= (srst && !ss_we) ? rq_addr_rst[rj] : rq_addr[rj];
        r_rq_data[rj] <= (srst && !ss_we) ? rq_data_rst[rj] : rq_data[rj];
        r_rq_ube[rj] <= (srst && !ss_we) ? rq_ube_rst[rj] : rq_ube[rj];
        r_rq_odd[rj] <= (srst && !ss_we) ? rq_odd_rst[rj] : rq_odd[rj];
        r_rq_seg[rj] <= (srst && !ss_we) ? rq_seg_rst[rj] : rq_seg[rj];
        r_rq_noaddr[rj] <= (srst && !ss_we) ? rq_noaddr_rst[rj] : rq_noaddr[rj];
        r_rq_wr[rj] <= (srst && !ss_we) ? rq_wr_rst[rj] : rq_wr[rj];
        r_rq_need[rj] <= (srst && !ss_we) ? rq_need_rst[rj] : rq_need[rj];
        r_rq_last[rj] <= (srst && !ss_we) ? rq_last_rst[rj] : rq_last[rj];
        r_rq_late[rj] <= (srst && !ss_we) ? rq_late_rst[rj] : rq_late[rj];
        r_rq_ghost[rj] <= (srst && !ss_we) ? rq_ghost_rst[rj] : rq_ghost[rj];
    end
    r_cmt_ghost <= (srst && !ss_we) ? cmt_ghost_rst : cmt_ghost;
    r_g_sp <= (srst && !ss_we) ? g_sp_rst : g_sp;
    r_g_bare <= (srst && !ss_we) ? g_bare_rst : g_bare;
    r_g_age <= (srst && !ss_we) ? g_age_rst : g_age;
    r_g_row_q <= (srst && !ss_we) ? g_row_q_rst : g_row_q;
end

`ifndef SYNTHESIS

always_ff @(posedge clk) if (!srst) begin
    assert (!(ce && eu_post && (r_rq_n == 2'd2)))
        else $error("v30u_biu: post dropped, request store full");
    assert (!(ce && eu_post && eu_split && (r_rq_n != 2'd0)))
        else $error("v30u_biu: split posted onto a non-empty request store");

    assert (!(r_run && r_evald && !r_cur_halt && (r_sev > 2'd2)))
        else $error("v30u_biu: sev bound violated (%0d)", r_sev);
    assert (!(r_cmt_valid && (r_cdage == 3'd7)))
        else $error("v30u_biu: announcement age saturated");
    assert (r_q_cnt <= 4'd6)
        else $error("v30u_biu: queue overflow (%0d)", r_q_cnt);
    assert (!((r_grn_ttl != 2'd0) && ({2'd0, r_grn_n} > r_q_cnt)))
        else $error("v30u_biu: green byte count exceeds queue");
end
`endif

always @(posedge clk) begin
    case (ss_addr)
        SSA_B_RUN:          ss_rdata <= {15'b0, r_run};
        SSA_B_TS:           ss_rdata <= {13'b0, r_ts};
        SSA_B_CUR_BS:       ss_rdata <= {13'b0, r_cur_bs};
        SSA_B_CUR_ADDR_LO:  ss_rdata <= r_cur_addr[15:0];
        SSA_B_CUR_ADDR_HI:  ss_rdata <= {12'b0, r_cur_addr[19:16]};
        SSA_B_CUR_DATA:     ss_rdata <= r_cur_data;
        SSA_B_CUR_UBE_N:    ss_rdata <= {15'b0, r_cur_ube_n};
        SSA_B_CUR_SEG:      ss_rdata <= {14'b0, r_cur_seg};
        SSA_B_CUR_FETCH:    ss_rdata <= {15'b0, r_cur_fetch};
        SSA_B_CUR_HALT:     ss_rdata <= {15'b0, r_cur_halt};
        SSA_B_CUR_NOADDR:   ss_rdata <= {15'b0, r_cur_noaddr};
        SSA_B_CUR_WR:       ss_rdata <= {15'b0, r_cur_wr};
        SSA_B_CUR_NEED:     ss_rdata <= {15'b0, r_cur_need};
        SSA_B_CUR_RDLAST:   ss_rdata <= {15'b0, r_cur_rd_last};
        SSA_B_CUR_PN:       ss_rdata <= {14'b0, r_cur_pn};
        SSA_B_CUR_LATET1:   ss_rdata <= {15'b0, r_cur_late_t1};
        SSA_B_EVALD:        ss_rdata <= {15'b0, r_evald};
        SSA_B_SEV:          ss_rdata <= {14'b0, r_sev};
        SSA_B_DAGE:         ss_rdata <= {13'b0, r_dage};
        SSA_B_CMT_VALID:    ss_rdata <= {15'b0, r_cmt_valid};
        SSA_B_CMT_BS:       ss_rdata <= {13'b0, r_cmt_bs};
        SSA_B_CMT_ADDR_LO:  ss_rdata <= r_cmt_addr[15:0];
        SSA_B_CMT_ADDR_HI:  ss_rdata <= {12'b0, r_cmt_addr[19:16]};
        SSA_B_CMT_DATA:     ss_rdata <= r_cmt_data;
        SSA_B_CMT_UBE_N:    ss_rdata <= {15'b0, r_cmt_ube_n};
        SSA_B_CMT_SEG:      ss_rdata <= {14'b0, r_cmt_seg};
        SSA_B_CMT_FETCH:    ss_rdata <= {15'b0, r_cmt_fetch};
        SSA_B_CMT_HALT:     ss_rdata <= {15'b0, r_cmt_halt};
        SSA_B_CMT_NOADDR:   ss_rdata <= {15'b0, r_cmt_noaddr};
        SSA_B_CMT_WR:       ss_rdata <= {15'b0, r_cmt_wr};
        SSA_B_CMT_NEED:     ss_rdata <= {15'b0, r_cmt_need};
        SSA_B_CMT_RDLAST:   ss_rdata <= {15'b0, r_cmt_rd_last};
        SSA_B_CMT_PN:       ss_rdata <= {14'b0, r_cmt_pn};
        SSA_B_CDAGE:        ss_rdata <= {13'b0, r_cdage};
        SSA_B_CMT_PREV_FP:  ss_rdata <= r_cmt_prev_fp;
        SSA_B_CMT_WAS_OWED: ss_rdata <= {15'b0, r_cmt_was_owed};
        SSA_B_LAST_UBE:     ss_rdata <= {15'b0, last_ube};
        SSA_B_LAST_FADDR:   ss_rdata <= r_last_fetch_addr;
        SSA_B_Q0:           ss_rdata <= {8'b0, r_q_mem[0]};
        SSA_B_Q1:           ss_rdata <= {8'b0, r_q_mem[1]};
        SSA_B_Q2:           ss_rdata <= {8'b0, r_q_mem[2]};
        SSA_B_Q3:           ss_rdata <= {8'b0, r_q_mem[3]};
        SSA_B_Q4:           ss_rdata <= {8'b0, r_q_mem[4]};
        SSA_B_Q5:           ss_rdata <= {8'b0, r_q_mem[5]};
        SSA_B_Q_HEAD:       ss_rdata <= {13'b0, r_q_head};
        SSA_B_Q_CNT:        ss_rdata <= {12'b0, r_q_cnt};
        SSA_B_GRN_N:        ss_rdata <= {14'b0, r_grn_n};
        SSA_B_GRN_TTL:      ss_rdata <= {14'b0, r_grn_ttl};
        SSA_B_FETCH_PTR:    ss_rdata <= r_fetch_ptr;
        SSA_B_CS:           ss_rdata <= r_cs_r;
        SSA_B_SUSPENDED:    ss_rdata <= {15'b0, r_suspended};
        SSA_B_HALTED:       ss_rdata <= {15'b0, r_halted};
        SSA_B_HALT_PEND:    ss_rdata <= {15'b0, r_halt_pending};
        SSA_B_PF_OWED:      ss_rdata <= {15'b0, r_pf_owed};
        SSA_B_PF_ARM:       ss_rdata <= {15'b0, r_pf_arm};
        SSA_B_INFL_TTL:     ss_rdata <= {14'b0, r_infl_ttl};
        SSA_B_INFL_N:       ss_rdata <= {14'b0, r_infl_n};
        SSA_B_ABSORB_TTL:   ss_rdata <= {14'b0, r_absorb_ttl};
        SSA_B_NO_EVAL:      ss_rdata <= {15'b0, r_no_eval};
        SSA_B_FLUSH_EVAL:   ss_rdata <= {15'b0, r_flush_eval};
        SSA_B_E_PEND:       ss_rdata <= {15'b0, r_e_pend};
        SSA_B_RQ_N:         ss_rdata <= {14'b0, r_rq_n};
        SSA_B_RQ0_BS:       ss_rdata <= {13'b0, r_rq_bs[0]};
        SSA_B_RQ0_ADDR_LO:  ss_rdata <= r_rq_addr[0][15:0];
        SSA_B_RQ0_ADDR_HI:  ss_rdata <= {12'b0, r_rq_addr[0][19:16]};
        SSA_B_RQ0_DATA:     ss_rdata <= r_rq_data[0];
        SSA_B_RQ0_UBE:      ss_rdata <= {15'b0, r_rq_ube[0]};
        SSA_B_RQ0_SEG:      ss_rdata <= {14'b0, r_rq_seg[0]};
        SSA_B_RQ0_NOADDR:   ss_rdata <= {15'b0, r_rq_noaddr[0]};
        SSA_B_RQ0_WR:       ss_rdata <= {15'b0, r_rq_wr[0]};
        SSA_B_RQ0_NEED:     ss_rdata <= {15'b0, r_rq_need[0]};
        SSA_B_RQ0_LAST:     ss_rdata <= {15'b0, r_rq_last[0]};
        SSA_B_RQ1_BS:       ss_rdata <= {13'b0, r_rq_bs[1]};
        SSA_B_RQ1_ADDR_LO:  ss_rdata <= r_rq_addr[1][15:0];
        SSA_B_RQ1_ADDR_HI:  ss_rdata <= {12'b0, r_rq_addr[1][19:16]};
        SSA_B_RQ1_DATA:     ss_rdata <= r_rq_data[1];
        SSA_B_RQ1_UBE:      ss_rdata <= {15'b0, r_rq_ube[1]};
        SSA_B_RQ1_SEG:      ss_rdata <= {14'b0, r_rq_seg[1]};
        SSA_B_RQ1_NOADDR:   ss_rdata <= {15'b0, r_rq_noaddr[1]};
        SSA_B_RQ1_WR:       ss_rdata <= {15'b0, r_rq_wr[1]};
        SSA_B_RQ1_NEED:     ss_rdata <= {15'b0, r_rq_need[1]};
        SSA_B_RQ1_LAST:     ss_rdata <= {15'b0, r_rq_last[1]};
        SSA_B_RQ_LATE:      ss_rdata <= {14'b0, r_rq_late[1], r_rq_late[0]};
        SSA_B_SLOT_BUSY:    ss_rdata <= {15'b0, r_slot_busy};
        SSA_B_SLOT_ACC:     ss_rdata <= {15'b0, r_slot_accept};
        SSA_B_OPR_HELD:     ss_rdata <= {14'b0, r_opr_held};
        SSA_B_RD_FIRST_HI:  ss_rdata <= {8'b0, r_rd_first_hi};
        SSA_B_RD_WAS_SPLIT: ss_rdata <= {15'b0, r_rd_was_split};
        SSA_B_CUR_ODD:      ss_rdata <= {15'b0, r_cur_odd};
        SSA_B_CMT_ODD:      ss_rdata <= {15'b0, r_cmt_odd};
        SSA_B_RQ0_ODD:      ss_rdata <= {15'b0, r_rq_odd[0]};
        SSA_B_RQ1_ODD:      ss_rdata <= {15'b0, r_rq_odd[1]};
        SSA_B_RD_LAND:      ss_rdata <= r_rd_land;
        SSA_B_DONE_CTR:     ss_rdata <= {14'b0, r_done_ctr};
        SSA_B_DONE_WR:      ss_rdata <= {15'b0, r_done_wr};
        SSA_B_RD_DONE_P:    ss_rdata <= {15'b0, r_rd_done_p};
        SSA_B_WR_DONE_P:    ss_rdata <= {15'b0, r_wr_done_p};
        SSA_B_OPR_FREE_P:   ss_rdata <= {15'b0, r_opr_free_p};
        SSA_B_RD_VAL:       ss_rdata <= r_rd_val;
        SSA_B_READY_PREV:   ss_rdata <= {15'b0, r_ready_prev};
`ifdef V30_MUXED_AD
        SSA_B_T1_HALF2:     ss_rdata <= {15'b0, t1_half2};
`endif

        SSA_B_LAST_AD_HI:   ss_rdata <= {12'b0, last_ad_hi};
        SSA_B_LAST_AD_LO:   ss_rdata <= last_ad_lo;
        SSA_B_GHOST_SP_LO:  ss_rdata <= r_g_sp[15:0];
        SSA_B_GHOST_SP_HI:  ss_rdata <= {12'b0, r_g_sp[19:16]};
        SSA_B_GHOST_BARE_LO:ss_rdata <= r_g_bare[15:0];
        SSA_B_GHOST_BARE_HI:ss_rdata <= {12'b0, r_g_bare[19:16]};
        SSA_B_GHOST_AGE:    ss_rdata <= {14'b0, r_g_age};
        SSA_B_GHOST_TAG:    ss_rdata <= {12'b0, r_g_row_q, r_cmt_ghost,
                                         r_rq_ghost[1], r_rq_ghost[0]};
        default:            ss_rdata <= 16'h0000;
    endcase
end

always @(posedge clk) begin
    if (ss_we && ss_addr == SSA_B_LAST_UBE) last_ube <= ss_wdata[0];

    else if (srst) last_ube <= 1'b0;
    else if (ce)   last_ube <= ube_n;
end

always @(posedge clk) begin
    if (ss_we && ss_addr == SSA_B_LAST_AD_HI) last_ad_hi <= ss_wdata[3:0];

    else if (srst) last_ad_hi <= data_ps(2'd2);
    else if (ce && (ad_oe_addr || ad_oe_ps)) last_ad_hi <= ad_o[19:16];
end
always @(posedge clk) begin
    if (ss_we && ss_addr == SSA_B_LAST_AD_LO) last_ad_lo <= ss_wdata;
    else if (srst) last_ad_lo <= last_fetch_addr_rst;
    else if (ce && (ad_oe_addr || ad_oe_data)) last_ad_lo <= ad_o[15:0];
end

`ifndef SYNTHESIS
logic utrace_en;
integer utrace_clk;
initial begin
    utrace_en = $test$plusargs("utrace");
    utrace_clk = 0;
end
always @(posedge clk) begin
    if (srst) utrace_clk <= 0;
    else if (ce) begin
        if (utrace_en)

            /* verilator lint_off WIDTHEXPAND */
            $display("u %0d ts=%0d run=%0d dage=%0d rdyp=%0d ev=%0d evald=%0d sev=%0d cmt=%0d cdage=%0d fetch=%0d ca=%05x cd=%04x pn=%0d occ=%0d arm=%0d infl=%0d absorb=%0d grn=%0d,%0d q=%0d owed=%0d susp=%0d halt=%0d ne=%0d fe=%0d epend=%0d qse=%0d pop=%0d rq=%0d lfa=%04x",
                     utrace_clk, ts, run, dage, ready_prev, eval_inst,
                     evald, sev, cmt_valid, cdage, cur_fetch, cur_addr, cur_data,
                     cur_pn,
                     q_cnt + ((run && cur_fetch) ? {2'b0, cur_pn} : 4'd0)
                           + ((cmt_valid && cmt_fetch) ? {2'b0, cmt_pn} : 4'd0)
                           + ((infl_ttl != 2'd0) ? {2'b0, infl_n} : 4'd0),
                     pf_arm, infl_ttl, absorb_ttl, grn_n,
                     grn_ttl, q_cnt, pf_owed, suspended, halted,
                     no_eval, flush_eval, e_pend, qs_e_now, pop_now, rq_n,
                     last_fetch_addr);
            /* verilator lint_on WIDTHEXPAND */
        utrace_clk <= utrace_clk + 1;
    end
end

logic padtrace_en;
integer padtrace_clk;
initial begin
    padtrace_en = $test$plusargs("padtrace");
    padtrace_clk = 0;
end
always @(posedge clk) begin
    if (srst) padtrace_clk <= 0;
    else if (ce) begin
        if (padtrace_en)
            $display("P %0d ad=%05x oe_addr=%0d oe_ps=%0d oe_data=%0d disp=%0d strel=%0d haltaddr=%0d curhalt=%0d ts=%0d bs=%0d cmtaddr=%05x",
                     padtrace_clk, ad_o, ad_oe_addr, ad_oe_ps, ad_oe_data,
                     display, st_rel, halt_addr, r_cur_halt, r_ts, bs,
                     r_cmt_addr);
        padtrace_clk <= padtrace_clk + 1;
    end
end
`endif

wire _unused = &{1'b0, eu_word, ad_i[15:0], bkd_queue[47:0]};

endmodule
