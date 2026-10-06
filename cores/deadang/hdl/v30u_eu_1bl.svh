begin

if (!(poste_n &&
      ((pla3_xop(ld_pla_n) == PLA3_BL1_SET_CY) ||
       (pla3_xop(ld_pla_n) == PLA3_BL1_CLR_CY) ||
       (pla3_xop(ld_pla_n) == PLA3_BL1_NOT_CY)))) begin
`ifndef SYNTHESIS
    trc_1bl_pre = psw_n; trc_1bl_hit = 1'b1;
`endif
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
    psw_n = (psw_n & PSW_WRITABLE) | PSW_FORCED;
`ifndef SYNTHESIS
    trc_1bl_post = psw_n;
`endif
end
end
