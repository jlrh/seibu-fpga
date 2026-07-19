# seibu-fpga

🇬🇧 English (below) · [🇪🇸 Español](#español)

FPGA recreations of **Seibu Kaihatsu** arcade boards, built on the **JTFRAME** framework (GPLv3). MiSTer
target.

## Cores

### Empire City: 1931 (Seibu, 1986)
Vertical run-and-gun shooter (same hardware family as *Street Fight* / `stfight`). Hardware: **Z80** main
CPU + **Z80** sound CPU + **Motorola 68705** microcontroller (protection / coins / ADPCM trigger) +
**2×YM2203** (FM/PSG) + **MSM5205** (ADPCM) + three tilemaps (RAM-based text + ROM-based bg/fg) + sprites,
mixed through **7 CLUT PROMs**.

**Status: playable on MiSTer** — the `empcity` set (Seibu original) boots, passes the 68705 protection,
renders the attract **pixel-identical to MAME (0.0000%)**, coins work, and audio (2×YM2203 + MSM5205
ADPCM) is fixed on real hardware. The **68705** runs on `jtframe_6805mcu`; its firmware loads at runtime.

A prebuilt `.rbf` is in [`releases/`](releases/) — **distributable**: the 68705 firmware
(`empcityu_68705.3j`) and the game ROMs are loaded at **runtime** from the `.mra`, **none is baked into
the bitstream**. Or build from source (`cores/empirecity/`). See [`BUILD.md`](BUILD.md).

> ℹ️ Naming: the core's own modules drop the `jt` prefix (`empirecity_*`); only the GAMETOP
> (`jtempirecity_game`) keeps `jt`, because memgen imposes it. The **CORENAME is `empirecity`** (folder,
> `.rbf` and `.mra` all use it).

## Build

This repo contains **only the core code** (`cores/empirecity/`). The framework and third-party cores
(jtframe, jt12/jt03, jt5205) are **not included** — jtframe provides them. Quick version:

1. Clone [jtcores](https://github.com/jotego/jtcores) (brings jtframe + modules).
2. Copy this repo's `cores/empirecity/` into your jtcores checkout.
3. Build: `jtcore empirecity -mister -c`.

📋 **Step-by-step in [`BUILD.md`](BUILD.md).**

Core layout:
```
cores/empirecity/
├── hdl/   Core Verilog (empirecity_* modules + jtempirecity_game GAMETOP)
├── cfg/   files.yaml, macros.def, mem.yaml, mame2mra.toml
├── mra/   .mra definition (how to assemble the ROMs; set empcity)
└── syn/   empirecity_clk48_96.sdc  (timing constraint — the core crosses clk48↔clk96)
```

## ROMs

**Not included** (copyrighted material). Everyone provides the original ROMs of their own board,
**including the 68705 firmware** (`empcityu_68705.3j`). The `.mra` describes how to assemble them; it
loads the firmware and PROMs at runtime, so the `.rbf` carries no copyrighted data.

## Credits

- **JTFRAME**, **jt12/jt03**, **jt5205** — the GPLv3 frameworks this core is built on
- **MAME** — hardware reference (`stfight.cpp` driver, 68705 research)

## Acknowledgements

- To **Sorgelig** and the whole **MiSTer FPGA** project and community.
- To the **MAME community**, for the preservation and reverse-engineering work without which this core
  would not be possible.
- And to **Anthropic**, for **Claude**.

## License

**GPLv3** (see [`LICENSE`](LICENSE)) — required by the JTFRAME / jt12 / jt5205 dependencies; their
copyright notices are preserved in the sources.

---

## Español

🇪🇸 Español · [🇬🇧 English ↑](#seibu-fpga)

Recreaciones en FPGA de placas arcade de **Seibu Kaihatsu**, construidas sobre el framework **JTFRAME**
(GPLv3). Objetivo MiSTer.

## Cores

### Empire City: 1931 (Seibu, 1986)
Shooter vertical de acción (misma familia de hardware que *Street Fight* / `stfight`). Hardware: CPU
principal **Z80** + CPU de sonido **Z80** + microcontrolador **Motorola 68705** (protección / monedas /
disparo del ADPCM) + **2×YM2203** (FM/PSG) + **MSM5205** (ADPCM) + tres tilemaps (texto en RAM + bg/fg en
ROM) + sprites, mezclados por **7 PROMs de CLUT**.

**Estado: jugable en MiSTer** — el set `empcity` (Seibu original) arranca, pasa la protección del 68705,
renderiza el attract **idéntico a MAME al píxel (0.0000%)**, las monedas funcionan y el audio (2×YM2203 +
ADPCM MSM5205) está resuelto en placa real. El **68705** corre sobre `jtframe_6805mcu`; su firmware se
carga en runtime.

Hay un `.rbf` precompilado en [`releases/`](releases/) — **distribuible**: el firmware del 68705
(`empcityu_68705.3j`) y las ROMs del juego se cargan en **runtime** desde el `.mra`, **nada va horneado en
el bitstream**. O compila desde fuente (`cores/empirecity/`). Ver [`BUILD.md`](BUILD.md).

> ℹ️ Nomenclatura: los módulos propios del core van **sin** el prefijo `jt` (`empirecity_*`); solo el
> GAMETOP (`jtempirecity_game`) conserva `jt`, porque memgen lo impone. El **CORENAME es `empirecity`**
> (lo usan la carpeta, el `.rbf` y el `.mra`).

## Construir

Este repo contiene **solo el código del core** (`cores/empirecity/`). El framework y los cores de
terceros (jtframe, jt12/jt03, jt5205) **no se incluyen** — los aporta jtframe. Versión rápida:

1. Clona [jtcores](https://github.com/jotego/jtcores) (trae jtframe + módulos).
2. Copia `cores/empirecity/` de este repo dentro de tu checkout de jtcores.
3. Compila: `jtcore empirecity -mister -c`.

📋 **Pasos detallados en [`BUILD.md`](BUILD.md).**

Estructura del core:
```
cores/empirecity/
├── hdl/   Verilog del core (módulos empirecity_* + GAMETOP jtempirecity_game)
├── cfg/   files.yaml, macros.def, mem.yaml, mame2mra.toml
├── mra/   definición .mra (cómo ensamblar las ROMs; set empcity)
└── syn/   empirecity_clk48_96.sdc  (constraint de timing — el core cruza clk48↔clk96)
```

## ROMs

**No se incluyen** (material con copyright). Cada cual aporta las ROMs originales de su placa, **incluido
el firmware del 68705** (`empcityu_68705.3j`). El `.mra` describe cómo ensamblarlas; carga el firmware y
las PROMs en runtime, así que el `.rbf` no lleva ningún dato con copyright.

## Créditos

- **JTFRAME**, **jt12/jt03**, **jt5205** — los frameworks GPLv3 sobre los que se construye este core
- **MAME** — referencia de hardware (driver `stfight.cpp`, investigación del 68705)

## Agradecimientos

- A **Sorgelig** y todo el proyecto y comunidad **MiSTer FPGA**.
- A la **comunidad MAME**, por el trabajo de preservación e ingeniería inversa sin el cual este core no
  sería posible.
- Y a **Anthropic**, por **Claude**.

## Licencia

**GPLv3** (ver [`LICENSE`](LICENSE)) — obligado por las dependencias JTFRAME / jt12 / jt5205; sus avisos de
copyright se conservan en las fuentes.
