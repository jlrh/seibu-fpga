//  Quartus extracted no clock enable, threaded `ce` through the EU's 61-level

module v30u_eu (
    input             clk,
    input             ce,
    input             srst,

    input       [7:0] q_byte,
    input             q_ripe,
    input             q_ripe_lead_n,
    input       [3:0] q_cnt,
    output            q_pop,
    output            q_first,
    output            q_flush,
    output            flush_pre,
    output            flush_rep,
    output            flush_stage,
    output            flush_pend,
    output            flush_nmi,
    output            flush_int_live,
    output     [15:0] flush_cs,
    output     [15:0] flush_cs_old,
    output            flush_cs_we,
    output     [15:0] flush_ip,

    output            eu_post,
    output            eu_post_hold,
    output            eu_halt_irq,
    output            eu_vector_post,
    output      [2:0] eu_bs,
    output     [19:0] eu_addr,
    output     [19:0] eu_addr2,
    output            eu_split,
    output      [1:0] eu_seg,
    output      [1:0] eu_seg2,
    output            eu_word,

    output            eu_ghost_row,
    output            eu_ghost_acc,
    output     [19:0] eu_ghost_sp,
    output     [19:0] eu_ghost_bare,
    input             eu_slot_busy,
    input             eu_slot_busy_n,
    input             eu_access_active,
    input             eu_direct_fetch,
    input             eu_fetch_tail,
    input             eu_ghost_full,
    input             eu_ghost_idle,
    input             eu_ghost_stack_first,
    output            eu_pair,
    output            eu_pair2,
    output     [15:0] eu_wdata,
    input      [15:0] eu_rdata_n,
    input             eu_rd_done_n,
    input             eu_rd_edge,
    input      [15:0] eu_rd_edge_d,
    input             eu_wr_done_n,
    input             eu_wr_eval,
    input             eu_opr_free,

    output            eu_susp,
    output            eu_resume,
    output            eu_halt,
    output            eu_unhalt,

    output            eu_unhalt_disp,
    input             halted,

    output            eu_bnd_take,
    output            eu_bnd_post,

    output            psw_ie,
    output            md8080,

    input             pin_int,
    input             pin_nmi,
    input             pin_poll_n,

    input             bkd_load,
    input     [223:0] bkd_regs,
    output    [223:0] dbg_regs,
    output            dbg_first_pop,
    output            dbg_pend,

    input       [8:0] ss_addr,
    input      [15:0] ss_wdata,
    input             ss_we,
    output reg [15:0] ss_rdata
);

import v30_ss_pkg::*;

