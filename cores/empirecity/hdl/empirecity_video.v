// empirecity_video.v — vídeo Seibu de Empire City (Fase 2c.3): módulo con PUERTOS DE GAME TOP.
// Porta la lógica validada de empirecity_video_scan2.v (bg/fg/sprites por fetch SDRAM DW32,
// prefetch por línea + doble line-buffer + handshake issue/wait) y añade:
//   * RAMs de vídeo internas (txram/sprram/vregs/paleta) con puerto de escritura de CPU.
//   * tx gfx + 4 CLUTs en BRAM (bajo sim: precarga hex; en HW: prom_we/prog_addr).
//   * colmix: paleta xBRG_444 -> RGB de 4 bits/canal (JTFRAME_COLORW=4).
// Buses SDRAM = PUERTOS (los sirve el game top / un wrapper de sim con modelo SDRAM).
// GPLv3 — crédito a Jose Tejada (jotego) / JTFRAME.
`timescale 1ns/1ps
module empirecity_video(
    input             rst,
    input             clk,
    input             pxl2_cen,
    input             pxl_cen,
    output            LHBL,
    output            LVBL,
    output            HS,
    output            VS,
    input             flip,
    // interfaz CPU (RAMs de vídeo)
    input      [12:0] cpu_addr,
    input      [ 7:0] cpu_dout,
    input             cpu_rnw,
    input             vram_cs,
    output     [ 7:0] vram_dout,
    input             pal_cs,
    output     [ 7:0] pal_dout,
    input             vreg_cs,
    output     [ 7:0] vreg_dout,
    input             spr_cs,
    output     [ 7:0] spr_dout,
    input      [ 9:0] sprbank,     // base de sprites (0xc807, del main). En sim NOMAIN se usa la precarga.
    // SDRAM gfx (mapas 8-bit + gfx 32-bit)
    output     [15:0] fgmap_addr, output fgmap_cs, input [ 7:0] fgmap_data, input fgmap_ok,
    output     [15:0] bgmap_addr, output bgmap_cs, input [ 7:0] bgmap_data, input bgmap_ok,
    output     [16:2] fgrom_addr, output fgrom_cs, input [31:0] fgrom_data, input fgrom_ok,
    output     [16:2] bgrom_addr, output bgrom_cs, input [31:0] bgrom_data, input bgrom_ok,
    output     [16:2] objrom_addr,output objrom_cs,input [31:0] objrom_data,input objrom_ok,
    // salida de color
    output     [ 3:0] red,
    output     [ 3:0] green,
    output     [ 3:0] blue,
    input      [ 7:0] gfx_en,
    // carga de PROMs (tx gfx + 4 CLUTs) desde el download de jtframe (prom_we + prog_addr)
    input      [21:0] prog_addr,
    input      [ 7:0] prog_data,
    input             prom_we
);
    // ============================ RAMs de vídeo (CPU) ============================
    // ⭐ txram = instancia jtframe_dual_ram (u_txram, abajo): puerto0=CPU (RW), puerto1=prefetch tx (RO).
    // Era un array leído combinacionalmente por CPU (vram_dout) y 2 veces por el prefetch = 16K FF.
    // Un comentario previo afirmaba que "NO puede ser BRAM porque tiene el read-back asíncrono de CPU":
    // FALSO — es exactamente el caso que u_sprram ya resolvió. El read-back registrado lo absorbe el
    // cen3 del Z80 (1/16 de clk) y el prefetch serializa sus 2 lecturas con estados pedir/latchear.
    // ⭐ sprram = instancia jtframe_dual_ram (u_sprram, abajo): puerto0=CPU (RW), puerto1=vídeo (RO).
    // Era un array con lectura combinacional por CPU (spr_dout) Y por el scanner (4 lecturas en 1 estado)
    // = ~32K FF. Canónico (SINTESIS-READINESS §4/§7): el scanner serializa con estados pedir/latchear y
    // el read-back de CPU sale registrado (lo absorbe cen3 = 1/16 de clk -> sin wait-states).
    reg [7:0] vregs [0:15];
    reg [7:0] pal_lo[0:255];
    reg [7:0] pal_hi[0:255];
    // ============================ BRAM de gfx tx + CLUTs ============================
    // ⭐ txgfx = instancia jtframe_prom (u_txgfx, abajo), NO un array local. Es el patrón canónico
    // (SINTESIS-READINESS §4/§5): lectura REGISTRADA + INCONDICIONAL en el MISMO `always` que la
    // escritura + (* ramstyle="no_rw_check" *) -> infiere M10K. Antes era un array leído
    // combinacionalmente en pentx() = mux de 8192 -> ~65K FF, el peor ofensor de la síntesis (§E4).
    // ⭐ Las 4 CLUTs = instancias jtframe_prom (u_txclut/u_fgclut/u_bgclut/u_sprclut, abajo).
    // Eran arrays con lectura combinacional en el pixel stage: 4 muxes de 256 = ~8K FF.
    // NO hizo falta pipelinear el pixel stage (que era lo que se temía): cada CLUT se indexa desde
    // la salida de un line buffer, que sigue a lb_ra y por tanto es ESTABLE durante los 8 clk del
    // píxel -> la lectura registrada se asienta de sobra antes del pxl_cen que la consume. Es el
    // mismo argumento que ya validaron los line buffers (SINTESIS-READINESS §9).
    reg [15:0] sprite_base;

`ifdef EMPIRECITY_PRELOAD
    // video_tb: RAMs de escena + PROMs desde DATADIR.
    initial begin
        // txram/sprram -> los cargan u_txram/u_sprram por su parámetro SIMHEXFILE
        $readmemh({`DATADIR,"/vregs.hex"},  vregs);   $readmemh({`DATADIR,"/pal_lo.hex"}, pal_lo);
        $readmemh({`DATADIR,"/pal_hi.hex"}, pal_hi);  // txgfx + las 4 CLUTs: por su parámetro SIMHEX
        sprite_base = `SPRITE_BASE;
    end
`else
  // PROMs (tx gfx + 4 CLUTs) = device ROM. NO se precargan por hex: se cargan del DOWNLOAD de jtframe
  // (bloque u_prom_load abajo), igual en boot-sim y en HW. Así el boot-sim valida el mismo camino que HW.
  `ifdef NOMAIN
    // jtsim SÓLO-VÍDEO: sin CPU, precarga la RAM de la escena + sprite_base (empirecity_jtsim_prep.py).
    reg [15:0] sprbase_ini [0:0];
    initial begin
        // txram/sprram -> u_txram/u_sprram (SIMHEXFILE)
        $readmemh("vregs.hex",  vregs);   $readmemh("pal_lo.hex", pal_lo);  $readmemh("pal_hi.hex", pal_hi);
        $readmemh("sprbase.hex",sprbase_ini); sprite_base = sprbase_ini[0];
        // vídeo-solo: sin download de jtframe -> PROMs por hex (como en 2c.3b), vía SIMHEX de
        // u_txgfx y de las 4 CLUTs (u_txclut/u_fgclut/u_bgclut/u_sprclut).
    end
  `else
    // BOOT REAL: la CPU genera la RAM de vídeo; sprite_base = sprbank (0xc807).
    always @(posedge clk) if(rst) sprite_base <= 16'd0; else sprite_base <= {6'd0, sprbank};
  `endif
`endif

    // ---- escritura de CPU en las RAMs de vídeo ----
    always @(posedge clk) begin
        // txram: la escritura de CPU va por el puerto 0 de u_txram (abajo), no aquí.
        // sprram: la escritura de CPU va por el puerto 0 de u_sprram (abajo), no aquí.
        if (vreg_cs && !cpu_rnw) vregs [cpu_addr[3:0]]  <= cpu_dout;   // d800-d808
        if (pal_cs  && !cpu_rnw) begin                                 // c000-c1ff (256x2)
            if (cpu_addr[8]) pal_hi[cpu_addr[7:0]] <= cpu_dout;
            else             pal_lo[cpu_addr[7:0]] <= cpu_dout;
        end
    end
    assign pal_dout  = cpu_addr[8] ? pal_hi[cpu_addr[7:0]] : pal_lo[cpu_addr[7:0]];

    // ---- txram: BRAM canónica (jtframe_dual_ram). P0 = CPU (RW), P1 = prefetch de texto (RO) ----
    // El read-back de CPU (vram_dout = q0) sale REGISTRADO: 1 ciclo, invisible bajo cen3 (1/16 de clk).
    // ⚠ §E7: mismo riesgo read-during-write que u_sprram (aceptado, igual que en los cores de ref).
    reg  [10:0] tx_ra;       // dirección de lectura del prefetch
    wire [ 7:0] tx_rq;       // dato (válido 1 ciclo después de que la RAM vea tx_ra)
`ifdef EMPIRECITY_PRELOAD
    localparam TXRAM_HEX = {`DATADIR,"/txram.hex"};
`elsif NOMAIN
    localparam TXRAM_HEX = "txram.hex";
`else
    localparam TXRAM_HEX = "";      // boot real / HW: la llena la CPU
`endif
    jtframe_dual_ram #(.DW(8), .AW(11), .SIMHEXFILE(TXRAM_HEX)) u_txram(
        // Puerto 0 — CPU (d000-d7ff, 2KB)
        .clk0 ( clk                    ), .data0( cpu_dout ), .addr0( cpu_addr[10:0] ),
        .we0  ( vram_cs & ~cpu_rnw     ), .q0   ( vram_dout ),
        // Puerto 1 — vídeo (prefetch de la capa de texto, solo lectura)
        .clk1 ( clk                    ), .data1( 8'd0     ), .addr1( tx_ra          ),
        .we1  ( 1'b0                   ), .q1   ( tx_rq    )
    );
    // ---- sprram: BRAM canónica (jtframe_dual_ram). P0 = CPU (RW), P1 = scanner de sprites (RO) ----
    // El read-back de CPU (spr_dout = q0) sale REGISTRADO: 1 ciclo, invisible bajo cen3 (1/16 de clk).
    // ⚠ §E7: si CPU y vídeo tocan la MISMA celda el MISMO flanco, en la M10K real el lector ve basura
    // (Verilator da read-before-write y NO lo reproduce). Riesgo aceptado, igual que en los cores de ref.
    reg  [11:0] spr_va;      // dirección de lectura del scanner
    wire [ 7:0] spr_vq;      // dato (válido 2 ciclos después de fijar spr_va)
`ifdef EMPIRECITY_PRELOAD
    localparam SPRRAM_HEX = {`DATADIR,"/sprram.hex"};
`elsif NOMAIN
    localparam SPRRAM_HEX = "sprram.hex";
`else
    localparam SPRRAM_HEX = "";      // boot real / HW: la llena la CPU
`endif
    jtframe_dual_ram #(.DW(8), .AW(12), .SIMHEXFILE(SPRRAM_HEX)) u_sprram(
        // Puerto 0 — CPU (f000-ffff, 4KB)
        .clk0 ( clk                    ), .data0( cpu_dout ), .addr0( cpu_addr[11:0] ),
        .we0  ( spr_cs & ~cpu_rnw      ), .q0   ( spr_dout ),
        // Puerto 1 — vídeo (scanner de sprites, solo lectura)
        .clk1 ( clk                    ), .data1( 8'd0     ), .addr1( spr_va         ),
        .we1  ( 1'b0                   ), .q1   ( spr_vq   )
    );
    assign vreg_dout = vregs[cpu_addr[3:0]];     // read-back vregs (0xd800-)

    // ---- carga de PROMs (tx gfx + 4 CLUTs) desde el DOWNLOAD de jtframe ----
    // La CPU no las toca; son device ROM. jtframe las vuelca tras JTFRAME_PROM_START con prom_we alto.
    // Offsets ABSOLUTOS = los mismos que usa el wrapper generado (u_range_txrom/txclut/... OFFSET):
    //   txgfx@+0x800 (0x2000), txclut@+0x2800, fgclut@+0x2900, bgclut@+0x2A00, sprclut@+0x2B00 (0x100 c/u).
    // Se mantienen los ARRAYS INTERNOS con lectura combinacional (lógica de pixel INTACTA -> pixel-exacta);
    // solo cambia la FUENTE de carga (antes $readmemh de sim; ahora el download, válido en boot-sim y HW).
    // Bajo EMPIRECITY_PRELOAD (video_tb) no hay download: los arrays se cargan por $readmemh (arriba).
    // Ya NO se escribe ninguna CLUT aquí: el download va por los puertos we/wr_addr de cada
    // instancia jtframe_prom (u_txgfx y las 4 CLUTs, abajo). Los offsets son los mismos.

    // ============================ timing ============================
    // Contadores propios (validados vs golden en scan2). LHBL/LVBL activos-bajos.
    // ⚠ Fase 2c.3b: alinear con jtframe_vtimer/visarea real (224 líneas) para la captura de jtsim.
    localparam HTOTAL=384, VTOTAL=264, HVISIBLE=256, VVISIBLE=256;
    integer hcnt, vcnt;
    reg     hb, vb, hs_r, vs_r;
    integer fg_x,fg_y,bg_x,bg_y,en;
    assign LHBL = ~hb; assign LVBL = ~vb; assign HS = hs_r; assign VS = vs_r;

    // ============================ line buffers ============================
    // ⭐ LINE BUFFERS = instancias jtframe_rpwp_ram (1W/1R, lectura REGISTRADA + no_rw_check).
    // Eran arrays leídos COMBINACIONALMENTE en el pixel stage: 4 muxes de 512:1 = el grueso de los
    // 31.813 ALMs (76%) que MIDIÓ el syncheck. WRally2 midió ~25K comb ALUTs por UN line buffer
    // async; registrado = 0 ALMs. El +1 clk se asienta DENTRO del periodo de píxel (8 clk por
    // pxl_cen, lb_ra estable) -> NO desplaza el pixel. rpwp y no dual_ram: su propia cabecera avisa
    // de que dual_ram NO infiere MLAB en buffers pequeños. Ver SINTESIS-READINESS §9.
    // txbuf = capa de texto prefetcheada por línea: {tcolor[3:0], tpen[1:0]} ya resueltos.
    wire [8:0] bg_q, fg_q;
    wire [9:0] sb_q;
    wire [5:0] tx_q;
    reg  [8:0] bg_wa, bg_din, fg_wa, fg_din;  reg bg_we, fg_we;
    reg  [8:0] sb_wa;  reg [9:0] sb_din;      reg sb_we;
    reg  [8:0] tx_wa;  reg [5:0] tx_din;      reg tx_we;
    // dirección de lectura: sigue a hcnt/vcnt, que solo cambian en pxl_cen -> estable 8 clk,
    // así la salida registrada YA es válida en el pxl_cen en que el pixel stage la consume.
    wire [8:0] lb_ra = { vcnt[0], hcnt[7:0] };

    jtframe_rpwp_ram #(.DW(9), .AW(9)) u_bgbuf(
        .clk(clk), .rd_addr(lb_ra), .dout(bg_q), .wr_addr(bg_wa), .din(bg_din), .we(bg_we) );
    jtframe_rpwp_ram #(.DW(9), .AW(9)) u_fgbuf(
        .clk(clk), .rd_addr(lb_ra), .dout(fg_q), .wr_addr(fg_wa), .din(fg_din), .we(fg_we) );
    jtframe_rpwp_ram #(.DW(10),.AW(9)) u_sbuf(
        .clk(clk), .rd_addr(lb_ra), .dout(sb_q), .wr_addr(sb_wa), .din(sb_din), .we(sb_we) );
    jtframe_rpwp_ram #(.DW(6), .AW(9)) u_txbuf(
        .clk(clk), .rd_addr(lb_ra), .dout(tx_q), .wr_addr(tx_wa), .din(tx_din), .we(tx_we) );
    // ---- txgfx: BRAM canónica (jtframe_prom, ASYNC=0 = lectura registrada) ----
    // txgfx no tiene puerto de CPU -> se convierte a BRAM sin tocar el bus del Z80.
    // La FSM de prefetch de texto (abajo) ya presenta txg_addr y consume txg_q con 1 ciclo de latencia.
    // SIMHEX/we por ruta: fold TB y NOMAIN cargan por hex; el boot real y HW, por el download de jtframe.
    reg  [12:0] txg_addr;
    wire [ 7:0] txg_q;
`ifdef EMPIRECITY_PRELOAD
    localparam TXGFX_HEX = {`DATADIR,"/txgfx.hex"};
    wire        txgfx_we = 1'b0;
    wire [12:0] txgfx_wa = 13'd0;
`elsif NOMAIN
    localparam TXGFX_HEX = "txgfx.hex";
    wire        txgfx_we = 1'b0;
    wire [12:0] txgfx_wa = 13'd0;
`else
    localparam TXGFX_HEX = "";      // boot real / HW: lo llena el download
    wire        txgfx_we = prom_we && prog_addr>=(`JTFRAME_PROM_START + 22'h0800)
                                   && prog_addr< (`JTFRAME_PROM_START + 22'h2800);
    wire [12:0] txgfx_wa = (prog_addr - (`JTFRAME_PROM_START + 22'h0800)) & 22'h1fff;
`endif
    jtframe_prom #(.DW(8), .AW(13), .SIMHEX(TXGFX_HEX)) u_txgfx(
        .clk     ( clk       ),
        .cen     ( 1'b1      ),
        .data    ( prog_data ),
        .wr_addr ( txgfx_wa  ),
        .we      ( txgfx_we  ),
        .rd_addr ( txg_addr  ),
        .q       ( txg_q     )
    );

    // ---- las CLUTs: BRAM canónica (jtframe_prom, lectura registrada) ----
    // Direcciones de lectura: COMBINACIONALES desde las salidas (ya registradas) de los line buffers.
    // lb_ra sigue a hcnt -> bg_q/fg_q/sb_q/tx_q estables durante los 8 clk del píxel -> la q registrada
    // de la CLUT está válida mucho antes del pxl_cen que la consume. NO desplaza el píxel (verificado:
    // fold TB 0.0000% x4 escenas). sp_idx = {sp[7:4],sp[3:0]} == sp[7:0]; tcolor*4+tpen == tx_q[5:0].
    //
    // ⭐ NIBBLES: en el HW real fg/bg/spr_clut son DOS PROMs 82s129 de 256x4 (dato en el nibble BAJO).
    // Aquí se cargan CRUDAS (= lo que hay en el zip / lo que el .mra puede entregar) y se combinan
    // `{hi[3:0], lo[3:0]}`, igual que hace MAME al cargar (ROM_LOAD_NIB_HIGH/LOW) y que el HW real.
    // ⚠ ANTES se cargaban las 4 CLUTs YA FUNDIDAS por MAME: **la placa NO puede recibir eso** (un .mra
    // no combina nibbles) -> era la misma clase de bug que el cifrado del main. Ver HANDOFF §6-B.
    // Combinación verificada byte-exacta contra los volcados de MAME (fg/bg/spr: IDENTICO).
    // tx_clut NO lleva nibbles: es 1 PROM con el byte entero (ROM_LOAD, no NIB_*).
    wire [7:0] txclut_q;
    wire [7:0] fgclut_hi_q, fgclut_lo_q, bgclut_hi_q, bgclut_lo_q, sprclut_hi_q, sprclut_lo_q;
    wire [7:0] fgclut_q  = { fgclut_hi_q[3:0],  fgclut_lo_q[3:0]  };
    wire [7:0] bgclut_q  = { bgclut_hi_q[3:0],  bgclut_lo_q[3:0]  };
    wire [7:0] sprclut_q = { sprclut_hi_q[3:0], sprclut_lo_q[3:0] };
    wire [7:0] bgclut_a  = bg_q[7:0];
    wire [7:0] fgclut_a  = fg_q[7:0];
    wire [7:0] sprclut_a = sb_q[7:0];
    wire [7:0] txclut_a  = { 2'd0, tx_q[5:0] };

    // Offsets del download = el ORDEN de las PROMs en cfg/mem.yaml (mcu 0x800 + txrom 0x2000 delante).
    // Bajo PRELOAD/NOMAIN se cargan por SIMHEX (mismos nombres que escriben los builders).
`ifdef EMPIRECITY_PRELOAD
    `define EC_CLUT_HEX(n) {`DATADIR,"/",n,".hex"}
    `define EC_CLUT_WE(off)  1'b0
    `define EC_CLUT_WA(off)  8'd0
`elsif NOMAIN
    `define EC_CLUT_HEX(n) {n,".hex"}
    `define EC_CLUT_WE(off)  1'b0
    `define EC_CLUT_WA(off)  8'd0
`else
    `define EC_CLUT_HEX(n) ""
    `define EC_CLUT_WE(off)  (prom_we && prog_addr>=(`JTFRAME_PROM_START+off) \
                                      && prog_addr< (`JTFRAME_PROM_START+off+22'h0100))
    `define EC_CLUT_WA(off)  ((prog_addr-(`JTFRAME_PROM_START+off)) & 22'h00ff)
`endif
// ⚠ Los nombres de los parámetros NO pueden coincidir con los de los puertos: en la expansión, un
// parámetro `q` sustituiría también al `q` de `.q(...)` -> `.bgclut_lo_q(...)` = "Pin not found".
// Por eso van con sufijo `_p`.
`define EC_CLUT(inst_p,nm_p,off_p,addr_p,q_p) \
    jtframe_prom #(.DW(8), .AW(8), .SIMHEX(`EC_CLUT_HEX(nm_p))) inst_p(       \
        .clk(clk), .cen(1'b1), .data(prog_data),                              \
        .wr_addr(`EC_CLUT_WA(off_p)), .we(`EC_CLUT_WE(off_p)),                 \
        .rd_addr(addr_p), .q(q_p) );
    `EC_CLUT(u_txclut,     "txclut",     22'h2800, txclut_a,  txclut_q    )
    `EC_CLUT(u_fgclut_hi,  "fgclut_hi",  22'h2900, fgclut_a,  fgclut_hi_q )
    `EC_CLUT(u_fgclut_lo,  "fgclut_lo",  22'h2A00, fgclut_a,  fgclut_lo_q )
    `EC_CLUT(u_bgclut_hi,  "bgclut_hi",  22'h2B00, bgclut_a,  bgclut_hi_q )
    `EC_CLUT(u_bgclut_lo,  "bgclut_lo",  22'h2C00, bgclut_a,  bgclut_lo_q )
    `EC_CLUT(u_sprclut_hi, "sprclut_hi", 22'h2D00, sprclut_a, sprclut_hi_q)
    `EC_CLUT(u_sprclut_lo, "sprclut_lo", 22'h2E00, sprclut_a, sprclut_lo_q)

    // mappers (identicos al ref validado)
    function integer fg_scan; input integer col; input integer row;
        fg_scan=(col&15)|((row&15)<<4)|((col&'h70)<<4)|((row&'hf0)<<7); endfunction
    function integer bg_scan; input integer col; input integer row;
        bg_scan=((col&'h0e)>>1)|((row&15)<<3)|((col&'h70)<<3)|((row&'h80)<<3)
               |((row&'h10)<<7)|((col&1)<<12)|((row&'h60)<<8); endfunction
    // NOTA: la antigua `function pentx` (leía txgfx COMBINACIONALMENTE -> mux de 8192 = ~65K FF,
    // el peor ofensor de la síntesis) se ha DESPLEGADO dentro de la FSM de prefetch de texto, con
    // lectura registrada de txgfx. No debe quedar NINGUNA lectura combinacional de txgfx. §E4.

    // ============================ prefetch bg/fg (clk libre) ============================
    reg        fill_req;
    integer    fill_line, fill_buf;
    integer    fl_state, fl_layer, fl_col, fl_px;
    integer    fl_scrx, fl_scry, fl_col_src, fl_row, fl_py, fl_moff;
    integer    fl_lo, fl_attr, fl_code, fl_color, fl_gsel, fl_bank, fl_baseW, fl_lane;
    reg [31:0] W0,W1,W2,W3;
    integer    fl_wsel;
    reg        fl_busy, fill_req_d;
    reg        decl_transp; reg [7:0] decl_idx; integer decl_sx;
    // salidas de bus bg/fg (registradas)
    reg [15:0] fgmap_addr_r, bgmap_addr_r; reg fgmap_cs_r, bgmap_cs_r;
    reg [16:0] fgrom_addr_r, bgrom_addr_r; reg fgrom_cs_r, bgrom_cs_r;
    assign fgmap_addr=fgmap_addr_r; assign bgmap_addr=bgmap_addr_r;
    assign fgmap_cs=fgmap_cs_r;     assign bgmap_cs=bgmap_cs_r;
    assign fgrom_addr=fgrom_addr_r[14:0]; assign bgrom_addr=bgrom_addr_r[14:0];
    assign fgrom_cs=fgrom_cs_r;     assign bgrom_cs=bgrom_cs_r;

    always @(posedge clk) begin
        if (rst) begin
            fl_state<=0; fl_busy<=0; fill_req_d<=0;
            fgmap_cs_r<=0; bgmap_cs_r<=0; fgrom_cs_r<=0; bgrom_cs_r<=0;
            bg_we<=0; fg_we<=0;
        end else begin
            bg_we <= 1'b0; fg_we <= 1'b0;   // por defecto: sin escritura (el estado 7 lo pone a 1)
            case (fl_state)
            0: begin
                fgmap_cs_r<=0; bgmap_cs_r<=0; fgrom_cs_r<=0; bgrom_cs_r<=0;
                if (fill_req!=fill_req_d && !fl_busy) begin
                    fill_req_d<=fill_req; fl_busy<=1; fl_layer<=0; fl_col<=0; fl_state<=1;
                end
            end
            1: begin
                if (fl_layer==0) begin fl_scrx=bg_x; fl_scry=bg_y; end
                else            begin fl_scrx=fg_x; fl_scry=fg_y; end
                fl_col_src = ((fl_scrx>>4)+fl_col) & 127;
                fl_row = (((fill_line+fl_scry)&4095) >> 4);
                fl_py  = (fill_line+fl_scry) & 15;
                fl_moff = (fl_layer==0) ? bg_scan(fl_col_src,fl_row) : fg_scan(fl_col_src,fl_row);
                if (fl_layer==0) begin bgmap_addr_r <= fl_moff & 16'hffff; bgmap_cs_r<=1; end
                else            begin fgmap_addr_r <= fl_moff & 16'hffff; fgmap_cs_r<=1; end
                fl_state<=2;
            end
            2: if ((fl_layer==0)?bgmap_ok:fgmap_ok) begin
                fl_lo = (fl_layer==0)?bgmap_data:fgmap_data;
                if (fl_layer==0) bgmap_cs_r<=0; else fgmap_cs_r<=0;
                fl_state<=3;
            end
            3: begin
                if (fl_layer==0) begin bgmap_addr_r <= (16'h8000+fl_moff) & 16'hffff; bgmap_cs_r<=1; end
                else            begin fgmap_addr_r <= (16'h8000+fl_moff) & 16'hffff; fgmap_cs_r<=1; end
                fl_state<=4;
            end
            4: if ((fl_layer==0)?bgmap_ok:fgmap_ok) begin
                fl_attr = (fl_layer==0)?bgmap_data:fgmap_data;
                if (fl_layer==0) begin
                    fl_bank = (fl_attr&'h20)>>5;
                    fl_code = ((fl_attr&'h80)<<1) + fl_lo;
                    fl_color= fl_attr&7; fl_gsel=2+fl_bank;
                    fl_baseW= fl_code*32 + fl_bank*8 + (fl_py>>1);
                end else begin
                    fl_code = (((fl_attr&'h80)<<2)|((fl_attr&'h20)<<3)) + fl_lo;
                    fl_color= fl_attr&7; fl_gsel=0; fl_bank=0;
                    fl_baseW= fl_code*16 + (fl_py>>1);
                end
                fl_lane = (fl_py&1)*2;
                if (fl_layer==0) bgmap_cs_r<=0; else fgmap_cs_r<=0;
                fl_wsel<=0; fl_state<=5;
            end
            5: begin
                if (fl_layer==0) begin
                    case (fl_wsel) 0: bgrom_addr_r<=(fl_baseW      )&17'h1ffff;
                                   1: bgrom_addr_r<=(fl_baseW+16    )&17'h1ffff;
                                   2: bgrom_addr_r<=(fl_baseW+'h4000)&17'h1ffff;
                                   3: bgrom_addr_r<=(fl_baseW+'h4010)&17'h1ffff; endcase
                    bgrom_cs_r<=1;
                end else begin
                    case (fl_wsel) 0: fgrom_addr_r<=(fl_baseW      )&17'h1ffff;
                                   1: fgrom_addr_r<=(fl_baseW+8     )&17'h1ffff;
                                   2: fgrom_addr_r<=(fl_baseW+'h4000)&17'h1ffff;
                                   3: fgrom_addr_r<=(fl_baseW+'h4008)&17'h1ffff; endcase
                    fgrom_cs_r<=1;
                end
                fl_state<=6;
            end
            6: if ((fl_layer==0)?bgrom_ok:fgrom_ok) begin
                case (fl_wsel) 0:W0<=(fl_layer==0)?bgrom_data:fgrom_data;
                               1:W1<=(fl_layer==0)?bgrom_data:fgrom_data;
                               2:W2<=(fl_layer==0)?bgrom_data:fgrom_data;
                               3:W3<=(fl_layer==0)?bgrom_data:fgrom_data; endcase
                if (fl_layer==0) bgrom_cs_r<=0; else fgrom_cs_r<=0;
                if (fl_wsel==3) begin fl_px<=0; fl_state<=7; end
                else begin fl_wsel<=fl_wsel+1; fl_state<=5; end
            end
            7: begin
                begin : DEC
                    integer t, sub; reg [7:0] bA, bB; reg [3:0] pn;
                    t = fl_px & 7; sub = t & 3;
                    if (fl_px < 8) begin bA = W0[8*fl_lane +:8]; bB = W2[8*fl_lane +:8];
                                         if (t>=4) begin bA=W0[8*(fl_lane+1)+:8]; bB=W2[8*(fl_lane+1)+:8]; end
                    end else begin       bA = W1[8*fl_lane +:8]; bB = W3[8*fl_lane +:8];
                                         if (t>=4) begin bA=W1[8*(fl_lane+1)+:8]; bB=W3[8*(fl_lane+1)+:8]; end
                    end
                    if (fl_layer==0) begin
                        pn[0]=(bA>>(7-sub))&1; pn[1]=(bA>>(3-sub))&1;
                        pn[2]=(bB>>(7-sub))&1; pn[3]=(bB>>(3-sub))&1;
                    end else begin
                        pn[0]=(bA>>(3-sub))&1; pn[1]=(bA>>(7-sub))&1;
                        pn[2]=(bB>>(3-sub))&1; pn[3]=(bB>>(7-sub))&1;
                    end
                    decl_sx = fl_col*16 + fl_px - (fl_scrx & 15);
                    decl_idx = fl_color*16 + pn;
                    decl_transp = (pn==4'hf);
                    // escritura por el puerto W del line buffer (registrada: cae 1 clk después,
                    // irrelevante porque se rellena la línea SIGUIENTE)
                    if (decl_sx>=0 && decl_sx<256) begin
                        if (fl_layer==0) begin
                            bg_wa <= fill_buf*256+decl_sx; bg_din <= {decl_transp, decl_idx}; bg_we <= 1'b1;
                        end else begin
                            fg_wa <= fill_buf*256+decl_sx; fg_din <= {decl_transp, decl_idx}; fg_we <= 1'b1;
                        end
                    end
                end
                if (fl_px==15) begin
                    if (fl_col==16) begin
                        if (fl_layer==1) begin fl_busy<=0; fl_state<=0; end
                        else begin fl_layer<=1; fl_col<=0; fl_state<=1; end
                    end else begin fl_col<=fl_col+1; fl_state<=1; end
                end else fl_px<=fl_px+1;
            end
            endcase
        end
    end

    // ============================ sprite engine (clk libre) ============================
    reg        sp_busy, fill_req_d2;
    integer    sp_state, sp_si, sp_xx, sp_wsel, sp_ci;
    integer    sp_ssy, sp_attr, sp_scode, sp_ssx, sp_scolor, sp_sflipx, sp_scode2, sp_syy;
    integer    sp_lane, sp_baseW;
    reg [31:0] SW0,SW1,SW2,SW3;
    reg [16:0] objrom_addr_r; reg objrom_cs_r;
    assign objrom_addr=objrom_addr_r[14:0]; assign objrom_cs=objrom_cs_r;
    always @(posedge clk) begin
        if (rst) begin sp_state<=0; sp_busy<=0; fill_req_d2<=0; objrom_cs_r<=0; sb_we<=0; end
        else begin
            sb_we <= 1'b0;   // por defecto: sin escritura (los estados 1 y 6 lo ponen a 1)
            case (sp_state)
            0: begin objrom_cs_r<=0;
                if (fill_req!=fill_req_d2 && !sp_busy) begin
                    fill_req_d2<=fill_req; sp_busy<=1; sp_ci<=0; sp_state<=1;
                end
            end
            1: begin sb_wa <= fill_buf*256+sp_ci; sb_din <= 10'h000; sb_we <= 1'b1;   // borra la línea
                if (sp_ci==255) begin sp_si<=4096-32; sp_state<=2; end else sp_ci<=sp_ci+1;
            end
            // ---- lectura del registro de sprite desde la BRAM: 1 ciclo de latencia ----
            // spr_vq es válido 2 estados después de fijar spr_va (q1 <= mem[addr1] registrada).
            // Las 4 lecturas (+2=Y, +0=code, +1=attr, +3=X) se serializan encadenando las peticiones.
            2: begin spr_va <= (sp_si+2) & 12'hfff; sp_state <= 7; end   // pide Y
            7: sp_state <= 8;                                            // burbuja de latencia
            8: begin sp_ssy = spr_vq;                                    // Y válido -> descarte rápido
                if (sp_ssy>0 && fill_line>=sp_ssy && fill_line<sp_ssy+16) begin
                    spr_va <= (sp_si+0) & 12'hfff; sp_state <= 9;        // en rango: pide code
                end else sp_state <= 5;                                  // descartado: 3 ciclos
            end
            9:  begin spr_va <= (sp_si+1) & 12'hfff; sp_state <= 10; end // pide attr
            10: begin sp_scode = spr_vq;                                 // code válido
                      spr_va <= (sp_si+3) & 12'hfff; sp_state <= 11;     // pide X
            end
            11: begin sp_attr = spr_vq; sp_state <= 12; end              // attr válido
            12: begin sp_ssx  = spr_vq;                                  // X válido -> ya está todo
                    sp_sflipx = sp_attr & 'h10;
                    sp_scolor = (sp_attr&'h0f)|((sp_attr&'h20)>>1);
                    if (sp_ssx>=240 && (sp_attr&'h80)) sp_ssx = sp_ssx-256;
                    sp_scode2 = sprite_base + sp_scode; sp_syy = fill_line - sp_ssy;
                    sp_baseW  = sp_scode2*16 + (sp_syy>>1); sp_lane = (sp_syy&1)*2;
                    sp_wsel<=0; sp_state<=3;
            end
            3: begin
                case (sp_wsel) 0: objrom_addr_r<=(sp_baseW      )&17'h1ffff;
                               1: objrom_addr_r<=(sp_baseW+8     )&17'h1ffff;
                               2: objrom_addr_r<=(sp_baseW+'h4000)&17'h1ffff;
                               3: objrom_addr_r<=(sp_baseW+'h4008)&17'h1ffff; endcase
                objrom_cs_r<=1; sp_state<=4;
            end
            4: if (objrom_ok) begin
                case (sp_wsel) 0:SW0<=objrom_data; 1:SW1<=objrom_data;
                               2:SW2<=objrom_data; 3:SW3<=objrom_data; endcase
                objrom_cs_r<=0;
                if (sp_wsel==3) begin sp_xx<=0; sp_state<=6; end
                else begin sp_wsel<=sp_wsel+1; sp_state<=3; end
            end
            6: begin
                begin : SDEC
                    integer tx, t, sub, ppx; reg [7:0] bA, bB; reg [3:0] pn;
                    tx = sp_sflipx ? 15-sp_xx : sp_xx; t = tx & 7; sub = t & 3;
                    if (tx < 8) begin bA = (t<4)?SW0[8*sp_lane+:8]:SW0[8*(sp_lane+1)+:8];
                                      bB = (t<4)?SW2[8*sp_lane+:8]:SW2[8*(sp_lane+1)+:8]; end
                    else        begin bA = (t<4)?SW1[8*sp_lane+:8]:SW1[8*(sp_lane+1)+:8];
                                      bB = (t<4)?SW3[8*sp_lane+:8]:SW3[8*(sp_lane+1)+:8]; end
                    pn[0]=(bA>>(3-sub))&1; pn[1]=(bA>>(7-sub))&1;
                    pn[2]=(bB>>(3-sub))&1; pn[3]=(bB>>(7-sub))&1;
                    ppx = sp_ssx + sp_xx;
                    if (ppx>=0 && ppx<256 && pn!=4'hf) begin
                        sb_wa <= fill_buf*256+ppx; sb_we <= 1'b1;
                        sb_din <= {1'b1, sp_scolor[4], sp_scolor[3:0], pn};
                    end
                end
                if (sp_xx==15) sp_state<=5; else sp_xx<=sp_xx+1;
            end
            5: begin
                if (sp_si==0) begin sp_busy<=0; sp_state<=0; end
                else begin sp_si<=sp_si-32; sp_state<=2; end
            end
            endcase
        end
    end

    // ============================ prefetch capa TEXTO (clk libre) ============================
    // Réplica EXACTA de la lógica de tx que antes vivía en el pixel stage (tix->tcode->pentx),
    // pero con la lectura de txgfx REGISTRADA (txg_addr/txg_q) -> infiere BRAM. Misma disciplina
    // de doble buffer que bg/fg: rellena fill_line en fill_buf; el pixel stage lee rdbuf=vcnt&1.
    // PRESUPUESTO DE CICLOS (§I3: contarlo, no suponerlo): 7 estados/pixel x 256 px = 1792 clk/línea.
    // Disponible = HTOTAL(384) x 8 clk por pxl_cen = 3072 clk/línea -> 58 % ocupado. Cabe.
    // Eran 4 estados (1024 clk); +3 al serializar las 2 lecturas de txram (BRAM = 1 clk de latencia).
    reg     tx_busy, txfill_req_d;
    integer tx_state, tp_x;
    integer tt_tix, tt_lo, tt_attr, tt_code, tt_color, tt_ttx, tt_tty;
    integer tt_bi0, tt_sh0, tt_bi1, tt_sh1;
    reg     tt_pen1;

    always @(posedge clk) begin
        if (rst) begin tx_state<=0; tx_busy<=0; txfill_req_d<=0; tx_we<=0; end
        else begin
            tx_we <= 1'b0;   // por defecto: sin escritura (el estado 4 lo pone a 1)
            case (tx_state)
            0: if (fill_req!=txfill_req_d && !tx_busy) begin
                   txfill_req_d<=fill_req; tx_busy<=1; tp_x<=0; tx_state<=1;
               end
            1: begin
                // txram = BRAM (u_txram): sus 2 lecturas se SERIALIZAN con estados pedir/latchear,
                // igual que el scanner de sprites en u_sprram. Latencia = 1 clk (jtframe_dual_ram
                // con LATCH*_OUT=0 registra q: `qq1 <= mem[addr1]`).
                tt_tix   = ((fill_line>>3)*32) + (tp_x>>3);
                tx_ra    <= tt_tix & 'h7ff;          // pide tt_lo
                tx_state <= 5;
            end
            5: begin                       // la RAM ve tix este ciclo -> tx_rq=txram[tix] en el estado 6
                tx_ra    <= (tt_tix+'h400) & 'h7ff;  // pide tt_attr
                tx_state <= 6;
            end
            6: begin                       // tx_rq = txram[tix] YA válido
                tt_lo    <= tx_rq;
                tx_state <= 7;
            end
            7: begin                       // tx_rq = txram[tix+0x400] YA válido
                tt_attr  = tx_rq;
                tt_code  = (tt_lo + ((tt_attr&'h80)<<1)) & 'h3ff;
                tt_color = tt_attr & 'h0f;
                tt_ttx   = ((tt_attr>>5)&1) ? 7-(tp_x&7)      : (tp_x&7);
                tt_tty   = ((tt_attr>>6)&1) ? 7-(fill_line&7) : (fill_line&7);
                begin : TXADDR   // pentx desplegado: p=0 -> po=4 -> pen[1]; p=1 -> po=0 -> pen[0]
                    integer yoff, xoff, ba0, ba1;
                    yoff = tt_tty*16; xoff = (tt_ttx<4) ? tt_ttx : (tt_ttx+4);
                    ba0  = tt_code*128 + 4 + yoff + xoff;
                    ba1  = tt_code*128 + 0 + yoff + xoff;
                    tt_bi0 = (ba0>>3) & 'h1fff; tt_sh0 = 7-(ba0&7);
                    tt_bi1 = (ba1>>3) & 'h1fff; tt_sh1 = 7-(ba1&7);
                end
                txg_addr <= tt_bi0[12:0];
                tx_state <= 2;
            end
            2: begin                       // txg_addr=bi0 este ciclo -> txg_q=txgfx[bi0] en el estado 3
                txg_addr <= tt_bi1[12:0];
                tx_state <= 3;
            end
            3: begin                       // txg_q = txgfx[bi0] YA válido -> pen[1]
                tt_pen1  <= txg_q[tt_sh0];   // == (txg_q>>tt_sh0)&1, pero de 1 bit (concat exige tamaño)
                tx_state <= 4;
            end
            4: begin                       // txg_q = txgfx[bi1] YA válido -> pen[0] + escribe txbuf
                tx_wa  <= fill_buf*256 + tp_x;  tx_we <= 1'b1;
                tx_din <= { tt_color[3:0], tt_pen1, txg_q[tt_sh1] };
                if (tp_x==255) begin tx_busy<=0; tx_state<=0; end
                else begin tp_x<=tp_x+1; tx_state<=1; end
            end
            endcase
        end
    end

    // ============================ pixel + mezcla ============================
    reg [7:0] pal_idx, dest, clut_r; reg [8:0] bgv, fgv;
    reg [9:0] sp; reg [7:0] sp_idx;
    integer tcol,trow,tix,tlo,tattr,tcode,tcolor,tflipx,tflipy,ttx,tty; reg [1:0] tpen;
    integer px_x, px_y, rdbuf;
`ifdef EMPIRECITY_PRELOAD
    reg [7:0] idx_fb [0:65535] /*verilator public_flat_rd*/;
    reg [11:0] rgb_fb [0:65535] /*verilator public_flat_rd*/;
`endif

    always @(posedge clk) begin
        if (rst) begin hcnt<=0; vcnt<=0; fill_req<=0; end
        else if (pxl_cen) begin
            if (hcnt==0 && vcnt==0) begin
                fg_x=(vregs[1]<<8)|vregs[0]; fg_y=(vregs[3]<<8)|vregs[2];
                bg_x=(vregs[5]<<8)|vregs[4]; bg_y=(vregs[8]<<8)|vregs[6]; en=vregs[7];
            end
            if (hcnt==0) begin
                fill_line <= (vcnt+1); fill_buf <= (vcnt+1) & 1;
                if (vcnt+1 < VVISIBLE) fill_req <= ~fill_req;
            end
            px_x=hcnt; px_y=vcnt; rdbuf=vcnt&1;
            if (hcnt<HVISIBLE && vcnt<VVISIBLE) begin
                dest=0;
                // line buffers: salidas YA REGISTRADAS (lb_ra sigue a hcnt/vcnt) -> aquí no hay mux 512:1
                // CLUTs: salidas YA REGISTRADAS (u_bgclut/... indexadas desde los line buffers)
                // -> aquí no hay mux de 256. Mismo valor que el array async: la dirección lleva
                // estable todo el píxel, así que la q ya se asentó (ver instancias arriba).
                bgv = bg_q;
                if ((en&'h20) && !bgv[8] && gfx_en[0]) begin clut_r=bgclut_q; dest=(clut_r&'h3f)+'h00; end
                sp = sb_q; sp_idx = {sp[7:4],sp[3:0]};
                if ((en&'h40) && sp[9] && sp[8] && gfx_en[3]) begin clut_r=sprclut_q;
                    if (sp[3:0]!=4'hf) dest=(clut_r&'h3f)+'h80; end
                fgv = fg_q;
                if ((en&'h10) && !fgv[8] && gfx_en[1]) begin clut_r=fgclut_q; dest=(clut_r&'h3f)+'h40; end
                if ((en&'h40) && sp[9] && !sp[8] && gfx_en[3]) begin clut_r=sprclut_q;
                    if (sp[3:0]!=4'hf) dest=(clut_r&'h3f)+'h80; end
                if ((en&'h80) && gfx_en[2]) begin
                    // ⭐ capa de texto YA resuelta en el prefetch (txbuf): aquí NO se lee txgfx.
                    tcolor = tx_q[5:2];
                    tpen   = tx_q[1:0];
                    clut_r = txclut_q;
                    if ((clut_r&'h0f)!=4'hf) dest=(clut_r&'h3f)+'hc0;
                end
                pal_idx <= dest;
`ifdef EMPIRECITY_PRELOAD
                idx_fb[px_y*256+px_x] = dest;
                rgb_fb[px_y*256+px_x] = { pal_lo[dest][7:4], pal_lo[dest][3:0], pal_hi[dest][3:0] };
`endif
            end else pal_idx <= 0;
            // LHBL activo 256 col; LVBL activo 224 líneas = visarea del golden (y 16..239).
            hb <= (hcnt>=HVISIBLE); vb <= (vcnt<16 || vcnt>=240);
            hs_r <= (hcnt>=296 && hcnt<328); vs_r <= (vcnt>=258 && vcnt<261);
            if (hcnt==HTOTAL-1) begin hcnt<=0;
                if (vcnt==VTOTAL-1) begin vcnt<=0;
`ifdef EMPIRECITY_PRELOAD
                    $writememh({`DATADIR,"/sim_video.hex"}, idx_fb);
                    $writememh({`DATADIR,"/sim_rgb.hex"},   rgb_fb);
`endif
                end else vcnt<=vcnt+1;
            end else hcnt<=hcnt+1;
        end
    end

    // ============================ colmix: paleta xBRG_444 -> RGB (4b/canal) ============================
    assign red   = pal_lo[pal_idx][7:4];
    assign green = pal_lo[pal_idx][3:0];
    assign blue  = pal_hi[pal_idx][3:0];
endmodule
