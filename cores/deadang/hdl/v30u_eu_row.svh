begin

    if (e_have1 && !e_is_rloop) begin

        v1  = (e_s1 == 5'd7) ? {8'd0, rowb0_n}
            : (e_s1 == 5'd6) ? opr_n
            : s1_val;

        wb1 = (e_s1 == 5'd7) ? 1'b1
            : (e_s1 == 5'd6) ? opr_byte_n
            : s1_wbyte;
        bsw = s1_byte;
        if (e_s1 == 5'd6) opr_fresh_n = 1'b0;
        if (e_s1 == 5'd20) begin
            if (sig_mask != 16'd0)
                stat_n = (stat_n & ~sig_mask) | (sig_flags & sig_mask);
        end
        if ((e_s1 == 5'd20) && !sig_commits) begin

            if ((e_d1 == 5'd19) && (m_kind_n == OK_MEM)) suppress_commit_n = 1'b1;
        end else begin
            `include "v30u_eu_wd1.svh"
        end
    end
    if (e_have2 && !e_is_rloop) begin
        v2  = (e_s2 == 4'd5) ? {8'd0, rowb1_n} : s2_val;
        wb2 = (e_s2 == 4'd5) ? 1'b1           : s2_wbyte;
        if (e_s2 == 4'd4) begin
            if (sig_mask != 16'd0)
                stat_n = (stat_n & ~sig_mask) | (sig_flags & sig_mask);
        end
        if (!((e_s2 == 4'd4) && !sig_commits)) begin
            case (e_d2)
                2'd0: begin tmpa_n = v2; tmpa_byte_n = wb2; end
                2'd1: begin tmpb_n = v2; tmpb_byte_n = wb2; end
                2'd2: ind_n  = v2;
                default: ;
            endcase
        end
    end

    if (!e_is_rloop && e_w && !ext4s_early_wblock && (sig_mask != 16'd0))
        commit_flags(sig_mask, sig_flags);

    nloc  = upc_loc_n + 4'd1;
    carry = (upc_loc_n == 4'hF);
    taken = 1'b0;
    bubble = 1'b0;

    if (e_type == TY_ALU) begin

        al_adjust_n  = (al_op_n == A_ADJD) ? 2'd1 : (al_op_n == A_ADJA) ? 2'd2 : 2'd0;
        al_adjtmp_n  = al_tmp_n;
        al_bitarm_n  = (al_op_n == A_BIT);
        al_bitn_n    = bit_n_n;
        al_spent_n   = 1'b0;
        al_op_n      = r_aluop;
        al_tmp_n     = r_alutmp;

        al_eaconst_n = 1'b0;

        if ((al_adjust_n != 2'd0) && (nxt_op != A_ADD) && (nxt_op != A_SUB)) begin
            case (al_adjtmp_n)
                2'd0: tmpa_n = tmpa_n & ((al_adjust_n == 2'd2) ? 16'h000F : 16'h00FF);
                2'd1: tmpb_n = tmpb_n & ((al_adjust_n == 2'd2) ? 16'h000F : 16'h00FF);
                default: tmpc_n = tmpc_n & ((al_adjust_n == 2'd2) ? 16'h000F : 16'h00FF);
            endcase
            al_adjust_n = 2'd0;
        end

        case (r_alutmp)
            2'd0: tsel_n = tmpa_n;
            2'd1: tsel_n = tmpb_n;
            2'd2: tsel_n = tmpc_n;
            default: tsel_n = 16'd0;
        endcase
        if (r_aluop == A_BIT)
            bit_n_n = tsel_n[3:0] & (op8_n ? 4'd7 : 4'd15);
        if (r_aluop == A_ABS)
            sign_neg_n = op8_n ? tsel_n[7] : tsel_n[15];
    end else if (e_type == TY_JMP) begin
        `include "v30u_eu_cond.svh"
        if (taken) begin
            nloc  = r_loc;
            carry = 1'b0;

            if ((r_loc + 4'd1) != upc_loc_n) bubble = 1'b1;
        end
    end else begin

        if (e_farjmp) begin
            upc_page_n = 3'd7;
            upc_opc_n  = {r_farloc, 3'd0};
            nloc  = 4'd0;
            carry = 1'b0;
            bubble = 1'b1;
        end else begin
            case (e_ictl)
                I_MFS:     mode8080_n = 1'b0;
                I_MFC:     mode8080_n = 1'b1;
                I_ENDEM:   mode8080_n = 1'b0;
                I_CITF:    begin psw_n[FIE] = 1'b0; psw_n[FBRK] = 1'b0; end
                I_CLRCYV:  begin psw_n[FCY] = 1'b0; psw_n[FV] = 1'b0; end
                I_SETCYV:  begin psw_n[FCY] = 1'b1; psw_n[FV] = 1'b1; end
                I_SIGNTGL: sign_neg_n = sign_neg_n ^ (op8_n ? tmpb_n[7] : tmpb_n[15]);
                I_BCDINIT: begin psw_n[FCY] = 1'b0; sign_neg_n = 1'b1; end
                I_BCDNZ:   if (!stat_n[FZ]) sign_neg_n = 1'b0;
                default: ;
            endcase
            psw_n = (psw_n & PSW_WRITABLE) | PSW_FORCED;
        end

        if (e_ectl == E_INTATAIL) bus_word_n = 1'b1;

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
        if (row_bus) begin
            if (row_is_wr || row_is_wb) begin
                pend_active_n = 1'b1;
                pend_off_n  = acc_off_nog;
                pend_seg_n  = acc_seg;
                pend_byte_n = acc_byte;
                pend_io_n   = acc_io;

                if (acc_split_wr) wr_out_n = (wr_out_n >= 2'd2) ? 2'd3
                                                         : wr_out_n + 2'd2;
                else if (wr_out_n != 2'd3) wr_out_n = wr_out_n + 2'd1;
            end else begin

                if (rd_pending_n == 2'd0)
                    rdp0_byte_n = row_is_inta ? 1'b1 : acc_byte;
                else if (rd_pending_n == 2'd1)
                    rdp1_byte_n = row_is_inta ? 1'b1 : acc_byte;
                if (rd_pending_n != 2'd3) rd_pending_n = rd_pending_n + 2'd1;

                if (ghost_read_stale_alu && (rd_pending_n == 2'd1))
                    ghost_rd_discard_n = 1'b1;
            end
        end
    end

    if (pend_active_n && opr_fresh_n) begin
        pend_active_n = 1'b0;
        opr_fresh_n   = 1'b0;
    end

    if (!e_is_rloop || (count_n == 16'd0)) begin
        upc_loc_n = nloc;
        if (carry) upc_opc_n = upc_opc_n + 8'd1;
    end
    rowq_n = 2'd0; row_posted_n = 1'b0; row_paired_n = 1'b0;

    if (e_is_rloop) begin

        if (count_n == 16'd0) begin
            al_spent_n = 1'b1;
            st_n = S_ROW;
        end else begin
            rloop_n_n = count_n;
            st_n = S_RLOOP;
        end
        stop = 1'b1;
    end else if (e_e || ext4s_early_e) begin

        retire_now = retire_ok_e;

        if (bnd_fire) begin
            irq_sel_nmi_n = irq_nmi_lvl;
            irq_sel_brk_n = !irq_take;
            brk_arm_n = brk_arm_n && irq_take;
            poste_n = 1'b1; pe_opc_reg_n = opc_reg_n; pe_opc8080_n = opc8080_n;
            pe_op8_n = op8_n; pe_pfxcnt_n = pfxcnt_n;
            st_n = S_IRQ_D;
            stop = 1'b1;
        end else if (!pend_after && !opc_valid_n && retire_now && q_ripe &&
                     !row_flush)
        begin

            irq_shadow_n = 1'b0;
            opc_byte_n = q_byte;
            opc_valid_n = 1'b1;
            pop_is_first_n = 1'b0;
            poste_n = 1'b1; pe_opc_reg_n = opc_reg_n; pe_opc8080_n = opc8080_n;
            pe_op8_n = op8_n; pe_pfxcnt_n = pfxcnt_n;
            st_n = S_TAIL;
        end else if (!pend_after && !opc_valid_n) begin
            st_n = S_EPOP;
            stop = 1'b1;
        end else begin
            poste_n = 1'b1; pe_opc_reg_n = opc_reg_n; pe_opc8080_n = opc8080_n;
            pe_op8_n = op8_n; pe_pfxcnt_n = pfxcnt_n;
            st_n = S_TAIL;
        end
    end else begin
        st_n = bubble ? S_ROW_CHG : S_ROW;
        stop = 1'b1;
    end
end