`include "pla3_tables.svh"

localparam bit [2:0] BS_INTA = 3'd0, BS_IOR = 3'd1, BS_IOW = 3'd2,
                     BS_MEMR = 3'd5, BS_MEMW = 3'd6, BS_PASV = 3'd7;

localparam bit [2:0] R_AW = 3'd0, R_CW = 3'd1, R_DW = 3'd2, R_BW = 3'd3,
                     R_SP = 3'd4, R_BP = 3'd5, R_IX = 3'd6, R_IY = 3'd7;
localparam bit [1:0] SR_ES = 2'd0, SR_CS = 2'd1, SR_SS = 2'd2, SR_DS = 2'd3;
localparam bit [2:0] SEG_ZERO = 3'd4;

localparam bit [1:0] OK_NONE = 2'd0, OK_REG = 2'd1, OK_SREG = 2'd2,
                     OK_MEM = 2'd3;

localparam int FCY = 0, FP = 2, FAC = 4, FZ = 6, FS = 7,
               FBRK = 8, FIE = 9, FDIR = 10, FV = 11;
localparam bit [15:0] PSW_WRITABLE = 16'h0FD5;
localparam bit [15:0] PSW_FORCED   = 16'hF002;
localparam bit [15:0] ARITH_MASK   = 16'h0000 | (16'd1 << FCY) | (16'd1 << FP)
                                   | (16'd1 << FAC) | (16'd1 << FZ)
                                   | (16'd1 << FS) | (16'd1 << FV);

localparam bit [4:0] A_ADD=5'h00, A_OR=5'h01, A_ADC=5'h02, A_SBB=5'h03,
                     A_AND=5'h04, A_SUB=5'h05, A_XOR=5'h06, A_CMP=5'h07,
                     A_ROL=5'h08, A_ROR=5'h09, A_RCL=5'h0A, A_RCR=5'h0B,
                     A_SHL=5'h0C, A_SHR=5'h0D, A_SHL6=5'h0E, A_SAR=5'h0F,
                     A_ROL12=5'h10, A_DIV=5'h12, A_MUL=5'h13, A_ADJD=5'h14,
                     A_ADJA=5'h15, A_OPC=5'h16, A_BIT=5'h17,
                     A_INC=5'h18, A_DEC=5'h19, A_NOT=5'h1A, A_NEG=5'h1B,
                     A_INC2=5'h1C, A_DEC2=5'h1D, A_ABS=5'h1E, A_PASS=5'h1F;

localparam bit [1:0] TY_ALU = 2'd0, TY_JMP = 2'd1, TY_CTL = 2'd2;

localparam bit [3:0] C_C=4'd0, C_NC=4'd1, C_Z=4'd2, C_NZ=4'd3, C_OP8B=4'd4,
                     C_CNTZ=4'd5, C_L=4'd6, C_OP8=4'd7, C_ALWAYS=4'd8,
                     C_SIGN=4'd9, C_O=4'd10, C_NS=4'd11, C_REP=4'd12,
                     C_BUSY=4'd13, C_INTR=4'd14, C_OPC=4'd15;

localparam bit [3:0] I_ENDEM=4'd0, I_CITF=4'd1, I_MFC=4'd2, I_MFS=4'd3,
                     I_BCDINIT=4'd4, I_CLRCYV=4'd6, I_SETCYV=4'd7, I_SUSP=4'd8,
                     I_FLUSH=4'd9, I_SIGNTGL=4'd12, I_BCDNZ=4'd13,
                     I_FARJMP=4'd14;
localparam bit [2:0] E_MEMR=3'd1, E_MEMW=3'd2, E_INTATAIL=3'd3, E_INTA=3'd5,
                     E_WRITEBACK=3'd6;

localparam bit [2:0] REP_NONE=3'd0, REP_E=3'd1, REP_NE=3'd2, REP_C=3'd3,
                     REP_NC=3'd4;
localparam bit [1:0] TEST_NONE=2'd0, TEST_Z=2'd1, TEST_CY=2'd2;

reg [15:0] gpr [0:7];
reg [15:0] sreg [0:3];
reg [15:0] pc;
reg [15:0] psw;
reg [15:0] tmpa, tmpb, tmpc;

reg [15:0] ea_residue;

reg [15:0] ea_pair_rhs;
reg        ea_pair_valid;
reg [15:0] opr;
reg [15:0] ind;
reg [15:0] count;
reg  [7:0] pfxcnt;
reg [15:0] stat;
reg        sign_neg;
reg  [3:0] bit_n;

reg        tmpa_byte, tmpb_byte, tmpc_byte;
reg        opr_byte;

reg  [4:0] al_op;
reg  [1:0] al_tmp;
reg        al_eaconst;
reg [15:0] al_eaval;
reg  [1:0] al_adjust;
reg  [1:0] al_adjtmp;
reg        al_bitarm;
reg  [3:0] al_bitn;
reg        al_spent;

reg  [2:0] upc_page;
reg  [7:0] upc_opc;
reg  [3:0] upc_loc;

reg        seg_override;
reg  [1:0] seg_ovr;
reg  [2:0] rep_kind;
reg        lock_pfx;
reg  [7:0] opc_reg;
reg        op8, imm8;
reg  [4:0] opc_base;
reg        opc_from_modrm;
reg  [2:0] modrm_reg;
reg  [3:0] xop;
reg  [1:0] rep_test;
reg        rep_pol;
reg        bus_word;
reg        opc8080;
reg        mode8080;
reg        intr_pending;
reg        eu_halted;

reg  [3:0] int_p;
reg  [4:0] nmi_p;
reg        nmi_latch;
reg  [3:0] ie_p;
reg        rep_chain;
reg        irq_shadow;
reg        bnd_armed;
reg        irq_sel_nmi;
reg        irq_sel_brk;
reg        unhalt_pend;
reg        irq_fast_inta;
reg        irq_halt_entry;

`ifndef V30_BRK_FLOOR
 `define V30_BRK_FLOOR 4
`endif
localparam int BRK_FLOOR = `V30_BRK_FLOOR;
reg [BRK_FLOOR-1:0] brk_p;
reg        brk_arm;
reg        brk_smp;

reg  [1:0] m_kind, r_kind, wb_kind;
reg  [2:0] m_idx,  r_idx,  wb_idx;
reg [15:0] m_ea,   r_ea,   wb_ea;
reg  [2:0] m_seg,  r_seg,  wb_seg;
reg        m_byte, r_byte, wb_byte;

reg        pend_active;
reg [15:0] pend_off;
reg  [2:0] pend_seg;
reg        pend_byte;
reg        pend_io;
reg        opr_fresh;

reg        opr_loaded;

reg [15:0] rdq0, rdq1;
reg  [1:0] rdq_n;
reg  [1:0] rd_pending;

reg        rdp0_byte, rdp1_byte;
reg        rdq0_byte, rdq1_byte;
reg        ghost_rd_discard;
reg  [1:0] rd_done_cnt;
reg        rd_age0;
reg        iend_owed;
reg  [2:0] rst_ctr;
reg [15:0] tsel;
reg  [7:0] pe_opc_reg;
reg        pe_opc8080;
reg        pe_op8;
reg  [7:0] pe_pfxcnt;
reg  [1:0] wr_out;

reg        opc_valid;
reg  [7:0] opc_byte;
reg        pop_is_first;

reg  [7:0] ld_b;
reg [13:0] ld_pla;
reg        ld_ext;
reg  [2:0] ld_page;
reg        ld_hasrm;
reg  [7:0] ld_rm;
reg [15:0] ld_disp;
reg  [7:0] ld_dlo;
reg        ld_grpd;
reg        ld_byte;
reg        ld_preread;
reg        ld_ripe_prev;

reg  [5:0] st;
reg  [1:0] chg;
reg        ending;
reg  [1:0] rowq;
reg        row_posted;
reg        row_paired;
reg [15:0] rloop_n;
reg        suppress_commit;
reg        first_pop_seen;
reg  [7:0] rowb0, rowb1;
reg        poste;

localparam bit [5:0]
    S_OPC_POP   = 6'd0,
    S_TAKE_OPC  = 6'd1,
    S_DECODE    = 6'd2,
    S_DECODE2   = 6'd3,
    S_PFX_CHG   = 6'd4,
    S_EXT_CHG1  = 6'd5,
    S_EXT_POP   = 6'd6,
    S_1BL_LEAD  = 6'd7,
    S_MODRM     = 6'd8,
    S_D8_A      = 6'd9,
    S_D8_B      = 6'd10,
    S_D16_LO    = 6'd11,
    S_D16_A     = 6'd12,
    S_D16_HI    = 6'd13,
    S_EA_CHG    = 6'd14,
    S_EA_CALC   = 6'd15,
    S_NORM_CHG  = 6'd16,
    S_BIND      = 6'd17,
    S_PRERD     = 6'd18,
    S_GRPD_CHG  = 6'd19,
    S_ENTER     = 6'd20,
    S_ROW       = 6'd22,
    S_ROW_CHG   = 6'd23,
    S_RLOOP     = 6'd24,
    S_EPOP      = 6'd25,
    S_TAIL      = 6'd26,
    S_TAIL_W    = 6'd27,
    S_TAIL_POP  = 6'd28,
    S_INSTR_END = 6'd29,
    S_HALTED    = 6'd30,
    S_RESET     = 6'd31,
    S_IRQ_D     = 6'd32,
    S_1BL_CHG   = 6'd33;

function automatic logic st_zero_ok(input [5:0] s);
    st_zero_ok = (s == S_TAKE_OPC) || (s == S_DECODE) || (s == S_DECODE2)
              || (s == S_EA_CALC)  || (s == S_BIND)   || (s == S_ENTER)
              || (s == S_TAIL)     || (s == S_TAIL_POP)
              || (s == S_INSTR_END);
endfunction

wire [12:0] dec_addr_next;
wire        dec_valid_next;
wire  [8:0] dec_bank_next;
reg   [9:0] dec_q;
wire        dec_valid = dec_q[9];
wire  [8:0] dec_bank  = dec_q[8:0];
wire [28:0] row;

v30u_ucrom u_ucrom (
    .dec_addr (dec_addr_next),
    .dec_valid(dec_valid_next),
    .dec_bank (dec_bank_next),
    .rom_addr ({dec_bank, upc_loc[1:0]}),
    .rom_word (row)
);

wire [4:0] r_s1   = row[28:24];
wire [4:0] r_d1   = row[23:19];
wire [3:0] r_s2   = row[18:15];
wire [1:0] r_d2   = row[14:13];
wire       r_f    = ~row[12];
wire       r_w    = ~row[11];
wire       r_e    = ~row[10];
wire [1:0] r_type = row[9] ? TY_CTL : (row[8] ? TY_JMP : TY_ALU);
wire [4:0] r_aluop= row[7:3];
wire [1:0] r_alutmp = row[2:1];
wire       r_r    = row[0] && (r_type == TY_ALU);
wire [3:0] r_cond = row[7:4];
wire [3:0] r_loc  = row[3:0];
wire [3:0] r_ictl = row[9:6] & 4'hF;
wire [2:0] r_ectl = row[4:2];
wire [1:0] r_sr   = row[1:0];

wire [3:0] c_ictl = row[8:5];
wire [2:0] c_ectl = row[4:2];
wire [1:0] c_sr   = row[1:0];

wire       r_farjmp = (r_type == TY_CTL) && (c_ictl == I_FARJMP);
wire [4:0] r_farloc = {c_ectl, c_sr};
wire       r_nopmove = (r_s1 == 5'h1F) && (r_d1 == 5'h1F);
wire       r_hasconst = (r_s1 == 5'h17);
wire [5:0] r_constval = {r_s2, r_d2};

wire [2:0] r_ect = r_farjmp ? 3'd7 : c_ectl;

wire       row_nop = !dec_valid;
wire [4:0] e_s1    = row_nop ? 5'h1F : r_s1;
wire [4:0] e_d1    = row_nop ? 5'h1F : r_d1;
wire [3:0] e_s2    = row_nop ? 4'hF  : r_s2;
wire [1:0] e_d2    = row_nop ? 2'd3  : r_d2;
wire       e_f     = row_nop ? 1'b0  : r_f;
wire       e_w     = row_nop ? 1'b0  : r_w;
wire       e_e     = row_nop ? 1'b0  : r_e;
wire       e_r     = row_nop ? 1'b0  : r_r;
wire [1:0] e_type  = row_nop ? TY_CTL : r_type;
wire [3:0] e_ictl  = row_nop ? 4'hF  : c_ictl;
wire [2:0] e_ectl  = row_nop ? 3'd7  : r_ect;
wire [1:0] e_sr    = row_nop ? 2'd3  : c_sr;
wire       e_farjmp= row_nop ? 1'b0  : r_farjmp;
wire       e_nopmv = row_nop ? 1'b1  : r_nopmove;
wire       e_hasc  = row_nop ? 1'b0  : r_hasconst;

wire e_is_rloop = (e_type == TY_ALU) && e_r;
wire e_have1 = !e_nopmv;
wire e_have2 = !e_hasc && ((e_s2 != 4'd15) || (e_d2 != 2'd3));

wire ext4s_early_e = (upc_page == 3'd4) && (upc_opc == 8'h21) &&
                     (upc_loc == 4'd5) && stat[FS] && !stat[FCY];
wire ext4s_early_wblock = (upc_page == 3'd4) && (upc_opc == 8'h21) &&
                          (upc_loc == 4'd3) && sig_flags[FS] && !sig_flags[FCY];

wire ext4s_early_post = poste && (upc_page == 3'd4) &&
                        (upc_opc == 8'h21) && (upc_loc == 4'd6);
wire ext4s_arch_d1 = (e_d1 <= 5'd4) || (e_d1 == 5'd15) ||
                     (e_d1 == 5'd18) || (e_d1 == 5'd19) ||
                     (e_d1 >= 5'd24);

function automatic [1:0] seg_code(input [2:0] s);
    case (s)
        3'd0: seg_code = 2'd0;
        3'd1: seg_code = 2'd2;
        3'd2: seg_code = 2'd1;
        3'd3: seg_code = 2'd3;
        default: seg_code = 2'd2;
    endcase
endfunction

wire row_io  = (e_sr == 2'd1) && ((xop == 4'hF) || (xop == 4'h6));

wire [2:0] row_seg = (e_sr == 2'd0) ? 3'd0
                   : (e_sr == 2'd1) ? SEG_ZERO
                   : (e_sr == 2'd2) ? 3'd2
                   : (m_kind == OK_MEM) ? m_seg
                   : (r_kind == OK_MEM) ? r_seg
                   : (seg_override ? {1'b0, seg_ovr} : 3'd3);

wire row_bbyte = op8 && !bus_word;

wire [15:0] seg_val = (row_seg == SEG_ZERO) ? 16'h0000 : sreg[row_seg[1:0]];
wire [19:0] row_phys = {seg_val, 4'd0} + {4'd0, ind};

wire row_reads_opr = (e_s1 == 5'd6);

wire nr_have   = (rd_done_cnt != 2'd0) || eu_rd_done_n;
wire nr_wait   = !nr_have && (rd_pending != 2'd0);

wire nr_extra_block = nr_have && rd_age0;

wire retire_ok_n = (wr_out == 2'd0) ||
                   ((wr_out == 2'd1) && eu_wr_done_n);

wire mfs_frame_release = (st == S_ROW) && e_f &&
                         (e_type == TY_JMP) && (r_cond == C_CNTZ) &&
                         e_have1 && (e_s1 == 5'd1) && (e_d1 == 5'd6);
wire eval_ok_n = (wr_out == 2'd0) ||
                 ((wr_out == 2'd1) && eu_wr_eval);
wire opr_free_now = mode8080          ? retire_ok_n
                  : mfs_frame_release ? eval_ok_n
                                      : eu_opr_free;

wire opr_starved = row_reads_opr && !opr_loaded && !nr_have &&
                   (rd_pending == 2'd0) && (rdq_n == 2'd0);

wire f_wait = row_reads_opr ? (nr_wait || opr_starved || !opr_free_now)
                            : !opr_free_now;

reg [2:0] poll_pipe;
wire poll_busy = poll_pipe[2];

wire irq_pin_int = int_p[2];

wire irq_int_lvl = (int_p[2] ||
                    (intr_pending && (rep_kind == REP_NONE) && !ie_p[3])) &&
                   ie_p[2] && psw[FIE];
wire irq_nmi_lvl = nmi_latch;
wire irq_any     = irq_nmi_lvl || irq_int_lvl;

wire irq_rep_1st = irq_nmi_lvl || (int_p[2] && psw[FIE]);
wire irq_rep_chn = irq_nmi_lvl || (int_p[1] && psw[FIE]);

wire row_q1 = e_have1 && (e_s1 == 5'd7);
wire row_q2 = e_have2 && (e_s2 == 4'd5);
wire [1:0] row_qn = {1'b0, row_q1} + {1'b0, row_q2};
wire row_need_q  = (st == S_ROW) && ({1'b0, rowq} < row_qn);

wire suppress_now = (e_s1 == 5'd20) && !sig_commits &&
                    (e_d1 == 5'd19) && (m_kind == OK_MEM);
wire row_wb_mem  = (wb_kind == OK_MEM) && !suppress_commit && !suppress_now;
wire row_is_read = (e_type == TY_CTL) && (e_ectl == E_MEMR);
wire row_is_wr   = (e_type == TY_CTL) && (e_ectl == E_MEMW);
wire row_is_wb   = (e_type == TY_CTL) && (e_ectl == E_WRITEBACK) && row_wb_mem;
wire row_is_inta = (e_type == TY_CTL) && (e_ectl == E_INTA);
wire row_bus     = row_is_read || row_is_wr || row_is_wb || row_is_inta;

wire ghost_read_stale_alu = (upc_page == 3'd0) && (upc_opc == 8'h8f) &&
                            row_is_read && (row_seg == 3'd2) &&
                            (m_kind == OK_REG) && (wb_kind == OK_REG) &&
                            e_have1 && (e_s1 == 5'd28) && (e_d1 == 5'd5) &&
                            e_have2 && (e_s2 == 4'd12) && (e_d2 == 2'd1);

wire ghost_preread_tail = (st == S_PRERD) && (upc_page == 3'd0) &&
                           (upc_opc == 8'h8f) && (upc_loc == 4'd4) &&
                           ghost_rd_discard;

wire [2:0] acc_seg   = row_is_wb ? wb_seg : row_seg;

wire       ghost_lost_io = row_io && (upc_page == 3'd1) &&
                           (upc_opc == 8'he4) && (pe_opc_reg == 8'h8f);
wire       acc_byte  = row_is_wb ? wb_byte : (row_bbyte && !ghost_lost_io);
wire       acc_io    = row_is_wb ? 1'b0 : (row_io && !ghost_lost_io);
wire [15:0] acc_segv = (acc_seg == SEG_ZERO) ? 16'h0000 : sreg[acc_seg[1:0]];

wire        pr_use_m = (m_kind == OK_MEM);
wire  [2:0] pr_seg   = pr_use_m ? m_seg : r_seg;
wire [15:0] pr_ea    = pr_use_m ? m_ea   : r_ea;
wire        pr_byte  = pr_use_m ? m_byte : r_byte;
wire [19:0] pr_phys  = {sreg[pr_seg[1:0]], 4'd0} + {4'd0, pr_ea};
wire        pr_split = !pr_byte && pr_phys[0];

wire  [2:0] pr_seg2  = (ghost_preread_tail && pr_split) ? 3'd3 : pr_seg;
wire [19:0] pr_phys2 = {sreg[pr_seg2[1:0]], 4'd0} + {4'd0, pr_ea + 16'd1};

wire [15:0] pend_segv = (pend_seg == SEG_ZERO) ? 16'h0000 : sreg[pend_seg[1:0]];
wire [19:0] pend_phys = pend_io ? {4'd0, pend_off}
                                : ({pend_segv, 4'd0} + {4'd0, pend_off});
wire       pend_split = !pend_byte && pend_phys[0];

function automatic [15:0] szp(input [16:0] r, input bbyte);
    logic [15:0] f;
    logic p;
    begin
        f = 16'd0;
        if (bbyte ? (r[7:0] == 8'd0) : (r[15:0] == 16'd0)) f[FZ] = 1'b1;
        if (bbyte ? r[7] : r[15]) f[FS] = 1'b1;
        p = ^r[7:0];
        if (!p) f[FP] = 1'b1;
        szp = f;
    end
endfunction

wire [7:0] opc_reg_eff = poste ? pe_opc_reg : opc_reg;
wire       opc8080_eff = poste ? pe_opc8080 : opc8080;
wire       op8_eff     = poste ? pe_op8     : op8;
wire [7:0] pfxcnt_eff  = poste ? pe_pfxcnt  : pfxcnt;
wire [2:0] opc_sel = opc_from_modrm ? modrm_reg : opc_reg_eff[5:3];
function automatic [4:0] opc8080_map(input [2:0] s);
    case (s)
        3'd0: opc8080_map = A_ADD;
        3'd1: opc8080_map = A_ADC;
        3'd2: opc8080_map = A_SUB;
        3'd3: opc8080_map = A_SBB;
        3'd4: opc8080_map = A_AND;
        3'd5: opc8080_map = A_XOR;
        3'd6: opc8080_map = A_OR;
        default: opc8080_map = A_CMP;
    endcase
endfunction
wire [4:0] alu_opc_sel = opc8080_eff ? opc8080_map(opc_sel)
                                     : (opc_base + {2'b0, opc_sel});

wire [4:0] eff_op = (al_op == A_OPC) ? alu_opc_sel : al_op;

wire [4:0] nxt_op = (r_aluop == A_OPC) ? alu_opc_sel : r_aluop;
wire is_iter = ((eff_op >= A_ROL) && (eff_op <= A_SAR)) ||
               (eff_op == A_ROL12) || (eff_op == A_DIV) || (eff_op == A_MUL);

wire [15:0] tmps [0:3];
assign tmps[0] = tmpa;
assign tmps[1] = tmpb;
assign tmps[2] = tmpc;
assign tmps[3] = 16'd0;

wire [15:0] tmps_lat [0:3];
assign tmps_lat[0] = tmpa;
assign tmps_lat[1] = tmpb;
assign tmps_lat[2] = tmpc;
assign tmps_lat[3] = 16'd0;

wire al_tag_b = (al_tmp == 2'd0) ? tmpa_byte
              : (al_tmp == 2'd1) ? tmpb_byte
              : (al_tmp == 2'd2) ? tmpc_byte : 1'b0;
wire al_width_byte = (eff_op == A_ABS) ? op8_eff : (tmpb_byte || al_tag_b);

wire ev_byte = al_width_byte && (eff_op != A_INC2) && (eff_op != A_DEC2);
wire [15:0] port_a = tmpb;
wire [15:0] port_b_raw = tmps[al_tmp];
wire [15:0] port_b = al_bitarm ? (port_b_raw & (16'd1 << al_bitn))
                               : port_b_raw;
wire [15:0] a_m = ev_byte ? {8'd0, port_a[7:0]} : port_a;
wire [15:0] b_m = ev_byte ? {8'd0, port_b[7:0]} : port_b;
wire        cin = psw[FCY];

wire [15:0] adj_src = tmps[al_adjtmp];
wire [7:0]  adj_al  = adj_src[7:0];
wire adj_lo  = (adj_al[3:0] > 4'd9) || psw[FAC];
wire adj_hi  = (al_adjust == 2'd1) &&
               (((adj_al[7:4] > 4'd9) || psw[FCY]) ||
                ((adj_al[7:4] == 4'd9) && (adj_al[3:0] > 4'd9) && !psw[FAC]));
wire [7:0] adj_corr = (adj_lo ? 8'h06 : 8'h00) + (adj_hi ? 8'h60 : 8'h00);
wire adj_sub = (eff_op == A_SUB);
wire [8:0] adj_sum = adj_sub ? ({1'b0, adj_al} - {1'b0, adj_corr})
                             : ({1'b0, adj_al} + {1'b0, adj_corr});
wire [7:0] adj_val8 = (al_adjust == 2'd2) ? {4'd0, adj_sum[3:0]} : adj_sum[7:0];
wire [7:0] adj_ahi = adj_src[15:8];
wire [7:0] adj_bhi = port_b[15:8];
wire [7:0] adj_rhi = adj_sub ? (adj_ahi - adj_bhi - {7'd0, adj_sum[8]})
                             : (adj_ahi + adj_bhi + {7'd0, adj_sum[8]});
wire [15:0] adj_flags = szp({9'd0, adj_sum[7:0]}, 1'b1)
                      | (16'd1 << FCY) & {16{(al_adjust == 2'd2) ? adj_lo : adj_hi}}
                      | (16'd1 << FAC) & {16{adj_lo}}
                      | (16'd1 << FV) & {16{adj_sub
                          ? (((adj_al ^ adj_corr) & (adj_al ^ adj_sum[7:0])) & 8'h80) != 8'h00
                          : ((~(adj_al ^ adj_corr) & (adj_al ^ adj_sum[7:0])) & 8'h80) != 8'h00}};

reg [16:0] ar_full;
reg [16:0] ar_m;
reg [15:0] ev_val;
reg [15:0] ev_flags;
reg [15:0] ev_mask;
reg        ev_commits;

wire [16:0] add_m = {1'b0, a_m} + {1'b0, b_m} +
                    {16'd0, ((eff_op == A_ADC) ? cin : 1'b0)};
wire [16:0] sub_m = {1'b0, a_m} - {1'b0, b_m} -
                    {16'd0, ((eff_op == A_SBB) ? cin : 1'b0)};
wire [15:0] add_f = port_a + port_b + {15'd0, ((eff_op == A_ADC) ? cin : 1'b0)};
wire [15:0] sub_f = port_a - port_b - {15'd0, ((eff_op == A_SBB) ? cin : 1'b0)};
wire add_cy = ev_byte ? add_m[8] : add_m[16];
wire sub_cy = ev_byte ? sub_m[8] : sub_m[16];
wire add_ac = (a_m[4] ^ b_m[4] ^ add_m[4]);
wire sub_ac = (a_m[4] ^ b_m[4] ^ sub_m[4]);
wire add_ov = ev_byte ? ((~(a_m[7] ^ b_m[7])) & (a_m[7] ^ add_m[7]))
                      : ((~(a_m[15] ^ b_m[15])) & (a_m[15] ^ add_m[15]));
wire sub_ov = ev_byte ? ((a_m[7] ^ b_m[7]) & (a_m[7] ^ sub_m[7]))
                      : ((a_m[15] ^ b_m[15]) & (a_m[15] ^ sub_m[15]));
wire [15:0] inc_m = b_m + 16'd1;
wire [15:0] dec_m = b_m - 16'd1;
wire inc_ac = (b_m[4] ^ 1'b0 ^ inc_m[4]) | (b_m[3:0] == 4'hF);
wire dec_ac = (b_m[3:0] == 4'h0);
wire inc_ov = ev_byte ? (b_m[7:0] == 8'h7F) : (b_m == 16'h7FFF);
wire dec_ov = ev_byte ? (b_m[7:0] == 8'h80) : (b_m == 16'h8000);
wire [15:0] neg_m = 16'd0 - b_m;

always @* begin
    ar_full = 17'd0;
    ar_m    = 17'd0;
    ev_val  = 16'd0;
    ev_flags= 16'd0;
    ev_mask = 16'd0;
    ev_commits = 1'b1;
    case (eff_op)
        A_ADD, A_ADC: begin
            ar_m = add_m; ev_val = add_f; ev_mask = ARITH_MASK;
            ev_flags = szp({1'b0, add_m[15:0]}, ev_byte);
            ev_flags[FCY] = add_cy;
            ev_flags[FAC] = add_ac;
            ev_flags[FV]  = add_ov;
        end
        A_SUB, A_SBB, A_CMP: begin
            ar_m = sub_m; ev_val = sub_f; ev_mask = ARITH_MASK;
            ev_flags = szp({1'b0, sub_m[15:0]}, ev_byte);
            ev_flags[FCY] = sub_cy;
            ev_flags[FAC] = sub_ac;
            ev_flags[FV]  = sub_ov;
            if (eff_op == A_CMP) ev_commits = 1'b0;
        end
        A_AND: begin
            ev_val = port_a & port_b; ev_mask = ARITH_MASK;
            ev_flags = szp({1'b0, a_m & b_m}, ev_byte);
        end
        A_OR: begin
            ev_val = port_a | port_b; ev_mask = ARITH_MASK;
            ev_flags = szp({1'b0, a_m | b_m}, ev_byte);
        end
        A_XOR: begin
            ev_val = port_a ^ port_b; ev_mask = ARITH_MASK;
            ev_flags = szp({1'b0, a_m ^ b_m}, ev_byte);
        end
        A_INC: begin
            ev_val = port_b + 16'd1;
            ev_mask = (16'd1<<FP)|(16'd1<<FAC)|(16'd1<<FZ)|(16'd1<<FS)|(16'd1<<FV);
            ev_flags = szp({1'b0, inc_m}, ev_byte);
            ev_flags[FAC] = inc_ac;
            ev_flags[FV]  = inc_ov;
        end
        A_DEC: begin
            ev_val = port_b - 16'd1;
            ev_mask = (16'd1<<FP)|(16'd1<<FAC)|(16'd1<<FZ)|(16'd1<<FS)|(16'd1<<FV);
            ev_flags = szp({1'b0, dec_m}, ev_byte);
            ev_flags[FAC] = dec_ac;
            ev_flags[FV]  = dec_ov;
        end
        A_INC2: begin ev_val = port_b + 16'd2; ev_mask = 16'd0; end
        A_DEC2: begin ev_val = port_b - 16'd2; ev_mask = 16'd0; end
        A_NOT:  begin ev_val = ~port_b;        ev_mask = 16'd0; end
        A_NEG:  begin
            ev_val = 16'd0 - port_b; ev_mask = ARITH_MASK;
            ev_flags = szp({1'b0, neg_m}, ev_byte);
            ev_flags[FCY] = (ev_byte ? (neg_m[7:0] != 8'd0) : (neg_m != 16'd0));
            ev_flags[FAC] = (b_m[4] ^ neg_m[4]);
            ev_flags[FV]  = ev_byte ? (b_m[7:0] == 8'h80) : (b_m == 16'h8000);
        end
        A_ABS: begin

            if (ev_byte) begin
                ev_val = port_b[7] ? {port_b[15:8], (8'd0 - port_b[7:0])}
                                   : port_b;
            end else begin
                ev_val = port_b[15] ? (16'd0 - port_b) : port_b;
            end
            ev_mask = 16'd0;
        end
        A_ADJD, A_ADJA, A_BIT: begin ev_val = port_b; ev_mask = 16'd0; end
        default: begin
            ev_val = port_b; ev_mask = ARITH_MASK;
            ev_flags = szp({1'b0, b_m}, ev_byte);
        end
    endcase

    if ((al_adjust != 2'd0) && ((eff_op == A_ADD) || (eff_op == A_SUB))) begin
        ev_val   = {adj_rhi, adj_val8};
        ev_flags = adj_flags;
        ev_mask  = ARITH_MASK;
        ev_commits = 1'b1;
    end
end

wire        it_byte = al_width_byte;
wire [15:0] it_a    = it_byte ? {8'd0, tmpb[7:0]} : tmpb;
wire [15:0] it_bop  = tmps[al_tmp];
wire [15:0] it_mask = it_byte ? 16'h00FF : 16'hFFFF;
wire        it_msb  = it_byte ? it_a[7] : it_a[15];
wire        it_lsb  = it_a[0];
reg  [15:0] it_val;
reg  [15:0] it_tmpa;
reg  [15:0] it_flags;
reg  [15:0] it_fmask;
reg         it_writes_tmpa;

wire [15:0] mul_mplier = it_byte ? {8'd0, tmpa[7:0]} : tmpa;
wire [15:0] mul_mcand  = it_byte ? {8'd0, it_bop[7:0]} : it_bop;
wire [16:0] mul_sum    = {1'b0, it_a} +
                         (mul_mplier[0] ? {1'b0, mul_mcand} : 17'd0);
wire        mul_cout   = it_byte ? mul_sum[8] : mul_sum[16];
wire [15:0] mul_hi     = it_byte
                       ? {8'd0, {mul_cout, mul_sum[7:1]}}
                       : {mul_cout, mul_sum[15:1]};
wire [15:0] mul_lo     = it_byte
                       ? {8'd0, {mul_sum[0], mul_mplier[7:1]}}
                       : {mul_sum[0], mul_mplier[15:1]};

wire [15:0] div_divisor = it_byte ? {8'd0, it_bop[7:0]} : it_bop;
wire [15:0] div_lo0     = it_byte ? {8'd0, tmpa[7:0]} : tmpa;

wire [16:0] div_hi0     = it_byte
                        ? {8'd0, it_a[7:0], div_lo0[7]}
                        : {it_a[15:0], div_lo0[15]};
wire [15:0] div_lo1     = (div_lo0 << 1) & it_mask;
wire        div_fits    = (div_hi0 >= {1'b0, div_divisor});
wire [15:0] div_hi1     = div_fits ? (div_hi0[15:0] - div_divisor)
                                   : div_hi0[15:0];
wire [15:0] div_lo2     = div_fits ? (div_lo1 | 16'd1) : div_lo1;

reg  [15:0] sh_r;
reg         sh_cy;
always @* begin
    sh_cy = 1'b0;
    sh_r  = 16'd0;
    case (eff_op)
        A_ROL: begin sh_cy = it_msb; sh_r = ((it_a << 1) | {15'd0, it_msb}) & it_mask; end
        A_ROR: begin sh_cy = it_lsb; sh_r = ((it_a >> 1) | (it_lsb ? (it_byte ? 16'h0080 : 16'h8000) : 16'd0)) & it_mask; end
        A_RCL: begin sh_cy = it_msb; sh_r = ((it_a << 1) | {15'd0, cin}) & it_mask; end
        A_RCR: begin sh_cy = it_lsb; sh_r = ((it_a >> 1) | (cin ? (it_byte ? 16'h0080 : 16'h8000) : 16'd0)) & it_mask; end
        A_SHL, A_SHL6: begin sh_cy = it_msb; sh_r = (it_a << 1) & it_mask; end
        A_SHR: begin sh_cy = it_lsb; sh_r = (it_a >> 1) & it_mask; end
        A_SAR: begin sh_cy = it_lsb; sh_r = ((it_a >> 1) | (it_msb ? (it_byte ? 16'h0080 : 16'h8000) : 16'd0)) & it_mask; end
        default: ;
    endcase
end
wire sh_left = (eff_op == A_ROL) || (eff_op == A_RCL) ||
               (eff_op == A_SHL) || (eff_op == A_SHL6);
wire sh_rmsb = it_byte ? sh_r[7] : sh_r[15];
wire sh_rmsb1= it_byte ? sh_r[6] : sh_r[14];
wire sh_v    = sh_left ? (sh_rmsb != sh_cy) : (sh_rmsb != sh_rmsb1);

wire sh_wrap = (eff_op == A_ROR) || (eff_op == A_RCR);
wire sh_fb   = sh_wrap ? sh_r[7] : 1'b0;
wire [7:0] sh_hi = sh_left ? {tmpb[14:8], tmpb[7]}
                           : {sh_fb, tmpb[15:9]};

always @* begin
    it_val   = 16'd0;
    it_tmpa  = tmpa;
    it_flags = 16'd0;
    it_fmask = 16'd0;
    it_writes_tmpa = 1'b0;
    case (eff_op)
        A_MUL: begin
            it_val  = it_byte ? {tmpb[15:8], mul_hi[7:0]} : mul_hi;
            it_tmpa = it_byte ? {tmpa[15:8], mul_lo[7:0]} : mul_lo;
            it_writes_tmpa = 1'b1;
        end
        A_DIV: begin
            it_val  = it_byte ? {tmpb[15:8], div_hi1[7:0]} : div_hi1;
            it_tmpa = it_byte ? {tmpa[15:8], div_lo2[7:0]} : div_lo2;
            it_writes_tmpa = 1'b1;
        end
        A_ROL12: begin
            it_val = {tmpb[14:0], tmpb[11]};
        end
        default: begin
            it_flags[FCY] = sh_cy;
            it_flags[FV]  = sh_v;
            if ((eff_op == A_SHL) || (eff_op == A_SHR) ||
                (eff_op == A_SAR) || (eff_op == A_SHL6)) begin
                it_flags = it_flags | szp({1'b0, sh_r}, it_byte);
                it_fmask = ARITH_MASK;
            end else begin
                it_fmask = (16'd1 << FCY) | (16'd1 << FV);
            end
            it_val = it_byte ? {sh_hi, sh_r[7:0]} : sh_r;
        end
    endcase
end

wire [15:0] sigma = al_eaconst ? al_eaval
                  : is_iter ? (al_spent ? tmpb : it_val)
                            : ev_val;
wire [15:0] sig_flags = is_iter ? it_flags : ev_flags;
wire [15:0] sig_mask  = al_eaconst ? 16'd0
                      : is_iter ? (al_spent ? 16'd0 : it_fmask)
                                : ev_mask;
wire        sig_commits = al_eaconst ? 1'b1 : (is_iter ? 1'b1 : ev_commits);

wire        sig_byte    = al_width_byte;

wire [15:0] flags_rd = (psw & PSW_WRITABLE) | PSW_FORCED;

function automatic [15:0] rb16(input [2:0] code, input [15:0] pair);
    rb16 = code[2] ? {pair[7:0], pair[15:8]} : pair;
endfunction

wire m_modrm_stack_word = (upc_page == 3'd3) &&
                          (m_kind == OK_REG) && m_byte && e_e &&
                          row_is_wr && (row_seg == 3'd2) &&
                          e_have1 && (e_s1 == 5'd19) && (e_d1 == 5'd6);

wire m_modrm_pc_word = (upc_page == 3'd3) &&
                       (m_kind == OK_REG) && m_byte &&
                       e_have1 && (e_s1 == 5'd19) && (e_d1 == 5'd4) &&
                       (e_ictl == I_FLUSH);
wire m_modrm_parent_word = m_modrm_stack_word || m_modrm_pc_word;

wire [2:0] m_par_idx = {1'b0, m_idx[1:0]};
wire [2:0] r_par_idx = {1'b0, r_idx[1:0]};
wire [15:0] m_reg_rd = !m_byte              ? gpr[m_idx]
                       : m_modrm_parent_word ? gpr[m_par_idx]
                                             : rb16(m_idx, gpr[m_par_idx]);
wire [15:0] m_rd = (m_kind == OK_REG)  ? m_reg_rd
                 : (m_kind == OK_SREG) ? sreg[m_idx[1:0]]
                 : (m_kind == OK_MEM)  ? opr : 16'd0;
wire [15:0] r_rd = (r_kind == OK_REG)  ? (r_byte ? rb16(r_idx, gpr[r_par_idx])
                                                 : gpr[r_idx])
                 : (r_kind == OK_SREG) ? sreg[r_idx[1:0]]
                 : (r_kind == OK_MEM)  ? opr : 16'd0;

wire [15:0] dirsz = (op8_eff ? (psw[FDIR] ? 16'hFFFF : 16'h0001)
                             : (psw[FDIR] ? 16'hFFFE : 16'h0002));

reg  [15:0] s1_val;
reg         s1_byte;
reg         s1_wbyte;
always @* begin
    s1_byte  = 1'b0;
    s1_wbyte = 1'b0;
    case (e_s1)
        5'd0,5'd1,5'd2,5'd3: s1_val = sreg[e_s1[1:0]];
        5'd4:  s1_val = pc;
        5'd6:  begin s1_val = opr;  s1_wbyte = opr_byte; end
        5'd7:  begin s1_val = {8'd0, q_byte}; s1_byte = 1'b1; s1_wbyte = 1'b1; end
        5'd8:  s1_val = dirsz;
        5'd9:  s1_val = 16'd0;
        5'd10: s1_val = {8'd0, pfxcnt_eff};
        5'd12: begin s1_val = tmpa; s1_wbyte = tmpa_byte; end
        5'd13: begin s1_val = tmpb; s1_wbyte = tmpb_byte; end
        5'd14: begin s1_val = tmpc; s1_wbyte = tmpc_byte; end
        5'd15: s1_val = flags_rd;
        5'd16: begin s1_val = {gpr[R_AW][7:0], gpr[R_AW][15:8]}; s1_wbyte = 1'b1; end
        5'd17: s1_val = count;
        5'd18: begin s1_val = r_rd; s1_wbyte = r_byte; end
        5'd19: begin s1_val = m_rd; s1_wbyte = m_byte; end
        5'd20: begin s1_val = sigma; s1_wbyte = sig_byte; end
        5'd21: s1_val = 16'hFFFF;
        5'd22: s1_val = {8'd0, opc_reg & 8'h38};
        5'd23: begin s1_val = {10'd0, r_constval}; s1_byte = 1'b1; end
        default: s1_val = (e_s1 >= 5'd24) ? gpr[e_s1[2:0]] : 16'd0;
    endcase
end

reg [15:0] s2_val;
reg        s2_wbyte;
always @* begin
    s2_wbyte = 1'b0;
    case (e_s2)
        4'd0: s2_val = 16'hFFFF;
        4'd4: begin s2_val = sigma; s2_wbyte = sig_byte; end
        4'd5: begin s2_val = {8'd0, q_byte}; s2_wbyte = 1'b1; end
        4'd6: s2_val = 16'd0;
        4'd7: begin s2_val = r_rd; s2_wbyte = r_byte; end
        default: s2_val = (e_s2 >= 4'd8) ? gpr[e_s2[2:0]] : 16'd0;
    endcase
end

wire [15:0] opr_live = (e_f && (rdq_n != 2'd0)) ? rdq0
                     : (e_f && eu_rd_done_n)    ? eu_rdata_n
                     : opr;
wire [15:0] s1_now = (e_s1 == 5'd7) ? {8'd0, q_byte}
                   : (e_s1 == 5'd6) ? opr_live
                   : s1_val;
wire [15:0] s2_now = (e_s2 == 4'd5) ? {8'd0, q_byte} : s2_val;

wire wr_ind1 = e_have1 && (e_d1 == 5'd5) &&
               !((e_s1 == 5'd20) && !sig_commits);
wire wr_ind2 = e_have2 && (e_d2 == 2'd2) &&
               !((e_s2 == 4'd4) && !sig_commits);
wire [15:0] ind_now = wr_ind2 ? s2_now : wr_ind1 ? s1_now : ind;

wire [15:0] pc_after_q = pc + {15'd0, row_q1} + {15'd0, row_q2};
wire wr_pc1 = e_have1 && (e_d1 == 5'd4) &&
              !((e_s1 == 5'd20) && !sig_commits);
wire wr_cs1 = e_have1 &&
              ((e_d1 == {3'd0, SR_CS}) ||
               ((e_d1 == 5'd18) && (r_kind == OK_SREG) &&
                (r_idx[1:0] == SR_CS)) ||
               ((e_d1 == 5'd19) && (m_kind == OK_SREG) &&
                (m_idx[1:0] == SR_CS))) &&
              !((e_s1 == 5'd20) && !sig_commits);
wire [15:0] pc_now = wr_pc1 ? s1_now : pc_after_q;
wire [15:0] cs_now = wr_cs1 ? s1_now : sreg[SR_CS];

wire        ghost_uses_ea = (ea_residue != tmpa);

wire [15:0] ghost_ea_off = (pe_opc_reg == 8'h8e) ? ea_residue
                                                  : {ea_residue[15:1], 1'b0};
wire [15:0] ghost_off = ghost_uses_ea ? ghost_ea_off : tmpa;
wire [13:0] ghost_next_pla = pla3_native(q_byte);
wire ghost_next_byte = q_ripe &&
                       (pla3_byte_only(ghost_next_pla) ||
                        (pla3_w_from_bit0(ghost_next_pla) && !q_byte[0]));

wire [15:0] ghost_bus_off = ghost_off & gpr[R_SP];
wire [15:0] acc_off  = ghost_read_stale_alu ? ghost_bus_off
                       : row_is_wb          ? wb_ea : ind_now;
wire [19:0] acc_phys_base = acc_io ? {4'd0, acc_off}
                                   : ({acc_segv, 4'd0} + {4'd0, acc_off});
wire [19:0] ghost_stack_phys = {acc_segv, 4'd0} + {4'd0, ind_now};

wire [19:0] acc_phys = (ghost_read_stale_alu && ghost_stack_phys[0] &&
                        eu_ghost_stack_first)
                     ? ghost_stack_phys : acc_phys_base;

wire [19:0] acc_phys2= (ghost_read_stale_alu && eu_ghost_idle &&
                        !ghost_uses_ea && ghost_stack_phys[0])
                      ? (({acc_segv, 4'd0} + {4'd0, ghost_off}) + 20'd1)
                      : ghost_read_stale_alu ? (acc_phys_base + 20'd1)
                     : acc_io ? {4'd0, acc_off + 16'd1}
                              : ({acc_segv, 4'd0} + {4'd0, acc_off + 16'd1});

wire       acc_split = ghost_read_stale_alu
                       ? (eu_word && ghost_stack_phys[0])
                       : (!acc_byte && acc_phys[0]);

wire [15:0] acc_off_nog  = row_is_wb ? wb_ea : ind_now;
wire [19:0] acc_phys_nog = acc_io ? {4'd0, acc_off_nog}
                                  : ({acc_segv, 4'd0} + {4'd0, acc_off_nog});
wire       acc_split_wr  = !acc_byte && acc_phys_nog[0];

wire [19:0] ghost_phys_sp   = {acc_segv, 4'd0} + {4'd0, gpr[R_SP]};
wire [19:0] ghost_phys_bare = {acc_segv, 4'd0} + {4'd0, ghost_off};

wire row_blocked = (st == S_ROW) && e_f && f_wait;

wire        rd_edge_take_raw  = eu_rd_edge && (st == S_ROW) && e_f &&
                                (e_s1 == 5'd6) && (e_d1 == 5'd15);
wire        rd_edge_psw_take  = rd_edge_take_raw && row_blocked;
wire [15:0] rd_edge_psw       = (eu_rd_edge_d & PSW_WRITABLE) | PSW_FORCED;

wire q_demand_row = row_need_q && !row_blocked;

wire vector_fixed = irq_sel_nmi || irq_sel_brk;

wire vector_tail = eu_fetch_tail && vector_fixed &&
                   (!q_ripe || (irq_sel_nmi && irq_fast_inta));
wire vector_overlap = (st == S_ROW) &&
                      ((eu_direct_fetch && !q_ripe) || vector_tail);
wire vector_early = !row_blocked && vector_overlap &&
                    (upc_page == 3'd7) && (upc_opc == 8'h10) &&
                    (upc_loc == 4'd0);
wire vector_first = (st == S_ROW) &&
                    (upc_page == 3'd7) && (upc_opc == 8'h10) &&
                    (upc_loc == 4'd2);
wire [15:0] vector_number = irq_sel_nmi ? 16'd2
                          : irq_sel_brk ? 16'd1 : opr;
wire [19:0] vector_phys_early = {2'b0, vector_number, 2'b0};

wire vector_reserved = vector_first && (eu_slot_busy || eu_access_active);

wire       row_slot_wait = row_bus && !row_posted &&
                           eu_slot_busy &&
                           !vector_reserved;
wire [2:0] row_wr_add    = (row_is_wr || row_is_wb)
                           ? (acc_split_wr ? 3'd2 : 3'd1) : 3'd0;
wire [2:0] wr_after      = {1'b0, wr_out} + row_wr_add;
wire       retire_ok_e   = (wr_after == 3'd0) ||
                           ((wr_after == 3'd1) && eu_wr_done_n);

wire pend_new   = pend_active || (row_is_wr || row_is_wb);
wire pend_after = pend_new && !(opr_fresh || row_wr_opr);

wire row_flush = (e_type == TY_CTL) && !e_farjmp && (e_ictl == I_FLUSH);
wire row_epop = (st == S_ROW) && (e_e || ext4s_early_e) &&
                !pend_after && !opc_valid &&
                !row_blocked && (rowq >= row_qn) && !row_pre_wait &&
                !row_slot_wait && retire_ok_e && !row_flush && !bnd_fire;

wire bnd_row  = (st == S_ROW) && (e_e || ext4s_early_e) &&
                !pend_after && !opc_valid &&
                !row_blocked && (rowq >= row_qn) && !row_pre_wait &&
                !row_slot_wait && retire_ok_e;

wire bnd_epop = ((st == S_EPOP) || (st == S_TAIL_POP) || tailw_go) &&
                retire_ok_n;

wire bnd_opc  = (st == S_OPC_POP) && bnd_armed;
wire at_bnd   = bnd_row || bnd_epop || bnd_opc;

wire irq_take = irq_any && !irq_shadow;

wire brk_seen = psw[FBRK] && brk_p[BRK_FLOOR-1];

wire brk_take = brk_arm && !irq_shadow;
wire bnd_take = irq_take || brk_take;
wire bnd_fire = at_bnd && bnd_take;

assign eu_bnd_take = bnd_fire;

assign eu_bnd_post = irq_take && !ie_p[3] && !irq_nmi_lvl;

wire tailw_go = (st == S_TAIL_W) && !opc_valid &&
                (opr_fresh || !(nr_wait || !opr_free_now));

wire q_demand = ((st == S_OPC_POP) && !bnd_fire) ||
                (st == S_EXT_POP) || (st == S_MODRM) ||
                (st == S_D16_LO) ||
                ((st == S_D8_B)   && (!ld_ripe_prev ? (chg == 2'd1) : 1'b1)) ||
                ((st == S_D16_HI) && (!ld_ripe_prev ? (chg == 2'd1) : 1'b1)) ||
                q_demand_row || row_epop ||

                (((st == S_EPOP) || (st == S_TAIL_POP) || tailw_go) &&
                 retire_ok_n && !bnd_fire);

assign q_pop   = q_demand;
assign q_first = (st == S_OPC_POP) ? pop_is_first
               : (st == S_EPOP) || (st == S_TAIL_POP) || tailw_go ||
                 row_epop ? 1'b1
               : 1'b0;

wire q_bnd_pop = q_first || (st == S_EXT_POP);

wire pend_go = pend_active && opr_fresh;
wire row_pre_pair = row_bus && pend_active;
wire row_pre_wait = row_pre_pair && !opr_fresh && (nr_wait || !opr_free_now);

wire row_acts_ok = (st == S_ROW) && !row_blocked && (rowq >= row_qn) &&
                   !row_pre_wait;

wire pr_active = (st == S_PRERD) && !row_posted;
wire row_post_now = row_acts_ok && row_bus && !row_posted &&
                    !vector_reserved;

wire inta_first = row_is_inta && (upc_page == 3'd7) &&
                  (upc_opc == 8'h02) && (upc_loc == 4'd0);

assign eu_post = (vector_early || pr_active || row_post_now) && !eu_slot_busy;
assign eu_post_hold = (vector_early && vector_tail && !eu_direct_fetch &&
                      !q_ripe && !eu_slot_busy) ||
                      (row_post_now && inta_first && eu_direct_fetch &&
                       !irq_fast_inta && !eu_slot_busy) ||
                      (row_post_now && (rdq_n == 2'd2) && !eu_slot_busy);
assign eu_halt_irq = irq_halt_entry;
assign eu_vector_post = eu_post && vector_first;

wire [13:0] ghost_t1_pla = pla3_native(q_byte);
wire ghost_space_io = ghost_read_stale_alu && q_ripe && !q_byte[1] &&
                      ((pla3_xop(ghost_t1_pla) == 4'hF) ||
                       (pla3_xop(ghost_t1_pla) == 4'h6));
assign eu_bs   = vector_early ? BS_MEMR
               : pr_active   ? BS_MEMR
               : row_is_inta ? BS_INTA
               : row_is_read ? ((acc_io || ghost_space_io) ? BS_IOR : BS_MEMR)
                             : (acc_io ? BS_IOW : BS_MEMW);
assign eu_addr = vector_early ? vector_phys_early
               : pr_active ? pr_phys : (row_is_inta ? 20'd0 : acc_phys);

assign eu_ghost_row  = ghost_read_stale_alu;
assign eu_ghost_acc  = eu_ghost_row && !vector_early && !pr_active;
assign eu_ghost_sp   = ghost_phys_sp;
assign eu_ghost_bare = ghost_phys_bare;
assign eu_addr2= vector_early ? (vector_phys_early + 20'd1)
               : pr_active ? pr_phys2 : acc_phys2;
assign eu_split= vector_early ? 1'b0
               : pr_active ? pr_split : (!row_is_inta && acc_split);
assign eu_seg  = vector_early ? 2'd2
               : pr_active ? seg_code(pr_seg)
               : row_is_inta ? 2'd2 : (acc_io ? 2'd2 : seg_code(acc_seg));
assign eu_seg2 = vector_early ? 2'd2
               : pr_active ? seg_code(pr_seg2)
               : row_is_inta ? 2'd2 : (acc_io ? 2'd2 : seg_code(acc_seg));
assign eu_word = vector_early ? 1'b1

               : pr_active ? (ghost_preread_tail ? 1'b1 : !pr_byte)

               : (ghost_read_stale_alu &&
                  (ghost_next_byte ||
                   (eu_ghost_full && (modrm_reg == 3'd0) &&
                    (m_idx == 3'd0)))) ? 1'b0
               : (row_is_inta ? 1'b1 : !acc_byte);

wire opr_wr_gate = e_have1 &&
                   ((e_d1 == 5'd6) ||
                    ((e_d1 == 5'd18) && (r_kind == OK_MEM)) ||
                    ((e_d1 == 5'd19) && (m_kind == OK_MEM))) &&
                   !((e_s1 == 5'd20) && !sig_commits);
wire row_wr_opr = (st == S_ROW) && !row_blocked && (rowq >= row_qn) &&
                  opr_wr_gate;
wire poste_wr_opr = poste && opr_wr_gate;

wire row_pre_deliver = (st == S_ROW) && !row_blocked && (rowq >= row_qn) &&
                       !row_pre_wait && row_pre_pair && !opr_fresh &&
                       !row_wr_opr;

wire ghost_edge_pair = ghost_rd_discard && eu_pair && !eu_rd_done_n;
wire [15:0] opr_now = ghost_edge_pair                    ? eu_rd_edge_d
                    : (row_wr_opr || poste_wr_opr)       ? s1_now
                    : (row_pre_deliver && (rdq_n != 2'd0)) ? rdq0
                    : (row_pre_deliver && eu_rd_done_n)    ? eu_rdata_n
                    : opr;
assign eu_pair  = ((st == S_ROW) && !row_blocked && (rowq >= row_qn) &&
                   !row_pre_wait &&
                   (pend_active || row_is_wr || row_is_wb) &&
                   (opr_fresh || row_wr_opr || row_pre_deliver))
               || (poste && pend_active && (opr_fresh || poste_wr_opr));
assign eu_pair2 = pend_active ? pend_split : acc_split;
assign eu_wdata = opr_now;

assign q_flush  = row_acts_ok && row_flush;

assign flush_pre = (st == S_ROW) && (upc_page == 3'd7) &&
                   (upc_opc == 8'h40) && (upc_loc == 4'd6) && !pend_active;
assign flush_rep = q_flush && (upc_page == 3'd7) && (upc_opc == 8'h40);
assign flush_stage = q_flush && pend_active;

assign flush_pend = q_flush && pend_active && (rdq_n != 2'd0) && !brk_take;

assign flush_nmi = irq_nmi_lvl;
assign flush_int_live = pin_int;

wire flush_cs_now = wr_cs1 && row_acts_ok;
assign flush_cs = flush_cs_now ? cs_now : sreg[SR_CS];
assign flush_cs_old = sreg[SR_CS];
assign flush_cs_we = flush_cs_now;
assign flush_ip = pc_now;

assign eu_susp  = (st == S_RESET) ||
                  (row_acts_ok && (e_type == TY_CTL) && !e_farjmp &&
                   (e_ictl == I_SUSP));
assign eu_resume = 1'b0;

wire qb_is_halt = pla3_one_byte_logic(pla3_lookup(
                      mode8080 ? PLA3_MODE_8080 : PLA3_MODE_NATIVE, q_byte)) &&
                  (pla3_xop(pla3_lookup(
                      mode8080 ? PLA3_MODE_8080 : PLA3_MODE_NATIVE, q_byte))
                   == PLA3_BL1_HALT);

assign eu_halt = q_pop && q_ripe && q_first && qb_is_halt && !mode8080 &&
                 !eu_halted && !brk_seen;

wire hlt_wake_int = (st == S_HALTED) && !irq_nmi_lvl && irq_pin_int;
assign eu_unhalt = hlt_wake_int || unhalt_pend;

wire hlt_wake_disp = (st == S_HALTED) && !irq_nmi_lvl && int_p[1];

wire hlt_wake_nmi_disp = eu_halted && (st != S_HALTED);
assign eu_unhalt_disp = hlt_wake_disp || unhalt_pend || hlt_wake_nmi_disp;

wire citf_status_pre = (st == S_ROW) && (upc_page == 3'd7) &&
                       ((upc_opc == 8'h10) || (upc_opc == 8'h18)) &&
                       (upc_loc == 4'd8) && opr_free_now;
assign psw_ie  = psw[FIE] && !citf_status_pre;
assign md8080  = mode8080;

assign dbg_regs = {psw, pc, sreg[3], sreg[2], sreg[1], sreg[0],
                   gpr[7], gpr[6], gpr[5], gpr[4],
                   gpr[3], gpr[2], gpr[1], gpr[0]};
assign dbg_first_pop = first_pop_seen;
assign dbg_pend = (rd_pending != 2'd0) || (rdq_n != 2'd0) || poste;

reg     [15:0] gpr_r [0:7];
reg     [15:0] sreg_r [0:3];
reg     [15:0] pc_r;
reg     [15:0] psw_r;
reg     [15:0] tmpa_r;
reg            tmpa_byte_r, tmpb_byte_r, tmpc_byte_r;
reg            opr_byte_r;
reg     [15:0] tmpb_r;
reg     [15:0] tmpc_r;
reg     [15:0] ea_residue_r;
reg     [15:0] ea_pair_rhs_r;
reg            ea_pair_valid_r;
reg     [15:0] opr_r;
reg     [15:0] ind_r;
reg     [15:0] count_r;
reg      [7:0] pfxcnt_r;
reg     [15:0] stat_r;
reg            sign_neg_r;
reg      [3:0] bit_n_r;
reg      [4:0] al_op_r;
reg      [1:0] al_tmp_r;
reg            al_eaconst_r;
reg     [15:0] al_eaval_r;
reg      [1:0] al_adjust_r;
reg      [1:0] al_adjtmp_r;
reg            al_bitarm_r;
reg      [3:0] al_bitn_r;
reg            al_spent_r;
reg      [2:0] upc_page_r;
reg      [7:0] upc_opc_r;
reg      [3:0] upc_loc_r;
reg            seg_override_r;
reg      [1:0] seg_ovr_r;
reg      [2:0] rep_kind_r;
reg            lock_pfx_r;
reg      [7:0] opc_reg_r;
reg            op8_r;
reg            imm8_r;
reg      [4:0] opc_base_r;
reg            opc_from_modrm_r;
reg      [2:0] modrm_reg_r;
reg      [3:0] xop_r;
reg      [1:0] rep_test_r;
reg            rep_pol_r;
reg            bus_word_r;
reg            opc8080_r;
reg            mode8080_r;
reg            intr_pending_r;
reg            eu_halted_r;
reg      [3:0] int_p_r;
reg      [4:0] nmi_p_r;
reg            nmi_latch_r;
reg      [3:0] ie_p_r;
reg            rep_chain_r;
reg            irq_shadow_r;
reg            bnd_armed_r;
reg            irq_sel_nmi_r;
reg            irq_sel_brk_r;
reg [BRK_FLOOR-1:0] brk_p_r;
reg            brk_arm_r;
reg            brk_smp_r;
reg            unhalt_pend_r;
reg            irq_fast_inta_r;
reg            irq_halt_entry_r;
reg      [1:0] m_kind_r;
reg      [1:0] r_kind_r;
reg      [1:0] wb_kind_r;
reg      [2:0] m_idx_r;
reg      [2:0] r_idx_r;
reg      [2:0] wb_idx_r;
reg     [15:0] m_ea_r;
reg     [15:0] r_ea_r;
reg     [15:0] wb_ea_r;
reg      [2:0] m_seg_r;
reg      [2:0] r_seg_r;
reg      [2:0] wb_seg_r;
reg            m_byte_r;
reg            r_byte_r;
reg            wb_byte_r;
reg            pend_active_r;
reg     [15:0] pend_off_r;
reg      [2:0] pend_seg_r;
reg            pend_byte_r;
reg            pend_io_r;
reg            opr_fresh_r;
reg            opr_loaded_r;
reg            rdp0_byte_r, rdp1_byte_r;
reg            rdq0_byte_r, rdq1_byte_r;
reg     [15:0] rdq0_r;
reg     [15:0] rdq1_r;
reg      [1:0] rdq_n_r;
reg      [1:0] rd_pending_r;
reg            ghost_rd_discard_r;
reg      [1:0] rd_done_cnt_r;
reg            rd_age0_r;
reg            iend_owed_r;
reg      [2:0] rst_ctr_r;
reg     [15:0] tsel_r;
reg      [7:0] pe_opc_reg_r;
reg            pe_opc8080_r;
reg            pe_op8_r;
reg      [7:0] pe_pfxcnt_r;
reg      [1:0] wr_out_r;
reg            opc_valid_r;
reg      [7:0] opc_byte_r;
reg            pop_is_first_r;
reg      [7:0] ld_b_r;
reg     [13:0] ld_pla_r;
reg            ld_ext_r;
reg      [2:0] ld_page_r;
reg            ld_hasrm_r;
reg      [7:0] ld_rm_r;
reg     [15:0] ld_disp_r;
reg      [7:0] ld_dlo_r;
reg            ld_grpd_r;
reg            ld_byte_r;
reg            ld_preread_r;
reg            ld_ripe_prev_r;
reg      [5:0] st_r;
reg      [1:0] chg_r;
reg            ending_r;
reg      [1:0] rowq_r;
reg            row_posted_r;
reg            row_paired_r;
reg     [15:0] rloop_n_r;
reg            suppress_commit_r;
reg            first_pop_seen_r;
reg      [7:0] rowb0_r;
reg      [7:0] rowb1_r;
reg            poste_r;
reg      [2:0] poll_pipe_r;

integer rsi;
always @* begin

    for (rsi = 0; rsi < 8; rsi = rsi + 1) gpr_r[rsi] = gpr[rsi];
    for (rsi = 0; rsi < 4; rsi = rsi + 1) sreg_r[rsi] = sreg[rsi];
    pc_r = pc;
    psw_r = psw;
    tmpa_r = tmpa;
    tmpa_byte_r = tmpa_byte;
    tmpb_byte_r = tmpb_byte;
    tmpc_byte_r = tmpc_byte;
    opr_byte_r = opr_byte;
    tmpb_r = tmpb;
    tmpc_r = tmpc;
    ea_residue_r = ea_residue;
    ea_pair_rhs_r = ea_pair_rhs;
    ea_pair_valid_r = ea_pair_valid;
    opr_r = opr;
    ind_r = ind;
    count_r = count;
    pfxcnt_r = pfxcnt;
    stat_r = stat;
    sign_neg_r = sign_neg;
    bit_n_r = bit_n;
    al_op_r = al_op;
    al_tmp_r = al_tmp;
    al_eaconst_r = al_eaconst;
    al_eaval_r = al_eaval;
    al_adjust_r = al_adjust;
    al_adjtmp_r = al_adjtmp;
    al_bitarm_r = al_bitarm;
    al_bitn_r = al_bitn;
    al_spent_r = al_spent;
    upc_page_r = upc_page;
    upc_opc_r = upc_opc;
    upc_loc_r = upc_loc;
    seg_override_r = seg_override;
    seg_ovr_r = seg_ovr;
    rep_kind_r = rep_kind;
    lock_pfx_r = lock_pfx;
    opc_reg_r = opc_reg;
    op8_r = op8;
    imm8_r = imm8;
    opc_base_r = opc_base;
    opc_from_modrm_r = opc_from_modrm;
    modrm_reg_r = modrm_reg;
    xop_r = xop;
    rep_test_r = rep_test;
    rep_pol_r = rep_pol;
    bus_word_r = bus_word;
    opc8080_r = opc8080;
    mode8080_r = mode8080;
    intr_pending_r = intr_pending;
    eu_halted_r = eu_halted;
    int_p_r = int_p;
    nmi_p_r = nmi_p;
    nmi_latch_r = nmi_latch;
    ie_p_r = ie_p;
    rep_chain_r = rep_chain;
    irq_shadow_r = irq_shadow;
    bnd_armed_r = bnd_armed;
    irq_sel_nmi_r = irq_sel_nmi;
    irq_sel_brk_r = irq_sel_brk;
    brk_p_r = brk_p;
    brk_arm_r = brk_arm;
    brk_smp_r = brk_smp;
    unhalt_pend_r = unhalt_pend;
    irq_fast_inta_r = irq_fast_inta;
    irq_halt_entry_r = irq_halt_entry;
    m_kind_r = m_kind;
    r_kind_r = r_kind;
    wb_kind_r = wb_kind;
    m_idx_r = m_idx;
    r_idx_r = r_idx;
    wb_idx_r = wb_idx;
    m_ea_r = m_ea;
    r_ea_r = r_ea;
    wb_ea_r = wb_ea;
    m_seg_r = m_seg;
    r_seg_r = r_seg;
    wb_seg_r = wb_seg;
    m_byte_r = m_byte;
    r_byte_r = r_byte;
    wb_byte_r = wb_byte;
    pend_active_r = pend_active;
    pend_off_r = pend_off;
    pend_seg_r = pend_seg;
    pend_byte_r = pend_byte;
    pend_io_r = pend_io;
    opr_fresh_r = opr_fresh;
    opr_loaded_r = opr_loaded;
    rdp0_byte_r = rdp0_byte;
    rdp1_byte_r = rdp1_byte;
    rdq0_byte_r = rdq0_byte;
    rdq1_byte_r = rdq1_byte;
    rdq0_r = rdq0;
    rdq1_r = rdq1;
    rdq_n_r = rdq_n;
    rd_pending_r = rd_pending;
    ghost_rd_discard_r = ghost_rd_discard;
    rd_done_cnt_r = rd_done_cnt;
    rd_age0_r = rd_age0;
    iend_owed_r = iend_owed;
    rst_ctr_r = rst_ctr;
    tsel_r = tsel;
    pe_opc_reg_r = pe_opc_reg;
    pe_opc8080_r = pe_opc8080;
    pe_op8_r = pe_op8;
    pe_pfxcnt_r = pe_pfxcnt;
    wr_out_r = wr_out;
    opc_valid_r = opc_valid;
    opc_byte_r = opc_byte;
    pop_is_first_r = pop_is_first;
    ld_b_r = ld_b;
    ld_pla_r = ld_pla;
    ld_ext_r = ld_ext;
    ld_page_r = ld_page;
    ld_hasrm_r = ld_hasrm;
    ld_rm_r = ld_rm;
    ld_disp_r = ld_disp;
    ld_dlo_r = ld_dlo;
    ld_grpd_r = ld_grpd;
    ld_byte_r = ld_byte;
    ld_preread_r = ld_preread;
    ld_ripe_prev_r = ld_ripe_prev;
    st_r = st;
    chg_r = chg;
    ending_r = ending;
    rowq_r = rowq;
    row_posted_r = row_posted;
    row_paired_r = row_paired;
    rloop_n_r = rloop_n;
    suppress_commit_r = suppress_commit;
    first_pop_seen_r = first_pop_seen;
    rowb0_r = rowb0;
    rowb1_r = rowb1;
    poste_r = poste;
    poll_pipe_r = poll_pipe;

        for (rsi = 0; rsi < 8; rsi = rsi + 1) gpr_r[rsi] = 16'd0;
        for (rsi = 0; rsi < 4; rsi = rsi + 1) sreg_r[rsi] = 16'd0;
        pc_r = 16'd0; psw_r = PSW_FORCED;
        tmpa_r = 16'd0; tmpb_r = 16'd0; tmpc_r = 16'd0;
        tmpa_byte_r = 1'b0; tmpb_byte_r = 1'b0; tmpc_byte_r = 1'b0;
        opr_byte_r = 1'b0;
        ea_residue_r = 16'd0;
        ea_pair_rhs_r = 16'd0; ea_pair_valid_r = 1'b0;
        opr_r = 16'd0; ind_r = 16'd0; count_r = 16'd0; pfxcnt_r = 8'd0;
        stat_r = 16'd0; sign_neg_r = 1'b0; bit_n_r = 4'd0;
        al_op_r = A_ADD; al_tmp_r = 2'd0;
        al_eaconst_r = 1'b0; al_eaval_r = 16'd0;
        al_adjust_r = 2'd0; al_adjtmp_r = 2'd0; al_bitarm_r = 1'b0; al_bitn_r = 4'd0;
        al_spent_r = 1'b0;
        upc_page_r = 3'd0; upc_opc_r = 8'd0; upc_loc_r = 4'd0;
        seg_override_r = 1'b0; seg_ovr_r = 2'd3; rep_kind_r = REP_NONE;
        lock_pfx_r = 1'b0; opc_reg_r = 8'd0; op8_r = 1'b0; imm8_r = 1'b0;
        opc_base_r = 5'd0; opc_from_modrm_r = 1'b0; modrm_reg_r = 3'd0; xop_r = 4'd0;
        rep_test_r = TEST_NONE; rep_pol_r = 1'b0; bus_word_r = 1'b0;
        opc8080_r = 1'b0; mode8080_r = 1'b0; intr_pending_r = 1'b0; eu_halted_r = 1'b0;
        rep_chain_r = 1'b0;
        m_kind_r = OK_NONE; m_idx_r = 3'd0; m_ea_r = 16'd0; m_seg_r = 3'd3; m_byte_r = 1'b0;
        r_kind_r = OK_NONE; r_idx_r = 3'd0; r_ea_r = 16'd0; r_seg_r = 3'd3; r_byte_r = 1'b0;
        wb_kind_r = OK_NONE; wb_idx_r = 3'd0; wb_ea_r = 16'd0; wb_seg_r = 3'd3;
        wb_byte_r = 1'b0;
        pend_active_r = 1'b0; pend_off_r = 16'd0; pend_seg_r = 3'd3;
        pend_byte_r = 1'b0; pend_io_r = 1'b0; opr_fresh_r = 1'b0;
        opr_loaded_r = 1'b0;
        rdq0_r = 16'd0; rdq1_r = 16'd0; rdq_n_r = 2'd0;
        rdp0_byte_r = 1'b0; rdp1_byte_r = 1'b0;
        rdq0_byte_r = 1'b0; rdq1_byte_r = 1'b0;
        rd_pending_r = 2'd0; ghost_rd_discard_r = 1'b0;
        rd_done_cnt_r = 2'd0; rd_age0_r = 1'b0;
        iend_owed_r = 1'b0; pe_opc_reg_r = 8'd0; pe_opc8080_r = 1'b0; pe_op8_r = 1'b0;
        pe_pfxcnt_r = 8'd0;
        wr_out_r = 2'd0;
        opc_valid_r = 1'b0; opc_byte_r = 8'd0; pop_is_first_r = 1'b1;
        ld_b_r = 8'd0; ld_pla_r = 14'd0; ld_ext_r = 1'b0; ld_page_r = 3'd0;
        ld_hasrm_r = 1'b0; ld_rm_r = 8'd0; ld_disp_r = 16'd0; ld_dlo_r = 8'd0;
        ld_grpd_r = 1'b0; ld_byte_r = 1'b0; ld_preread_r = 1'b0; ld_ripe_prev_r = 1'b0;
        st_r = S_OPC_POP; chg_r = 2'd0; ending_r = 1'b0; poste_r = 1'b0;
        rowq_r = 2'd0; row_posted_r = 1'b0; row_paired_r = 1'b0; rloop_n_r = 16'd0;
        suppress_commit_r = 1'b0; first_pop_seen_r = 1'b0;
        rowb0_r = 8'd0; rowb1_r = 8'd0; poste_r = 1'b0;

        poll_pipe_r = {3{pin_poll_n}};
        int_p_r = {4{pin_int}}; nmi_p_r = {5{pin_nmi}}; ie_p_r = 4'd0;
        rep_chained = 1'b0;
        nmi_latch_r = 1'b0; irq_shadow_r = 1'b0; bnd_armed_r = 1'b0;
        irq_sel_nmi_r = 1'b0; unhalt_pend_r = 1'b0;
        irq_fast_inta_r = 1'b0;
        irq_halt_entry_r = 1'b0;
        irq_sel_brk_r = 1'b0; brk_p_r = '0; brk_arm_r = 1'b0;
        brk_smp_r = 1'b0;
        if (bkd_load) begin
            gpr_r[0] = bkd_regs[  0 +: 16];  gpr_r[1] = bkd_regs[ 16 +: 16];
            gpr_r[2] = bkd_regs[ 32 +: 16];  gpr_r[3] = bkd_regs[ 48 +: 16];
            gpr_r[4] = bkd_regs[ 64 +: 16];  gpr_r[5] = bkd_regs[ 80 +: 16];
            gpr_r[6] = bkd_regs[ 96 +: 16];  gpr_r[7] = bkd_regs[112 +: 16];
            sreg_r[0] = bkd_regs[128 +: 16]; sreg_r[1] = bkd_regs[144 +: 16];
            sreg_r[2] = bkd_regs[160 +: 16]; sreg_r[3] = bkd_regs[176 +: 16];
            pc_r = bkd_regs[192 +: 16];
            psw_r = (bkd_regs[208 +: 16] & PSW_WRITABLE) | PSW_FORCED;
        end else begin

            upc_page_r = 3'd7;
            upc_opc_r  = 8'h03;
            upc_loc_r  = 4'd0;
            rst_ctr_r  = 3'd0;
            st_r = S_RESET;
        end
        ie_p_r = {4{psw_r[FIE]}};
end

reg     [15:0] gpr_n [0:7];
reg     [15:0] sreg_n [0:3];
reg     [15:0] pc_n;
reg     [15:0] psw_n;
reg     [15:0] tmpa_n;
reg            tmpa_byte_n, tmpb_byte_n, tmpc_byte_n;
reg            opr_byte_n;
reg     [15:0] tmpb_n;
reg     [15:0] tmpc_n;
reg     [15:0] ea_residue_n;
reg     [15:0] ea_pair_rhs_n;
reg            ea_pair_valid_n;
reg     [15:0] opr_n;
reg     [15:0] ind_n;
reg     [15:0] count_n;
reg      [7:0] pfxcnt_n;
reg     [15:0] stat_n;
reg            sign_neg_n;
reg      [3:0] bit_n_n;
reg      [4:0] al_op_n;
reg      [1:0] al_tmp_n;
reg            al_eaconst_n;
reg     [15:0] al_eaval_n;
reg      [1:0] al_adjust_n;
reg      [1:0] al_adjtmp_n;
reg            al_bitarm_n;
reg      [3:0] al_bitn_n;
reg            al_spent_n;
reg      [2:0] upc_page_n;
reg      [7:0] upc_opc_n;
reg      [3:0] upc_loc_n;
reg            seg_override_n;
reg      [1:0] seg_ovr_n;
reg      [2:0] rep_kind_n;
reg            lock_pfx_n;
reg      [7:0] opc_reg_n;
reg            op8_n;
reg            imm8_n;
reg      [4:0] opc_base_n;
reg            opc_from_modrm_n;
reg      [2:0] modrm_reg_n;
reg      [3:0] xop_n;
reg      [1:0] rep_test_n;
reg            rep_pol_n;
reg            bus_word_n;
reg            opc8080_n;
reg            mode8080_n;
reg            intr_pending_n;
reg            eu_halted_n;
reg      [3:0] int_p_n;
reg      [4:0] nmi_p_n;
reg            nmi_latch_n;
reg      [3:0] ie_p_n;
reg            rep_chain_n;
reg            irq_shadow_n;
reg            bnd_armed_n;
reg            irq_sel_nmi_n;
reg            irq_sel_brk_n;
reg [BRK_FLOOR-1:0] brk_p_n;
reg            brk_arm_n;
reg            brk_smp_n;
reg            unhalt_pend_n;
reg            irq_fast_inta_n;
reg            irq_halt_entry_n;
reg      [1:0] m_kind_n;
reg      [1:0] r_kind_n;
reg      [1:0] wb_kind_n;
reg      [2:0] m_idx_n;
reg      [2:0] r_idx_n;
reg      [2:0] wb_idx_n;
reg     [15:0] m_ea_n;
reg     [15:0] r_ea_n;
reg     [15:0] wb_ea_n;
reg      [2:0] m_seg_n;
reg      [2:0] r_seg_n;
reg      [2:0] wb_seg_n;
reg            m_byte_n;
reg            r_byte_n;
reg            wb_byte_n;
reg            pend_active_n;
reg     [15:0] pend_off_n;
reg      [2:0] pend_seg_n;
reg            pend_byte_n;
reg            pend_io_n;
reg            opr_fresh_n;
reg            opr_loaded_n;
reg            rdp0_byte_n, rdp1_byte_n;
reg            rdq0_byte_n, rdq1_byte_n;
reg     [15:0] rdq0_n;
reg     [15:0] rdq1_n;
reg      [1:0] rdq_n_n;
reg      [1:0] rd_pending_n;
reg            ghost_rd_discard_n;
reg      [1:0] rd_done_cnt_n;
reg            rd_age0_n;
reg            iend_owed_n;
reg      [2:0] rst_ctr_n;
reg     [15:0] tsel_n;
reg      [7:0] pe_opc_reg_n;
reg            pe_opc8080_n;
reg            pe_op8_n;
reg      [7:0] pe_pfxcnt_n;
reg      [1:0] wr_out_n;
reg            opc_valid_n;
reg      [7:0] opc_byte_n;
reg            pop_is_first_n;
reg      [7:0] ld_b_n;
reg     [13:0] ld_pla_n;
reg            ld_ext_n;
reg      [2:0] ld_page_n;
reg            ld_hasrm_n;
reg      [7:0] ld_rm_n;
reg     [15:0] ld_disp_n;
reg      [7:0] ld_dlo_n;
reg            ld_grpd_n;
reg            ld_byte_n;
reg            ld_preread_n;
reg            ld_ripe_prev_n;
reg      [5:0] st_n;
reg      [1:0] chg_n;
reg            ending_n;
reg      [1:0] rowq_n;
reg            row_posted_n;
reg            row_paired_n;
reg     [15:0] rloop_n_n;
reg            suppress_commit_n;
reg            first_pop_seen_n;
reg      [7:0] rowb0_n;
reg      [7:0] rowb1_n;
reg            poste_n;
reg      [2:0] poll_pipe_n;

`ifndef SYNTHESIS
reg eutrace = 0;
initial if ($test$plusargs("eutrace")) eutrace = 1;

