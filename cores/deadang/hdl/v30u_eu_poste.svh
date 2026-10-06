begin
    if (e_have1) begin
        v1  = s1_val;

        wb1 = s1_wbyte;
        bsw = (e_s1 == 5'd23);
        if (e_s1 == 5'd6) opr_fresh_n = 1'b0;
        if (e_s1 == 5'd20) begin
            if (sig_mask != 16'd0)
                stat_n = (stat_n & ~sig_mask) | (sig_flags & sig_mask);
        end
        if (!((e_s1 == 5'd20) && !sig_commits) &&
            !(ext4s_early_post && ext4s_arch_d1)) begin
            `include "v30u_eu_wd1.svh"
        end
    end
    if (e_have2) begin
        v2  = s2_val;
        wb2 = s2_wbyte;
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
    if (e_w && (sig_mask != 16'd0)) commit_flags(sig_mask, sig_flags);

    if (e_type == TY_ALU) begin
        al_adjust_n  = (al_op_n == A_ADJD) ? 2'd1 : (al_op_n == A_ADJA) ? 2'd2 : 2'd0;
        al_adjtmp_n  = al_tmp_n;
        al_bitarm_n  = (al_op_n == A_BIT);
        al_bitn_n    = bit_n_n;
        al_spent_n   = 1'b0;
        al_op_n      = r_aluop;
        al_tmp_n     = r_alutmp;
        al_eaconst_n = 1'b0;
    end else if (e_type == TY_CTL && !e_farjmp) begin
        case (e_ictl)
            4'd3:  mode8080_n = 1'b0;
            4'd2:  mode8080_n = 1'b1;
            4'd0:  mode8080_n = 1'b0;
            4'd1:  begin psw_n[FIE] = 1'b0; psw_n[FBRK] = 1'b0; end
            4'd6:  begin psw_n[FCY] = 1'b0; psw_n[FV] = 1'b0; end
            4'd7:  begin psw_n[FCY] = 1'b1; psw_n[FV] = 1'b1; end
            4'd12: sign_neg_n = sign_neg_n ^ (op8_eff ? tmpb_n[7] : tmpb_n[15]);
            4'd4:  begin psw_n[FCY] = 1'b0; sign_neg_n = 1'b1; end
            4'd13: if (!stat_n[FZ]) sign_neg_n = 1'b0;
            default: ;
        endcase
        psw_n = (psw_n & PSW_WRITABLE) | PSW_FORCED;
    end

    if (st_n == S_1BL_CHG) begin
        case (pla3_xop(ld_pla_n))
            PLA3_BL1_SET_DIR: psw_n[FDIR] = 1'b1;
            PLA3_BL1_CLR_DIR: psw_n[FDIR] = 1'b0;
            PLA3_BL1_SET_IE:  psw_n[FIE]  = 1'b1;
            PLA3_BL1_CLR_IE:  psw_n[FIE]  = 1'b0;
            PLA3_BL1_SET_CY:  psw_n[FCY]  = 1'b1;
            PLA3_BL1_CLR_CY:  psw_n[FCY]  = 1'b0;

            PLA3_BL1_NOT_CY:  psw_n[FCY]  = ~psw_n[FCY];
            default: ;
        endcase
    end
`ifndef SYNTHESIS
    if (row_bus)
        $error("v30u_eu: a post-E row carries a bus cycle (upc %0d.%02X.%0d)",
               upc_page_n, upc_opc_n, upc_loc_n);
    if (row_q1 || row_q2)
        $error("v30u_eu: a post-E row pops a queue byte");
`endif
end
