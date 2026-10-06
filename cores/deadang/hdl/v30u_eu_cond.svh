case (r_cond)
    C_C:      taken = stat_n[FCY];
    C_NC:     taken = !stat_n[FCY];
    C_Z:      taken = stat_n[FZ];
    C_NZ:     taken = !stat_n[FZ];
    C_OP8B:   taken = op8_n;

    C_CNTZ:   begin
                  count_n = count_n - 16'd1;
                  taken = (count_n != 16'd0);
              end
    C_L:      taken = (stat_n[FS] != stat_n[FV]);
    C_OP8:    taken = imm8_n;
    C_ALWAYS: taken = 1'b1;
    C_SIGN:   taken = !sign_neg_n;
    C_O:      taken = psw_n[FV];
    C_NS:     taken = !(op8_n ? tmpb_n[7] : tmpb_n[15]);
    C_REP:    begin
                  count_n = count_n - 16'd1;

                  rep_chained = rep_chain_n;
                  rep_chain_n = 1'b1;
                  if (count_n == 16'd0) taken = 1'b0;
                  else begin
                      if (rep_test_n == TEST_Z)
                          taken = (psw_n[FZ] == rep_pol_n);
                      else if (rep_test_n == TEST_CY)
                          taken = (psw_n[FCY] == rep_pol_n);
                      else taken = 1'b1;

                      if (taken && (rep_kind_n != REP_NONE) &&
                          (intr_pending_n ||
                           (rep_chained ? irq_rep_chn : irq_rep_1st))) begin
                          intr_pending_n = 1'b1;
                          taken = 1'b0;

                          if (rep_chained) bubble = 1'b1;
                      end

                      else if (taken && brk_take &&
                               (rep_kind_n != REP_NONE)) begin
                          intr_pending_n = 1'b1;
                          taken = 1'b0;
                          bubble = 1'b1;
                      end
                  end
              end
    C_BUSY:   taken = poll_busy;
    C_INTR:   taken = intr_pending_n;
    default:  begin
                  case (opc_reg_n[3:0])
                      4'h0: taken = psw_n[FV];
                      4'h1: taken = !psw_n[FV];
                      4'h2: taken = psw_n[FCY];
                      4'h3: taken = !psw_n[FCY];
                      4'h4: taken = psw_n[FZ];
                      4'h5: taken = !psw_n[FZ];
                      4'h6: taken = psw_n[FCY] || psw_n[FZ];
                      4'h7: taken = !psw_n[FCY] && !psw_n[FZ];
                      4'h8: taken = psw_n[FS];
                      4'h9: taken = !psw_n[FS];
                      4'hA: taken = psw_n[FP];
                      4'hB: taken = !psw_n[FP];
                      4'hC: taken = (psw_n[FS] != psw_n[FV]);
                      4'hD: taken = (psw_n[FS] == psw_n[FV]);
                      4'hE: taken = psw_n[FZ] || (psw_n[FS] != psw_n[FV]);
                      default: taken = !psw_n[FZ] && (psw_n[FS] == psw_n[FV]);
                  endcase
              end
endcase