reg brktrace = 0;
initial if ($test$plusargs("brktrace")) brktrace = 1;

int unsigned ce_clk = 0;

reg [15:0] trc_1bl_pre, trc_1bl_post; reg trc_1bl_hit;
reg [15:0] trc_pe_pre, trc_pe_post; reg trc_pe_hit; reg [11:0] trc_pe_upc;

reg trc_1bld_hit, trc_1bld_ripe, trc_1bld_seen, trc_1bld_arm, trc_1bld_smp;
reg trc_1bld_shd;
reg chain_report = 0;
initial if ($test$plusargs("chaindepth")) chain_report = 1;
reg [3:0] chain_hi = 4'd0;
reg [3:0] chain_used;

reg      [5:0] trc_st;
reg      [2:0] trc_upc_page;
reg      [7:0] trc_upc_opc;
reg      [3:0] trc_upc_loc;
reg      [1:0] trc_wr_out;
reg     [15:0] trc_pc;
reg     [15:0] trc_ind;
reg     [15:0] trc_opr;
reg            trc_opr_fresh;
reg            trc_pend_active;
reg            trc_poste;
reg      [1:0] trc_rdq_n;
reg      [1:0] trc_rd_done_cnt;
reg     [15:0] trc_tmpa;
reg     [15:0] trc_tmpb;
reg     [15:0] trc_tmpc;
reg [5:0] chain_first;
`ifdef CHAIN_PROBE
reg cp_seen [0:1023];
integer cpi;
initial for (cpi = 0; cpi < 1024; cpi = cpi + 1) cp_seen[cpi] = 1'b0;
`endif
`endif

localparam bit [3:0] CHAIN_MAX = 4'd7;

integer i;
integer ci;
reg        stop;
reg  [3:0] chain;
reg [15:0] v1, v2;
reg        bsw;
reg        wb1, wb2;
reg        rdh_byte;
reg [13:0] pv;
reg  [3:0] nloc;
reg        carry, taken, bubble, retire_now;
reg        rep_chained;
reg        ie_now;
reg        brk_now;
reg [15:0] ea;
reg  [2:0] rseg;
reg  [1:0] rmmod;
reg  [2:0] rmreg, rmrm;
reg  [1:0] tk;
reg  [2:0] ti, ts;
reg [15:0] te;
reg        tb;

`define SETPSW(v) begin psw_n = ((v) & PSW_WRITABLE) | PSW_FORCED; end

