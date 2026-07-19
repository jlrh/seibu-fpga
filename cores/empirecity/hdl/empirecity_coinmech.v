/*  Empire City: 1931 (Seibu, 1986) — CONFORMADOR DE PULSO DE MONEDA ("coin mech").

    POR QUÉ EXISTE ESTE MÓDULO (bug del coin en placa, resuelto 2026-07-17):
    En el mueble la moneda NO es un botón: es el micro del mecanismo, que cierra ~50-100 ms mientras la
    moneda cae. El firmware del 68705 MIDE ESA ANCHURA (cuenta en su bucle de sondeo mientras la línea
    está baja) y decide AL SOLTARLA:
      · pulso corto -> `bclr 0,$02` + `bset 0,$02` (0x199) = MONEDA VÁLIDA -> coin_valid al main.
      · línea baja demasiado tiempo (contador > 0x05D0; ~0.355 s MEDIDOS en MAME) -> "stuck coin":
            214: bclr 3,$02   ; NMI al main
            216: bset 3,$02
            218: bra  $218    ; ⭐ BUCLE INFINITO — EL MCU NO VUELVE JAMÁS (anti-tamper del mecanismo)
    En MiSTer el coin es un BOTÓN que el usuario mantiene cuanto quiere -> disparaba el anti-tamper, y al
    quedarse el MCU colgado PARA SIEMPRE, ya no entraba ninguna moneda más ni sonaban las voces ADPCM
    hasta el reset. Síntoma en placa: "responde solo a veces, y la mayoría de las veces no" + "si lo dejo
    pulsado, rápidamente da un ERROR". El RTL del handshake estaba BIEN (sim == golden, eslabón a eslabón).

    QUÉ HACE: reproduce el MECANISMO, no el botón. Cada pulsación, POR LARGA QUE SEA, produce UN pulso
    activo-bajo de anchura fija (WIDTH), y hay que SOLTAR para volver a armar (sin auto-repeat).

    VERIFICADO contra el oráculo (MAME 0.288, empcityu): acepta 0.10 s y 0.25 s; a 0.355 s se cuelga.
    133 ms es la anchura con la que la sim reproduce el golden byte a byte. Ver debug/empirecity/coin/.
    GPLv3 — crédito a jotego/JTFRAME. */
module empirecity_coinmech #( parameter W = 19, parameter [W-1:0] WIDTH = 19'd399000 )(  // 133 ms @3 MHz
    input            rst,
    input            clk,
    input            cen,        // cen3 (3 MHz)
    input      [1:0] coin_btn,   // botón de jtframe, ACTIVO-BAJO
    output     [1:0] coin_mech   // al MCU, ACTIVO-BAJO: pulso de WIDTH por pulsación
);

genvar gi;
generate
    for( gi=0; gi<2; gi=gi+1 ) begin : gen_mech
        reg [W-1:0] cnt;
        reg         act, arm, btn_l;
        always @(posedge clk or posedge rst) begin
            if( rst ) begin
                cnt <= {W{1'b0}}; act <= 1'b0; arm <= 1'b1; btn_l <= 1'b1;
            end else if( cen ) begin
                btn_l <= coin_btn[gi];
                if( arm && btn_l && !coin_btn[gi] ) begin   // flanco de bajada -> dispara el mecanismo
                    act <= 1'b1; arm <= 1'b0; cnt <= WIDTH;
                end else if( act ) begin
                    if( cnt!={W{1'b0}} ) cnt <= cnt-1'd1; else act <= 1'b0;
                end
                if( !act && coin_btn[gi] ) arm <= 1'b1;     // re-arma SOLO al soltar (no auto-repeat)
            end
        end
        assign coin_mech[gi] = ~act;                        // 0 mientras dura el pulso
    end
endgenerate

endmodule
