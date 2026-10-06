case (st_n)

S_OPC_POP: if (chain == 4'd0) begin

    if (bnd_armed_n && bnd_take) begin
        bnd_armed_n   = 1'b0;
        irq_shadow_n  = 1'b0;
        irq_fast_inta_n = 1'b1;
        irq_sel_nmi_n = irq_nmi_lvl;
        irq_sel_brk_n = !irq_take;
        brk_arm_n     = brk_arm_n && irq_take;

        st_n = S_IRQ_D;
        stop = 1'b1;
    end else if (!q_ripe) stop = 1'b1;
    else begin

        bnd_armed_n = 1'b0; irq_shadow_n = 1'b0;
        ld_b_n = q_byte;
        pc_n   = pc_n + 16'd1;
        pop_is_first_n = 1'b0;
        st_n = S_DECODE;
    end
end

S_TAKE_OPC: begin

    ld_b_n = opc_byte_n;
    opc_valid_n = 1'b0;
    pc_n = pc_n + 16'd1;
    st_n = S_DECODE;
end

S_DECODE: begin

    pv = pla3_native(ld_b_n);
    if (pla3_is_prefix(pv)) begin
        case (pla3_xop(pv))
            PLA3_BL1_SEG_PREFIX: begin
                seg_override_n = 1'b1; seg_ovr_n = ld_b_n[4:3];
            end
            PLA3_BL1_REP_PFX:   rep_kind_n = REP_E;
            PLA3_BL1_REPNE_PFX: rep_kind_n = REP_NE;
            PLA3_BL1_REPC_PFX:  rep_kind_n = REP_C;
            PLA3_BL1_REPNC_PFX: rep_kind_n = REP_NC;
            PLA3_BL1_LOCK, PLA3_BL1_LOCK_ALIAS: lock_pfx_n = 1'b1;
            PLA3_BL1_EXT_PREFIX: ld_ext_n = 1'b1;
            default: ;
        endcase
        pfxcnt_n = pfxcnt_n + 8'd1;

        st_n = (pla3_xop(pv) == PLA3_BL1_EXT_PREFIX) ? S_EXT_CHG1 : S_PFX_CHG;
        stop = 1'b1;
    end else begin
        st_n = S_DECODE2;
    end
end

S_PFX_CHG: if (chain == 4'd0) begin
    pop_is_first_n = 1'b1;
    st_n = S_OPC_POP;
    stop = 1'b1;
end

S_EXT_CHG1: if (chain == 4'd0) begin
    st_n = S_EXT_POP;
    stop = 1'b1;
end

S_EXT_POP: if (chain == 4'd0) begin

    if (!q_ripe) stop = 1'b1;
    else begin
        ld_b_n = q_byte;
        pc_n   = pc_n + 16'd1;
        st_n = S_DECODE2;
    end
end

S_DECODE2: begin
    pv = ld_ext_n ? pla3_ext(ld_b_n) : pla3_native(ld_b_n);
    ld_pla_n = pv;
    if (!ld_ext_n && pla3_one_byte_logic(pv)) begin

        if (pla3_xop(pv) == PLA3_BL1_HALT && !brk_seen) begin

            eu_halted_n = 1'b1;

            pop_is_first_n = 1'b1;
            psw_n = (psw_n & PSW_WRITABLE) | PSW_FORCED;
            st_n = S_HALTED;
        end else begin

`ifndef SYNTHESIS

            trc_1bld_hit = 1'b1; trc_1bld_ripe = q_ripe_lead_n;
            trc_1bld_seen = brk_seen; trc_1bld_arm = brk_arm;
            trc_1bld_smp = brk_smp_n; trc_1bld_shd = irq_shadow_n;
`endif

            if (q_ripe_lead_n || brk_seen) begin
                `include "v30u_eu_1bl.svh"
                st_n = S_1BL_CHG;
            end else begin
                st_n = S_1BL_LEAD;
            end
        end
        stop = 1'b1;
    end else begin
        ld_byte_n = pla3_byte_only(pv) ? 1'b1
                : pla3_w_from_bit0(pv) ? (ld_b_n[0] == 1'b0)
                : 1'b0;
        op8_n  = ld_byte_n;
        imm8_n = ld_byte_n || (ld_b_n == 8'h83) || (ld_b_n == 8'h6B);
        xop_n  = pla3_xop(pv);

        if (!ld_ext_n && (pla3_sreg_mov(pv) ||
                          ld_b_n == 8'h07 || ld_b_n == 8'h17 ||
                          ld_b_n == 8'h1F))
            irq_shadow_n = 1'b1;
        ld_page_n = ld_ext_n ? 3'd4 : ((rep_kind_n != REP_NONE) ? 3'd1 : 3'd0);
        opc_reg_n = ld_b_n;
        ld_hasrm_n = pla3_has_modrm(pv);
        st_n = pla3_has_modrm(pv) ? S_MODRM : S_NORM_CHG;
        stop = 1'b1;
    end
end

S_1BL_LEAD: if (chain == 4'd0) begin

    if (!q_ripe_lead_n) stop = 1'b1;
    else begin
        `include "v30u_eu_1bl.svh"
        st_n = S_1BL_CHG;
        stop = 1'b1;
    end
end

S_1BL_CHG: if (chain == 4'd0) begin

    st_n = S_INSTR_END;
end

S_MODRM: if (chain == 4'd0) begin
    if (!q_ripe) stop = 1'b1;
    else begin
        ld_rm_n = q_byte;
        pc_n = pc_n + 16'd1;
        ld_disp_n = 16'd0;
        ld_ripe_prev_n = 1'b0;
        chg_n = 2'd0;
        if (q_byte[7:6] == 2'd1)                        st_n = S_D8_A;
        else if (q_byte[7:6] == 2'd2)                   st_n = S_D16_LO;
        else if ((q_byte[7:6] == 2'd0) && (q_byte[2:0] == 3'd6))
                                                        st_n = S_D16_LO;
        else if (q_byte[7:6] != 2'd3)                   st_n = S_EA_CHG;
        else                                            st_n = S_BIND;
        if (st_n != S_BIND) stop = 1'b1;
    end
end

S_D8_A: if (chain == 4'd0) begin

    ld_ripe_prev_n = q_ripe;
    st_n = S_D8_B;
    stop = 1'b1;
end

S_D8_B: if (chain == 4'd0) begin
    if (!q_ripe) stop = 1'b1;
    else if (!ld_ripe_prev_n && (chg_n == 2'd0)) begin
        chg_n = 2'd1;
        stop = 1'b1;
    end else begin
        ld_disp_n = {{8{q_byte[7]}}, q_byte};
        pc_n = pc_n + 16'd1;
        st_n = S_EA_CALC;
    end
end

S_D16_LO: if (chain == 4'd0) begin
    if (!q_ripe) stop = 1'b1;
    else begin
        ld_dlo_n = q_byte;
        pc_n = pc_n + 16'd1;
        st_n = S_D16_A;
        stop = 1'b1;
    end
end

S_D16_A: if (chain == 4'd0) begin
    ld_ripe_prev_n = q_ripe;
    chg_n = 2'd0;
    st_n = S_D16_HI;
    stop = 1'b1;
end

S_D16_HI: if (chain == 4'd0) begin
    if (!q_ripe) stop = 1'b1;
    else if (!ld_ripe_prev_n && (chg_n == 2'd0)) begin
        chg_n = 2'd1;
        stop = 1'b1;
    end else begin
        ld_disp_n = {q_byte, ld_dlo_n};
        pc_n = pc_n + 16'd1;
        st_n = S_EA_CALC;
    end
end

S_EA_CHG: if (chain == 4'd0) begin
    st_n = S_EA_CALC;
end

S_EA_CALC: begin

    rmmod = ld_rm_n[7:6];
    rmrm  = ld_rm_n[2:0];
    case (rmrm)
        3'd0: ea = gpr_n[R_BW] + gpr_n[R_IX];
        3'd1: ea = gpr_n[R_BW] + gpr_n[R_IY];
        3'd2: ea = gpr_n[R_BP] + gpr_n[R_IX];
        3'd3: ea = gpr_n[R_BP] + gpr_n[R_IY];
        3'd4: ea = gpr_n[R_IX];
        3'd5: ea = gpr_n[R_IY];
        3'd6: ea = (rmmod == 2'd0) ? 16'd0 : gpr_n[R_BP];
        default: ea = gpr_n[R_BW];
    endcase

    ea_residue_n = ea;

    ea_pair_valid_n = (rmrm <= 3'd3);
    if ((rmrm == 3'd0) || (rmrm == 3'd2))
        ea_pair_rhs_n = gpr_n[R_IX];
    else if ((rmrm == 3'd1) || (rmrm == 3'd3))
        ea_pair_rhs_n = gpr_n[R_IY];
    ea = ea + ld_disp_n;
    rseg = seg_override_n ? {1'b0, seg_ovr_n}
         : ((rmrm == 3'd2) || (rmrm == 3'd3) ||
            ((rmrm == 3'd6) && (rmmod != 2'd0))) ? 3'd2 : 3'd3;
    ind_n = ea;
    al_eaconst_n = 1'b1;
    al_eaval_n   = ea;
    m_ea_n = ea;  m_seg_n = rseg;
    st_n = S_BIND;
end

S_NORM_CHG: if (chain == 4'd0) begin
    st_n = S_BIND;
end

S_BIND: begin

    pv = ld_pla_n;
    rmmod = ld_rm_n[7:6];
    rmreg = ld_rm_n[5:3];
    rmrm  = ld_rm_n[2:0];
    ld_grpd_n = 1'b0;

    if (!ld_ext_n && (ld_b_n == 8'h8D) && (rmmod != 2'd3))
        ea_residue_n = ind_n;
    if (ld_hasrm_n && (pla3_xop(pv) == 4'hB)) begin
        ld_page_n = ld_b_n[3] ? 3'd3 : 3'd2;
        opc_reg_n = ld_rm_n;
        ld_grpd_n = 1'b1;
    end
    modrm_reg_n = rmreg;
    opc_from_modrm_n = 1'b0;
    opc_base_n = 5'd0;
    if ((ld_page_n == 3'd2) || (ld_page_n == 3'd3)) begin
        opc_base_n = A_INC; opc_from_modrm_n = 1'b1;
    end else if (!ld_ext_n && (ld_b_n[7:2] == 6'b100000)) begin
        opc_base_n = 5'd0;  opc_from_modrm_n = 1'b1;
    end else if (!ld_ext_n && ((ld_b_n == 8'hC0) || (ld_b_n == 8'hC1) ||
                             (ld_b_n[7:2] == 6'b110100))) begin
        opc_base_n = A_ROL; opc_from_modrm_n = 1'b1;
    end else if (pla3_xop(pv) == 4'hC) begin
        opc_base_n = A_INC;
    end
    rep_test_n = TEST_NONE;
    rep_pol_n  = 1'b0;
    if (pla3_xop(pv) == 4'hE) begin
        if (!ld_ext_n && (ld_b_n[7:1] == 7'b1110000)) begin

            if ((rep_kind_n == REP_C) || (rep_kind_n == REP_NC))
                rep_test_n = TEST_CY;
            else
                rep_test_n = TEST_Z;
            rep_pol_n = ld_b_n[0];
        end else if ((rep_kind_n == REP_E) || (rep_kind_n == REP_NE)) begin
            rep_test_n = TEST_Z; rep_pol_n = (rep_kind_n == REP_E);
        end else if ((rep_kind_n == REP_C) || (rep_kind_n == REP_NC)) begin
            rep_test_n = TEST_CY; rep_pol_n = (rep_kind_n == REP_C);
        end
    end

    bsw = ld_byte_n || (ld_ext_n && (pla3_xop(pv) == 4'h3));
    m_kind_n = OK_NONE; m_idx_n = 3'd0; m_byte_n = 1'b0;
    r_kind_n = OK_NONE; r_idx_n = 3'd0; r_byte_n = 1'b0; r_ea_n = 16'd0; r_seg_n = 3'd3;

    if (!ld_ext_n && (ld_b_n == 8'h8D) && (rmmod == 2'd3)) begin
        tmpa_n = ea_residue_n;
        if (ea_pair_valid_n) tmpb_n = ea_pair_rhs_n;
    end
    if (ld_hasrm_n) begin
        if (pla3_sreg_mov(pv)) begin
            r_kind_n = OK_SREG; r_idx_n = {1'b0, rmreg[1:0]}; r_byte_n = 1'b0;
        end else begin
            r_kind_n = OK_REG;  r_idx_n = rmreg; r_byte_n = bsw;
        end

        if ((rmmod == 2'd3) ||
            (ld_ext_n && (pla3_xop(pv) == 4'h3))) begin
            m_kind_n = OK_REG; m_idx_n = rmrm; m_byte_n = bsw;
        end else begin
            m_kind_n = OK_MEM; m_byte_n = ld_byte_n;
        end
        if (pla3_dir_from_bit1(pv) && ld_b_n[1]) begin
            tk = m_kind_n; m_kind_n = r_kind_n; r_kind_n = tk;
            ti = m_idx_n;  m_idx_n  = r_idx_n;  r_idx_n  = ti;
            te = m_ea_n;   m_ea_n   = r_ea_n;   r_ea_n   = te;
            ts = m_seg_n;  m_seg_n  = r_seg_n;  r_seg_n  = ts;
            tb = m_byte_n; m_byte_n = r_byte_n; r_byte_n = tb;
        end
    end else if (pla3_acc_w_operand(pv)) begin
        m_kind_n = OK_REG; m_idx_n = R_AW; m_byte_n = ld_byte_n;
    end else if ((ld_b_n < 8'h40) && (ld_b_n[2:0] >= 3'd6)) begin
        r_kind_n = OK_SREG; r_idx_n = {1'b0, ld_b_n[4:3]};
    end else begin
        m_kind_n = OK_REG; m_idx_n = ld_b_n[2:0]; m_byte_n = ld_byte_n;
    end
    wb_kind_n = m_kind_n; wb_idx_n = m_idx_n; wb_ea_n = m_ea_n;
    wb_seg_n = m_seg_n;   wb_byte_n = m_byte_n;

    ld_preread_n = 1'b0;
    if (ld_hasrm_n && (rmmod != 2'd3) && !(!ld_ext_n && pla3_modrm_store(pv)))
        if ((m_kind_n == OK_MEM) || (r_kind_n == OK_MEM)) begin
            ld_preread_n = 1'b1;

            opr_loaded_n = 1'b1;
        end

    row_posted_n = 1'b0;
    if (ld_preread_n)     st_n = S_PRERD;
    else if (ld_grpd_n)   st_n = S_GRPD_CHG;
    else                st_n = S_ENTER;
    if (st_n != S_ENTER) stop = 1'b1;
end

S_PRERD: if (chain == 4'd0) begin

    if (!row_posted_n) begin
        if (eu_slot_busy_n) stop = 1'b1;
        else begin
            row_posted_n = 1'b1;

            if (rd_pending_n == 2'd0)      rdp0_byte_n = pr_byte;
            else if (rd_pending_n == 2'd1) rdp1_byte_n = pr_byte;

            if (rd_pending_n != 2'd3) rd_pending_n = rd_pending_n + 2'd1;
            stop = 1'b1;
        end
    end else if (rd_done_cnt_n == 2'd0) begin
        stop = 1'b1;
    end else begin
        rd_done_cnt_n = rd_done_cnt_n - 2'd1;
        if (rdq_n_n != 2'd0) begin
            opr_n = rdq0_n; rdq0_n = rdq1_n; rdq_n_n = rdq_n_n - 2'd1;

                    opr_byte_n = rdq0_byte_n; rdq0_byte_n = rdq1_byte_n;
            opr_loaded_n = 1'b1;
        end

        row_posted_n = 1'b0;
        st_n = ld_grpd_n ? S_GRPD_CHG : S_ENTER;
        if (ld_grpd_n) stop = 1'b1;
    end
end

S_GRPD_CHG: if (chain == 4'd0) begin
    st_n = S_ENTER;
end

S_ENTER: begin

    upc_page_n = ld_page_n;
    upc_opc_n  = opc_reg_n;
    upc_loc_n  = 4'd0;
    ending_n = 1'b0; rowq_n = 2'd0; row_posted_n = 1'b0; row_paired_n = 1'b0;
    suppress_commit_n = 1'b0;
    st_n = S_ROW;
    stop = 1'b1;
end

S_ROW: if (chain == 4'd0) begin
    if (row_blocked) begin
        stop = 1'b1;
    end else if (row_need_q && !q_ripe) begin
        stop = 1'b1;
    end else if (row_need_q) begin
        if (row_q1 && (rowq_n == 2'd0)) rowb0_n = q_byte; else rowb1_n = q_byte;
        pc_n = pc_n + 16'd1;
        rowq_n = rowq_n + 2'd1;
        if ({1'b0, rowq_n} < row_qn) stop = 1'b1;
    end else if (row_pre_wait) begin
        stop = 1'b1;
    end else if (row_slot_wait) begin

        if (row_bus && pend_active_n) begin
            if (!opr_fresh_n) begin
                if (rd_done_cnt_n != 2'd0) rd_done_cnt_n = rd_done_cnt_n - 2'd1;
                if (rdq_n_n != 2'd0) begin
                    opr_n = rdq0_n; rdq0_n = rdq1_n; rdq_n_n = rdq_n_n - 2'd1;

                    opr_byte_n = rdq0_byte_n; rdq0_byte_n = rdq1_byte_n;
                    opr_loaded_n = 1'b1;
                end
            end
            pend_active_n = 1'b0;
            opr_fresh_n   = 1'b0;
        end

        stop = 1'b1;
    end
    if (!stop) begin

        if (e_f) begin
            if (row_reads_opr && (rd_done_cnt_n != 2'd0))
                rd_done_cnt_n = rd_done_cnt_n - 2'd1;
            if (rdq_n_n != 2'd0) begin
                opr_n = rdq0_n; rdq0_n = rdq1_n; rdq_n_n = rdq_n_n - 2'd1;

                    opr_byte_n = rdq0_byte_n; rdq0_byte_n = rdq1_byte_n;
                opr_fresh_n = 1'b1;
                opr_loaded_n = 1'b1;
            end
        end
        `include "v30u_eu_row.svh"
        if (tmpa_n != tmpa) begin

            if (!((upc_page == 3'd0) && (upc_opc == 8'h8f) &&
                  (upc_loc == 4'd0) && (m_kind_n == OK_REG) &&
                  (wb_kind_n == OK_REG) && (ea_residue_n != tmpa)))
                ea_residue_n = tmpa_n;
        end

        if (tmpb_n != tmpb) ea_pair_valid_n = 1'b0;
    end
end

S_ROW_CHG: if (chain == 4'd0) begin

    st_n = S_ROW;
    stop = 1'b1;
end

S_RLOOP: if (chain == 4'd0) begin

    count_n = count_n - 16'd1;
    rloop_n_n = rloop_n_n - 16'd1;
    if (it_fmask != 16'd0)
        stat_n = (stat_n & ~it_fmask) | (it_flags & it_fmask);
    if (!e_nopmv) begin
        v1 = it_val;
        bsw = 1'b0;

        wb1 = al_width_byte;
        `include "v30u_eu_wd1.svh"
    end

    if (it_writes_tmpa) tmpa_n = it_tmpa;
    if (tmpa_n != tmpa) ea_residue_n = tmpa_n;
    if (tmpb_n != tmpb) ea_pair_valid_n = 1'b0;
    if (e_w && (it_fmask != 16'd0)) commit_flags(it_fmask, it_flags);

    if (rloop_n_n == 16'd0) begin
        al_spent_n = 1'b1;

        if (upc_loc_n == 4'hF) upc_opc_n = upc_opc_n + 8'd1;
        upc_loc_n = upc_loc_n + 4'd1;
        st_n = S_ROW;
    end
    stop = 1'b1;
end

S_EPOP: if (chain == 4'd0) begin

    if (!retire_ok_n) stop = 1'b1;

    else if (bnd_take) begin
        irq_shadow_n = 1'b0;
        irq_sel_nmi_n = irq_nmi_lvl;
        irq_sel_brk_n = !irq_take;
        brk_arm_n = brk_arm_n && irq_take;
        poste_n = 1'b1; pe_opc_reg_n = opc_reg_n; pe_opc8080_n = opc8080_n;
        pe_op8_n = op8_n; pe_pfxcnt_n = pfxcnt_n;
        st_n = S_IRQ_D;
        stop = 1'b1;
    end
    else if (!q_ripe) stop = 1'b1;
    else begin
        irq_shadow_n = 1'b0;
        opc_byte_n = q_byte;
        opc_valid_n = 1'b1;
        pop_is_first_n = 1'b0;
        poste_n = 1'b1; pe_opc_reg_n = opc_reg_n; pe_opc8080_n = opc8080_n;
        pe_op8_n = op8_n; pe_pfxcnt_n = pfxcnt_n;
        st_n = S_TAIL;
    end
end

S_TAIL: begin

    if (pend_active_n) st_n = S_TAIL_W;
    else if (opc_valid_n) st_n = S_INSTR_END;
    else st_n = S_TAIL_POP;
    if (st_n != S_INSTR_END) stop = 1'b1;
end

S_TAIL_W: if (chain == 4'd0) begin

    if (!opr_fresh_n && (nr_wait || !opr_free_now)) stop = 1'b1;
    else begin
        if (!opr_fresh_n) begin
            if (rd_done_cnt_n != 2'd0) rd_done_cnt_n = rd_done_cnt_n - 2'd1;
            if (rdq_n_n != 2'd0) begin
                opr_n = rdq0_n; rdq0_n = rdq1_n; rdq_n_n = rdq_n_n - 2'd1;

                    opr_byte_n = rdq0_byte_n; rdq0_byte_n = rdq1_byte_n;
                opr_loaded_n = 1'b1;
            end
        end
        pend_active_n = 1'b0;
        opr_fresh_n   = 1'b0;

        if (opc_valid_n) begin
            st_n = S_INSTR_END;
        end else if (retire_ok_n && bnd_take) begin

            irq_shadow_n  = 1'b0;
            irq_sel_nmi_n = irq_nmi_lvl;
            irq_sel_brk_n = !irq_take;
            brk_arm_n = brk_arm_n && irq_take;
            st_n = S_IRQ_D;
            stop = 1'b1;
        end else begin
            st_n = S_TAIL_POP;
        end
    end
end

S_TAIL_POP: begin

    if (!retire_ok_n) stop = 1'b1;

    else if (bnd_take) begin
        irq_shadow_n = 1'b0;
        irq_sel_nmi_n = irq_nmi_lvl;
        irq_sel_brk_n = !irq_take;
        brk_arm_n = brk_arm_n && irq_take;
        st_n = S_IRQ_D;
        stop = 1'b1;
    end
    else if (!q_ripe) stop = 1'b1;
    else begin
        irq_shadow_n = 1'b0;
        opc_byte_n = q_byte;
        opc_valid_n = 1'b1;
        pop_is_first_n = 1'b0;

        st_n = S_INSTR_END;
    end
end

S_HALTED: if (chain == 4'd0) begin

    if (irq_nmi_lvl) begin
        bnd_armed_n = 1'b1;
        st_n = S_OPC_POP;
    end else if (irq_pin_int) begin
        eu_halted_n = 1'b0;
        bnd_armed_n = 1'b1;
        irq_halt_entry_n = 1'b1;
        st_n = S_OPC_POP;
    end
    stop = 1'b1;
end

S_IRQ_D: if (chain == 4'd0) begin

    upc_page_n = 3'd7;
    upc_opc_n  = (irq_sel_nmi_n || irq_sel_brk_n) ? 8'h00 : 8'h02;
    upc_loc_n  = irq_sel_nmi_n ? 4'd2  : 4'd0;
    if (irq_sel_nmi_n) nmi_latch_n = 1'b0;

    if (irq_sel_brk_n) irq_fast_inta_n = 1'b0;
    seg_override_n = 1'b0; seg_ovr_n = 2'd3; rep_kind_n = REP_NONE; lock_pfx_n = 1'b0;
    pfxcnt_n = 8'd0;
    m_kind_n = OK_NONE; m_idx_n = 3'd0; m_ea_n = 16'd0; m_seg_n = 3'd3; m_byte_n = 1'b0;
    r_kind_n = OK_NONE; r_idx_n = 3'd0; r_ea_n = 16'd0; r_seg_n = 3'd3; r_byte_n = 1'b0;
    wb_kind_n = OK_NONE; wb_idx_n = 3'd0; wb_ea_n = 16'd0; wb_seg_n = 3'd3;
    wb_byte_n = 1'b0;
    opc_base_n = 5'd0; opc_from_modrm_n = 1'b0; modrm_reg_n = 3'd0; opc_reg_n = 8'd0;
    rep_test_n = TEST_NONE; rep_pol_n = 1'b0; xop_n = 4'd0;
    op8_n = 1'b0; imm8_n = 1'b0; bus_word_n = 1'b0; opc8080_n = 1'b0;
    al_op_n = A_ADD; al_tmp_n = 2'd0;
    al_eaconst_n = 1'b0; al_eaval_n = 16'd0;
    al_adjust_n = 2'd0; al_adjtmp_n = 2'd0; al_bitarm_n = 1'b0; al_bitn_n = 4'd0;
    al_spent_n = 1'b0;

    pend_active_n = 1'b0; pend_off_n = 16'd0; pend_seg_n = 3'd3;
    pend_byte_n = 1'b0; pend_io_n = 1'b0; opr_fresh_n = 1'b0;
    opr_loaded_n = 1'b0;
    rdq0_n = 16'd0; rdq1_n = 16'd0; rdq_n_n = 2'd0;
    rdq0_byte_n = 1'b0; rdq1_byte_n = 1'b0;
    ld_ext_n = 1'b0; ld_hasrm_n = 1'b0; ld_grpd_n = 1'b0; ld_preread_n = 1'b0;
    ld_rm_n = 8'd0; ld_disp_n = 16'd0;
    ending_n = 1'b0; rowq_n = 2'd0; row_posted_n = 1'b0; row_paired_n = 1'b0;
    suppress_commit_n = 1'b0;
    opc_valid_n = 1'b0; pop_is_first_n = 1'b1; bnd_armed_n = 1'b0;
    irq_shadow_n = 1'b0;
    intr_pending_n = 1'b0;
    rep_chain_n = 1'b0;
    if (eu_halted_n) begin
        eu_halted_n = 1'b0;
        unhalt_pend_n = 1'b1;
    end
    st_n = S_ROW;
    stop = 1'b1;
end

S_RESET: if (chain == 4'd0) begin

    rst_ctr_n = rst_ctr_n + 3'd1;
    if (rst_ctr_n == 3'd4) st_n = S_ROW;
    stop = 1'b1;
end

S_INSTR_END: begin

    seg_override_n = 1'b0; seg_ovr_n = 2'd3; rep_kind_n = REP_NONE; lock_pfx_n = 1'b0;
    rep_test_n = TEST_NONE; rep_pol_n = 1'b0; bus_word_n = 1'b0; opc8080_n = 1'b0;

    pfxcnt_n = 8'd0;
    ld_ext_n = 1'b0; ld_hasrm_n = 1'b0; ld_grpd_n = 1'b0; ld_preread_n = 1'b0;
    ld_rm_n = 8'd0; ld_disp_n = 16'd0;

    if (poste_n) iend_owed_n = 1'b1;
    else begin
        `include "v30u_eu_iend_late.svh"
    end
    ending_n = 1'b0; rowq_n = 2'd0; row_posted_n = 1'b0; row_paired_n = 1'b0;
    rep_chain_n = 1'b0;

    if (!opc_valid_n) begin
        pop_is_first_n = 1'b1;
        bnd_armed_n = 1'b1;
    end
    st_n = opc_valid_n ? S_TAKE_OPC : S_OPC_POP;
    if (st_n == S_OPC_POP) stop = 1'b1;
end

default: stop = 1'b1;
endcase