task automatic commit_flags(input [15:0] mask, input [15:0] fl);
    begin
        psw_n = ((psw_n & ~mask) | (fl & mask));
        psw_n = (psw_n & PSW_WRITABLE) | PSW_FORCED;
    end
endtask

always @* begin

    for (i = 0; i < 8; i = i + 1) gpr_n[i] = gpr[i];
    for (i = 0; i < 4; i = i + 1) sreg_n[i] = sreg[i];
    pc_n = pc;
    psw_n = psw;
    tmpa_n = tmpa;
    tmpa_byte_n = tmpa_byte;
    tmpb_byte_n = tmpb_byte;
    tmpc_byte_n = tmpc_byte;
    opr_byte_n = opr_byte;
    tmpb_n = tmpb;
    tmpc_n = tmpc;
    ea_residue_n = ea_residue;
    ea_pair_rhs_n = ea_pair_rhs;
    ea_pair_valid_n = ea_pair_valid;
    opr_n = opr;
    ind_n = ind;
    count_n = count;
    pfxcnt_n = pfxcnt;
    stat_n = stat;
    sign_neg_n = sign_neg;
    bit_n_n = bit_n;
    al_op_n = al_op;
    al_tmp_n = al_tmp;
    al_eaconst_n = al_eaconst;
    al_eaval_n = al_eaval;
    al_adjust_n = al_adjust;
    al_adjtmp_n = al_adjtmp;
    al_bitarm_n = al_bitarm;
    al_bitn_n = al_bitn;
    al_spent_n = al_spent;
    upc_page_n = upc_page;
    upc_opc_n = upc_opc;
    upc_loc_n = upc_loc;
    seg_override_n = seg_override;
    seg_ovr_n = seg_ovr;
    rep_kind_n = rep_kind;
    lock_pfx_n = lock_pfx;
    opc_reg_n = opc_reg;
    op8_n = op8;
    imm8_n = imm8;
    opc_base_n = opc_base;
    opc_from_modrm_n = opc_from_modrm;
    modrm_reg_n = modrm_reg;
    xop_n = xop;
    rep_test_n = rep_test;
    rep_pol_n = rep_pol;
    bus_word_n = bus_word;
    opc8080_n = opc8080;
    mode8080_n = mode8080;
    intr_pending_n = intr_pending;
    eu_halted_n = eu_halted;
    int_p_n = int_p;
    nmi_p_n = nmi_p;
    nmi_latch_n = nmi_latch;
    ie_p_n = ie_p;
    rep_chain_n = rep_chain;
    irq_shadow_n = irq_shadow;
    bnd_armed_n = bnd_armed;
    irq_sel_nmi_n = irq_sel_nmi;
    irq_sel_brk_n = irq_sel_brk;
    brk_p_n = brk_p;
    brk_arm_n = brk_arm;
    brk_smp_n = brk_smp;
    unhalt_pend_n = unhalt_pend;
    irq_fast_inta_n = irq_fast_inta;
    irq_halt_entry_n = irq_halt_entry;
    m_kind_n = m_kind;
    r_kind_n = r_kind;
    wb_kind_n = wb_kind;
    m_idx_n = m_idx;
    r_idx_n = r_idx;
    wb_idx_n = wb_idx;
    m_ea_n = m_ea;
    r_ea_n = r_ea;
    wb_ea_n = wb_ea;
    m_seg_n = m_seg;
    r_seg_n = r_seg;
    wb_seg_n = wb_seg;
    m_byte_n = m_byte;
    r_byte_n = r_byte;
    wb_byte_n = wb_byte;
    pend_active_n = pend_active;
    pend_off_n = pend_off;
    pend_seg_n = pend_seg;
    pend_byte_n = pend_byte;
    pend_io_n = pend_io;
    opr_fresh_n = opr_fresh;
    opr_loaded_n = opr_loaded;
    rdp0_byte_n = rdp0_byte;
    rdp1_byte_n = rdp1_byte;
    rdq0_byte_n = rdq0_byte;
    rdq1_byte_n = rdq1_byte;
    rdq0_n = rdq0;
    rdq1_n = rdq1;
    rdq_n_n = rdq_n;
    rd_pending_n = rd_pending;
    ghost_rd_discard_n = ghost_rd_discard;
    rd_done_cnt_n = rd_done_cnt;
    rd_age0_n = rd_age0;
    iend_owed_n = iend_owed;
    rst_ctr_n = rst_ctr;
    tsel_n = tsel;
    pe_opc_reg_n = pe_opc_reg;
    pe_opc8080_n = pe_opc8080;
    pe_op8_n = pe_op8;
    pe_pfxcnt_n = pe_pfxcnt;
    wr_out_n = wr_out;
    opc_valid_n = opc_valid;
    opc_byte_n = opc_byte;
    pop_is_first_n = pop_is_first;
    ld_b_n = ld_b;
    ld_pla_n = ld_pla;
    ld_ext_n = ld_ext;
    ld_page_n = ld_page;
    ld_hasrm_n = ld_hasrm;
    ld_rm_n = ld_rm;
    ld_disp_n = ld_disp;
    ld_dlo_n = ld_dlo;
    ld_grpd_n = ld_grpd;
    ld_byte_n = ld_byte;
    ld_preread_n = ld_preread;
    ld_ripe_prev_n = ld_ripe_prev;
    st_n = st;
    chg_n = chg;
    ending_n = ending;
    rowq_n = rowq;
    row_posted_n = row_posted;
    row_paired_n = row_paired;
    rloop_n_n = rloop_n;
    suppress_commit_n = suppress_commit;
    first_pop_seen_n = first_pop_seen;
    rowb0_n = rowb0;
    rowb1_n = rowb1;
    poste_n = poste;
    poll_pipe_n = poll_pipe;

    stop = 1'b0;
    chain = 4'd0;
    v1 = 16'd0;
    v2 = 16'd0;
    bsw = 1'b0;
    wb1 = 1'b0;
    wb2 = 1'b0;
    rdh_byte = 1'b0;
    pv = 14'd0;
    nloc = 4'd0;
    carry = 1'b0;
    taken = 1'b0;
    bubble = 1'b0;
    retire_now = 1'b0;
    rep_chained = 1'b0;
    ie_now = 1'b0;
    brk_now = 1'b0;
    ea = 16'd0;
    rseg = 3'd0;
    rmmod = 2'd0;
    rmreg = 3'd0;
    rmrm = 3'd0;
    tk = 2'd0;
    ti = 3'd0;
    ts = 3'd0;
    te = 16'd0;
    tb = 1'b0;

    if (ss_we) begin
        `include "v30u_eu_ss_write.svh"
    end else begin

`ifndef SYNTHESIS
        trc_1bl_hit = 1'b0; trc_pe_hit = 1'b0; trc_1bld_hit = 1'b0;
`endif
        poll_pipe_n = {poll_pipe_n[1:0], pin_poll_n};

        ie_now = psw_n[FIE];
        brk_now = psw_n[FBRK];

        if (ie_now && !ie_p_n[0] && int_p[0])
            intr_pending_n = 1'b1;

        if (brk_smp) brk_arm_n = brk_seen;

        brk_smp_n = (q_pop && q_ripe && q_bnd_pop) || (bnd_fire && irq_take);
        unhalt_pend_n = 1'b0;
        if (bnd_fire)
            irq_fast_inta_n = bnd_opc || eu_bnd_post;
        if (eu_post && inta_first) begin
            irq_fast_inta_n = 1'b0;
            irq_halt_entry_n = 1'b0;
        end
        if (vector_first) irq_fast_inta_n = 1'b0;
        rd_age0_n = 1'b0;
        if (eu_rd_done_n) begin

            rdh_byte = rdp0_byte_n;
            rdp0_byte_n = rdp1_byte_n;
            if (rd_pending_n != 2'd0) rd_pending_n = rd_pending_n - 2'd1;

            if (ghost_rd_discard_n && (rd_pending_n == 2'd0)) begin
                ghost_rd_discard_n = 1'b0;
            end else begin
                if (rd_done_cnt_n == 2'd0) rd_age0_n = 1'b1;
                if (rd_done_cnt_n != 2'd3) rd_done_cnt_n = rd_done_cnt_n + 2'd1;
                if (rdq_n_n == 2'd0) begin
                    rdq0_n = eu_rdata_n; rdq0_byte_n = rdh_byte;
                end else begin
                    rdq1_n = eu_rdata_n; rdq1_byte_n = rdh_byte;
                end
                if (rdq_n_n != 2'd2) rdq_n_n = rdq_n_n + 2'd1;
            end
        end
        if (eu_wr_done_n && (wr_out_n != 2'd0)) wr_out_n = wr_out_n - 2'd1;
        if (q_pop && q_ripe && q_first && !first_pop_seen_n) first_pop_seen_n = 1'b1;

        if (poste_n) begin
            poste_n = 1'b0;
`ifndef SYNTHESIS
            trc_pe_hit = 1'b1; trc_pe_pre = psw_n;
            trc_pe_upc = {upc_opc_n, upc_loc_n};
`endif
            `include "v30u_eu_poste.svh"
            if (tmpa_n != tmpa) ea_residue_n = tmpa_n;
            if (tmpb_n != tmpb) ea_pair_valid_n = 1'b0;
`ifndef SYNTHESIS
            trc_pe_post = psw_n;
`endif
        end

        if (iend_owed_n) begin
            iend_owed_n = 1'b0;
            `include "v30u_eu_iend_late.svh"
        end

`ifndef SYNTHESIS

        trc_st = st_n;
        trc_upc_page = upc_page_n;
        trc_upc_opc = upc_opc_n;
        trc_upc_loc = upc_loc_n;
        trc_wr_out = wr_out_n;
        trc_pc = pc_n;
        trc_ind = ind_n;
        trc_opr = opr_n;
        trc_opr_fresh = opr_fresh_n;
        trc_pend_active = pend_active_n;
        trc_poste = poste_n;
        trc_rdq_n = rdq_n_n;
        trc_rd_done_cnt = rd_done_cnt_n;
        trc_tmpa = tmpa_n;
        trc_tmpb = tmpb_n;
        trc_tmpc = tmpc_n;
`endif
        stop = 1'b0;
`ifndef SYNTHESIS
        chain_used = 4'd0;
        chain_first = st_n;
`endif
        for (chain = 0; chain < CHAIN_MAX; chain = chain + 4'd1) begin
            if (!stop) begin
`ifndef SYNTHESIS
                chain_used = chain + 4'd1;
`ifdef CHAIN_PROBE
                if (!cp_seen[{chain, st_n}]) begin : cprobe
                    integer fd;
                    cp_seen[{chain, st_n}] = 1'b1;
                    fd = $fopen(`CHAIN_PROBE, "a");
                    $fwrite(fd, "POS %0d ST %0d\n", chain, st_n);
                    $fclose(fd);
                end
`endif
`endif

                if ((chain != 4'd0) && !st_zero_ok(st_n)) stop = 1'b1;
                else begin
                    `include "v30u_eu_step.svh"
                end
            end
        end

        int_p_n = {int_p_n[2:0], pin_int};
        nmi_p_n = {nmi_p_n[3:0], pin_nmi};
        ie_p_n  = {ie_p_n[2:0], ie_now};

        brk_p_n = BRK_FLOOR'({brk_p_n, brk_now});

        if (nmi_p_n[3] && !nmi_p_n[4]) nmi_latch_n = 1'b1;
    end
end

assign dec_addr_next = (srst && !ss_we)
        ? {upc_page_r, upc_opc_r, upc_loc_r[3:2]}
        : {upc_page_n, upc_opc_n, upc_loc_n[3:2]};

always @(posedge clk) begin

    if (ss_we || srst || ce) begin
        for (ci = 0; ci < 8; ci = ci + 1)
            gpr[ci] <= (srst && !ss_we) ? gpr_r[ci] : gpr_n[ci];
        for (ci = 0; ci < 4; ci = ci + 1)
            sreg[ci] <= (srst && !ss_we) ? sreg_r[ci] : sreg_n[ci];
        pc <= (srst && !ss_we) ? pc_r : pc_n;

        psw <= (srst && !ss_we)             ? psw_r
             : (rd_edge_psw_take && !ss_we) ? rd_edge_psw
             :                                psw_n;
        tmpa <= (srst && !ss_we) ? tmpa_r : tmpa_n;
        tmpa_byte <= (srst && !ss_we) ? tmpa_byte_r : tmpa_byte_n;
        tmpb_byte <= (srst && !ss_we) ? tmpb_byte_r : tmpb_byte_n;
        tmpc_byte <= (srst && !ss_we) ? tmpc_byte_r : tmpc_byte_n;
        opr_byte  <= (srst && !ss_we) ? opr_byte_r  : opr_byte_n;
        tmpb <= (srst && !ss_we) ? tmpb_r : tmpb_n;
        tmpc <= (srst && !ss_we) ? tmpc_r : tmpc_n;
        ea_residue <= (srst && !ss_we) ? ea_residue_r : ea_residue_n;
        ea_pair_rhs <= (srst && !ss_we) ? ea_pair_rhs_r : ea_pair_rhs_n;
        ea_pair_valid <= (srst && !ss_we) ? ea_pair_valid_r : ea_pair_valid_n;
        opr <= (srst && !ss_we) ? opr_r : opr_n;
        ind <= (srst && !ss_we) ? ind_r : ind_n;
        count <= (srst && !ss_we) ? count_r : count_n;
        pfxcnt <= (srst && !ss_we) ? pfxcnt_r : pfxcnt_n;
        stat <= (srst && !ss_we) ? stat_r : stat_n;
        sign_neg <= (srst && !ss_we) ? sign_neg_r : sign_neg_n;
        bit_n <= (srst && !ss_we) ? bit_n_r : bit_n_n;
        al_op <= (srst && !ss_we) ? al_op_r : al_op_n;
        al_tmp <= (srst && !ss_we) ? al_tmp_r : al_tmp_n;
        al_eaconst <= (srst && !ss_we) ? al_eaconst_r : al_eaconst_n;
        al_eaval <= (srst && !ss_we) ? al_eaval_r : al_eaval_n;
        al_adjust <= (srst && !ss_we) ? al_adjust_r : al_adjust_n;
        al_adjtmp <= (srst && !ss_we) ? al_adjtmp_r : al_adjtmp_n;
        al_bitarm <= (srst && !ss_we) ? al_bitarm_r : al_bitarm_n;
        al_bitn <= (srst && !ss_we) ? al_bitn_r : al_bitn_n;
        al_spent <= (srst && !ss_we) ? al_spent_r : al_spent_n;
        upc_page <= (srst && !ss_we) ? upc_page_r : upc_page_n;
        upc_opc <= (srst && !ss_we) ? upc_opc_r : upc_opc_n;
        upc_loc <= (srst && !ss_we) ? upc_loc_r : upc_loc_n;

        dec_q <= {dec_valid_next, dec_bank_next};
        seg_override <= (srst && !ss_we) ? seg_override_r : seg_override_n;
        seg_ovr <= (srst && !ss_we) ? seg_ovr_r : seg_ovr_n;
        rep_kind <= (srst && !ss_we) ? rep_kind_r : rep_kind_n;
        lock_pfx <= (srst && !ss_we) ? lock_pfx_r : lock_pfx_n;
        opc_reg <= (srst && !ss_we) ? opc_reg_r : opc_reg_n;
        op8 <= (srst && !ss_we) ? op8_r : op8_n;
        imm8 <= (srst && !ss_we) ? imm8_r : imm8_n;
        opc_base <= (srst && !ss_we) ? opc_base_r : opc_base_n;
        opc_from_modrm <= (srst && !ss_we) ? opc_from_modrm_r : opc_from_modrm_n;
        modrm_reg <= (srst && !ss_we) ? modrm_reg_r : modrm_reg_n;
        xop <= (srst && !ss_we) ? xop_r : xop_n;
        rep_test <= (srst && !ss_we) ? rep_test_r : rep_test_n;
        rep_pol <= (srst && !ss_we) ? rep_pol_r : rep_pol_n;
        bus_word <= (srst && !ss_we) ? bus_word_r : bus_word_n;
        opc8080 <= (srst && !ss_we) ? opc8080_r : opc8080_n;
        mode8080 <= (srst && !ss_we) ? mode8080_r : mode8080_n;
        intr_pending <= (srst && !ss_we) ? intr_pending_r : intr_pending_n;
        eu_halted <= (srst && !ss_we) ? eu_halted_r : eu_halted_n;
        int_p <= (srst && !ss_we) ? int_p_r : int_p_n;
        nmi_p <= (srst && !ss_we) ? nmi_p_r : nmi_p_n;
        nmi_latch <= (srst && !ss_we) ? nmi_latch_r : nmi_latch_n;
        ie_p <= (srst && !ss_we) ? ie_p_r : ie_p_n;
        rep_chain <= (srst && !ss_we) ? rep_chain_r : rep_chain_n;
        irq_shadow <= (srst && !ss_we) ? irq_shadow_r : irq_shadow_n;
        bnd_armed <= (srst && !ss_we) ? bnd_armed_r : bnd_armed_n;
        irq_sel_nmi <= (srst && !ss_we) ? irq_sel_nmi_r : irq_sel_nmi_n;
        irq_sel_brk <= (srst && !ss_we) ? irq_sel_brk_r : irq_sel_brk_n;
        brk_p <= (srst && !ss_we) ? brk_p_r : brk_p_n;
        brk_arm <= (srst && !ss_we) ? brk_arm_r : brk_arm_n;
        brk_smp <= (srst && !ss_we) ? brk_smp_r : brk_smp_n;
        unhalt_pend <= (srst && !ss_we) ? unhalt_pend_r : unhalt_pend_n;
        irq_fast_inta <= (srst && !ss_we) ? irq_fast_inta_r
                                          : irq_fast_inta_n;
        irq_halt_entry <= (srst && !ss_we) ? irq_halt_entry_r
                                           : irq_halt_entry_n;
        m_kind <= (srst && !ss_we) ? m_kind_r : m_kind_n;
        r_kind <= (srst && !ss_we) ? r_kind_r : r_kind_n;
        wb_kind <= (srst && !ss_we) ? wb_kind_r : wb_kind_n;
        m_idx <= (srst && !ss_we) ? m_idx_r : m_idx_n;
        r_idx <= (srst && !ss_we) ? r_idx_r : r_idx_n;
        wb_idx <= (srst && !ss_we) ? wb_idx_r : wb_idx_n;
        m_ea <= (srst && !ss_we) ? m_ea_r : m_ea_n;
        r_ea <= (srst && !ss_we) ? r_ea_r : r_ea_n;
        wb_ea <= (srst && !ss_we) ? wb_ea_r : wb_ea_n;
        m_seg <= (srst && !ss_we) ? m_seg_r : m_seg_n;
        r_seg <= (srst && !ss_we) ? r_seg_r : r_seg_n;
        wb_seg <= (srst && !ss_we) ? wb_seg_r : wb_seg_n;
        m_byte <= (srst && !ss_we) ? m_byte_r : m_byte_n;
        r_byte <= (srst && !ss_we) ? r_byte_r : r_byte_n;
        wb_byte <= (srst && !ss_we) ? wb_byte_r : wb_byte_n;
        pend_active <= (srst && !ss_we) ? pend_active_r : pend_active_n;
        pend_off <= (srst && !ss_we) ? pend_off_r : pend_off_n;
        pend_seg <= (srst && !ss_we) ? pend_seg_r : pend_seg_n;
        pend_byte <= (srst && !ss_we) ? pend_byte_r : pend_byte_n;
        pend_io <= (srst && !ss_we) ? pend_io_r : pend_io_n;
        opr_fresh <= (srst && !ss_we) ? opr_fresh_r : opr_fresh_n;
        opr_loaded <= (srst && !ss_we) ? opr_loaded_r : opr_loaded_n;
        rdp0_byte <= (srst && !ss_we) ? rdp0_byte_r : rdp0_byte_n;
        rdp1_byte <= (srst && !ss_we) ? rdp1_byte_r : rdp1_byte_n;
        rdq0_byte <= (srst && !ss_we) ? rdq0_byte_r : rdq0_byte_n;
        rdq1_byte <= (srst && !ss_we) ? rdq1_byte_r : rdq1_byte_n;
        rdq0 <= (srst && !ss_we) ? rdq0_r : rdq0_n;
        rdq1 <= (srst && !ss_we) ? rdq1_r : rdq1_n;
        rdq_n <= (srst && !ss_we) ? rdq_n_r : rdq_n_n;
        rd_pending <= (srst && !ss_we) ? rd_pending_r : rd_pending_n;
        ghost_rd_discard <= (srst && !ss_we) ? ghost_rd_discard_r
                                             : ghost_rd_discard_n;
        rd_done_cnt <= (srst && !ss_we) ? rd_done_cnt_r : rd_done_cnt_n;
        rd_age0 <= (srst && !ss_we) ? rd_age0_r : rd_age0_n;
        iend_owed <= (srst && !ss_we) ? iend_owed_r : iend_owed_n;
        rst_ctr <= (srst && !ss_we) ? rst_ctr_r : rst_ctr_n;
        tsel <= (srst && !ss_we) ? tsel_r : tsel_n;
        pe_opc_reg <= (srst && !ss_we) ? pe_opc_reg_r : pe_opc_reg_n;
        pe_opc8080 <= (srst && !ss_we) ? pe_opc8080_r : pe_opc8080_n;
        pe_op8 <= (srst && !ss_we) ? pe_op8_r : pe_op8_n;
        pe_pfxcnt <= (srst && !ss_we) ? pe_pfxcnt_r : pe_pfxcnt_n;
        wr_out <= (srst && !ss_we) ? wr_out_r : wr_out_n;
        opc_valid <= (srst && !ss_we) ? opc_valid_r : opc_valid_n;
        opc_byte <= (srst && !ss_we) ? opc_byte_r : opc_byte_n;
        pop_is_first <= (srst && !ss_we) ? pop_is_first_r : pop_is_first_n;
        ld_b <= (srst && !ss_we) ? ld_b_r : ld_b_n;
        ld_pla <= (srst && !ss_we) ? ld_pla_r : ld_pla_n;
        ld_ext <= (srst && !ss_we) ? ld_ext_r : ld_ext_n;
        ld_page <= (srst && !ss_we) ? ld_page_r : ld_page_n;
        ld_hasrm <= (srst && !ss_we) ? ld_hasrm_r : ld_hasrm_n;
        ld_rm <= (srst && !ss_we) ? ld_rm_r : ld_rm_n;
        ld_disp <= (srst && !ss_we) ? ld_disp_r : ld_disp_n;
        ld_dlo <= (srst && !ss_we) ? ld_dlo_r : ld_dlo_n;
        ld_grpd <= (srst && !ss_we) ? ld_grpd_r : ld_grpd_n;
        ld_byte <= (srst && !ss_we) ? ld_byte_r : ld_byte_n;
        ld_preread <= (srst && !ss_we) ? ld_preread_r : ld_preread_n;
        ld_ripe_prev <= (srst && !ss_we) ? ld_ripe_prev_r : ld_ripe_prev_n;
        st <= (srst && !ss_we) ? st_r : st_n;
        chg <= (srst && !ss_we) ? chg_r : chg_n;
        ending <= (srst && !ss_we) ? ending_r : ending_n;
        rowq <= (srst && !ss_we) ? rowq_r : rowq_n;
        row_posted <= (srst && !ss_we) ? row_posted_r : row_posted_n;
        row_paired <= (srst && !ss_we) ? row_paired_r : row_paired_n;
        rloop_n <= (srst && !ss_we) ? rloop_n_r : rloop_n_n;
        suppress_commit <= (srst && !ss_we) ? suppress_commit_r : suppress_commit_n;
        first_pop_seen <= (srst && !ss_we) ? first_pop_seen_r : first_pop_seen_n;
        rowb0 <= (srst && !ss_we) ? rowb0_r : rowb0_n;
        rowb1 <= (srst && !ss_we) ? rowb1_r : rowb1_n;
        poste <= (srst && !ss_we) ? poste_r : poste_n;
        poll_pipe <= (srst && !ss_we) ? poll_pipe_r : poll_pipe_n;
    end
end

`ifndef SYNTHESIS

always @(posedge clk) begin
    if (srst) ce_clk <= 0;
    else if (ce && !ss_we) ce_clk <= ce_clk + 1;
    if (ce && !srst && !ss_we) begin

        if (eu_rd_done_n) begin
            assert (rdq_n != 2'd2)
                else $warning("v30u_eu: completed-read store overflow (rdq_n=2)");
            assert (rd_done_cnt != 2'd3)
                else $warning("v30u_eu: rd_done_cnt saturated");
        end

        if (rd_edge_take_raw && row_blocked)
            assert (!poste && !iend_owed)
                else $error("v30u_eu: R7' falsifier (A): data-edge PSW load with the chain stopped but poste=%0d iend_owed=%0d owed -- they read-modify-write psw_n between the old write site and the commit, so the D-pin form is NOT equivalent here (upc=%0d.%02X.%0d)",
                            poste, iend_owed, upc_page, upc_opc, upc_loc);
        if (rd_edge_take_raw && !row_blocked)
            assert (row_acts_ok && e_have1)
                else $error("v30u_eu: R7' falsifier (B): data-edge PSW load with the chain RUNNING but the row not performing its own OPR->FLAGS (row_acts_ok=%0d e_have1=%0d) -- the deleted block-(a) write was NOT dead here (f_wait=%0d nr_wait=%0d rd_done_cnt=%0d rd_pending=%0d upc=%0d.%02X.%0d)",
                            row_acts_ok, e_have1, f_wait, nr_wait,
                            rd_done_cnt, rd_pending,
                            upc_page, upc_opc, upc_loc);

        if (poste && row_bus)
            $error("v30u_eu: a post-E row carries a bus cycle (upc %0d.%02X.%0d)",
                   upc_page, upc_opc, upc_loc);
        if (poste && (row_q1 || row_q2))
            $error("v30u_eu: a post-E row pops a queue byte");
        if (brktrace && trc_pe_hit)
            $display("PE  clk=%0d pre=%04x post=%04x upc=%03X",
                     ce_clk, trc_pe_pre, trc_pe_post, trc_pe_upc);
        if (brktrace && trc_1bl_hit)
            $display("1BL clk=%0d pre=%04x post=%04x psw=%04x pswn=%04x",
                     ce_clk, trc_1bl_pre, trc_1bl_post, psw, psw_n);

        if (brktrace && trc_1bld_hit)
            $display("1BLD clk=%0d ripe_lead=%0d seen=%0d arm=%0d smp=%0d shd=%0d",
                     ce_clk, trc_1bld_ripe, trc_1bld_seen, trc_1bld_arm,
                     trc_1bld_smp, trc_1bld_shd);
        if (brktrace) begin

            if (brk_now && !brk_p[0])
                $display("BRKR clk=%0d", ce_clk);
            if (brk_smp)
                $display("BRKS clk=%0d seen=%0d psw_brk=%0d brk_p=%0d arm=%0d",
                         ce_clk, brk_seen, psw[FBRK], brk_p, brk_arm);
            if (bnd_fire)
                $display("BRKT clk=%0d arm=%0d irq=%0d sel_brk=%0d",
                         ce_clk, brk_arm, irq_take, !irq_take);
        end
        if (eutrace)
            $display("EU st=%0d upc=%0d.%02X.%0d row=%07x q=%02x ripe=%0d slot=%0d post=%0d bs=%0d a=%05x pair=%0d wd=%04x rdd=%0d wrd=%0d oprf=%0d wr_out=%0d pc=%04x ind=%04x opr=%04x of=%0d pnd=%0d pe=%0d rdq=%0d rdc=%0d a=%04x b=%04x c=%04x sig=%04x pfx=%0d",
                     trc_st, trc_upc_page, trc_upc_opc, trc_upc_loc, row, q_byte, q_ripe,
                     eu_slot_busy_n, eu_post, eu_bs, eu_addr, eu_pair,
                     eu_wdata,
                     eu_rd_done_n, eu_wr_done_n, eu_opr_free, trc_wr_out, trc_pc,
                     trc_ind, trc_opr, trc_opr_fresh, trc_pend_active, trc_poste, trc_rdq_n,
                     trc_rd_done_cnt, trc_tmpa, trc_tmpb, trc_tmpc, sigma, pfxcnt_eff);

        if (!stop)
            $fatal(1, "v30u_eu: CHAIN OVERFLOW at CHAIN_MAX=%0d (entered in st=%0d, now st=%0d)",
                   CHAIN_MAX, chain_first, st_n);
        if (chain_used > chain_hi) begin
            chain_hi = chain_used;
            if (chain_report)
                $display("CHAIN_DEPTH_MAX %0d entry_st %0d", chain_hi, chain_first);
            `ifdef CHAIN_PROBE
            begin : probe
                integer fd;
                fd = $fopen(`CHAIN_PROBE, "a");
                $fwrite(fd, "%0d %0d\n", chain_hi, chain_first);
                $fclose(fd);
            end
            `endif
        end
    end
end
`endif

always @(posedge clk) begin
    `include "v30u_eu_ss_read.svh"
end

wire _unused_eu = &{1'b0, q_cnt, halted, lock_pfx, nmi_p[2:0], int_p[0],
                    int_p[3], ie_p[3], ie_p[1:0],
                    ar_full, ar_m, row_paired, imm8,
                    r_ictl, r_ectl, r_sr, r_f, r_w, r_e, r_type, r_nopmove,
                    r_hasconst, r_s1, r_d1, r_s2, r_d2, r_r, dec_valid,
                    SR_ES, SR_SS, SR_DS, R_CW, R_DW, R_SP, BS_PASV,
                    A_SHL6, A_NOT, A_PASS, C_OPC, I_SUSP, I_FLUSH, E_MEMR,
                    TEST_NONE, tk, ti, ts, te, tb, ea, rseg, nloc};

endmodule
