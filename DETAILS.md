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

### Dead Angle (Seibu, 1988)
Third-person gangster shooter, sequel to *Empire City: 1931*. Hardware: **2× NEC V30** at 8 MHz (main + sub,
4 KB shared RAM with a hardware lock) + **Z80** sound CPU with the **SEI80BU**-encrypted program + Seibu
Sound System (**YM3931** interface, **2×YM2203**, **2×MSM5205** ADPCM) + text layer + three 16×16
playfields (one RAM-mapped, two ROM-mapped) + 256 sprites, 2048-colour palette.

**Status: playable on MiSTer** — the `deadang` set boots, runs the attract, takes coins and plays (tested on
real hardware: level 1, music and sound effects). Video was checked against MAME scene by scene (261
scenes, 0 differing pixels in simulation). The V30s are **wickerwaka's cycle-exact NEC V30 "ucore"**
(`nec_test`), with a max-mode bus controller derived from Raiden_MiSTer / M72.

A prebuilt `.rbf` is in [`releases/`](releases/) (`ffdeadang_20261006.rbf`); the game ROMs are loaded at
runtime from the `.mra` (`deadang.zip`, MAME 0.288 merged). Source: `cores/deadang/`.

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
- **MAME** — hardware reference (`stfight.cpp` driver, 68705 research; `deadang.cpp`, `seibusound.cpp`, `sei80bu.cpp`)
- **wickerwaka** — cycle-exact NEC V30 ucore ([nec_test](https://github.com/wickerwaka/nec_test), commit
  `ed50fb4e`), used by Dead Angle. Distributed with its own GPL-2.0 `LICENSE` text
  (`cores/deadang/hdl/ucore_LICENSE_GPL2`); the files carry no "version 2 only" / "or later" statement
- **Raiden_MiSTer** (Umberto Parisi) and **Irem M72** (Martin Donlon) — V30 max-mode bus controller that
  `deadang_v30.sv` is distilled from

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

### Dead Angle (Seibu, 1988)
Shooter en tercera persona de gánsteres, secuela de *Empire City: 1931*. Hardware: **2× NEC V30** a 8 MHz
(principal + secundaria, 4 KB de RAM compartida con candado hardware) + CPU de sonido **Z80** con programa
cifrado (**SEI80BU**) + Seibu Sound System (interfaz **YM3931**, **2×YM2203**, **2×MSM5205** ADPCM) + capa de
texto + tres playfields de 16×16 (uno con mapa en RAM, dos con mapa en ROM) + 256 sprites, paleta de 2048
colores.

**Estado: jugable en MiSTer** — el set `deadang` arranca, pasa el attract, acepta monedas y se juega
(probado en placa real: nivel 1, música y efectos). El vídeo se contrastó con MAME escena a escena (261
escenas, 0 píxeles distintos en simulación). Los V30 son el **"ucore" NEC V30 exacto a ciclo de wickerwaka**
(`nec_test`), con un controlador de bus en modo máximo derivado de Raiden_MiSTer / M72.

Hay un `.rbf` precompilado en [`releases/`](releases/) (`ffdeadang_20261006.rbf`); las ROMs del juego se
cargan en runtime desde el `.mra` (`deadang.zip`, merged de MAME 0.288). Fuente: `cores/deadang/`.

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
- **MAME** — referencia de hardware (driver `stfight.cpp`, investigación del 68705; `deadang.cpp`, `seibusound.cpp`, `sei80bu.cpp`)
- **wickerwaka** — ucore NEC V30 exacto a ciclo ([nec_test](https://github.com/wickerwaka/nec_test), commit
  `ed50fb4e`), usado por Dead Angle. Se distribuye con su propio texto `LICENSE` GPL-2.0
  (`cores/deadang/hdl/ucore_LICENSE_GPL2`); los ficheros no dicen "solo versión 2" ni "o posterior"
- **Raiden_MiSTer** (Umberto Parisi) e **Irem M72** (Martin Donlon) — controlador de bus V30 en modo máximo
  del que deriva `deadang_v30.sv`

## Agradecimientos

- A **Sorgelig** y todo el proyecto y comunidad **MiSTer FPGA**.
- A la **comunidad MAME**, por el trabajo de preservación e ingeniería inversa sin el cual este core no
  sería posible.
- Y a **Anthropic**, por **Claude**.

## Licencia

**GPLv3** (ver [`LICENSE`](LICENSE)) — obligado por las dependencias JTFRAME / jt12 / jt5205; sus avisos de
copyright se conservan en las fuentes.

<!-- omf_release:dependencias:ffempirecity -->
## Dependencias externas de `ffempirecity`

Este repositorio contiene **solo el código de los cores**. Para compilar `ffempirecity`
hacen falta estas piezas, que se distribuyen desde su propio origen:

| Qué | De dónde | Dónde va |
|---|---|---|
| jtframe — framework de compilacion y modulos comunes (vtimer, SDRAM, descarga, CPUs Z80 y 6805) | [https://github.com/jotego/jtframe](https://github.com/jotego/jtframe) | `modules/jtframe` |
| jt12 — YM2203 (jt03) | [https://github.com/jotego/jt12](https://github.com/jotego/jt12) | `modules/jt12` |
| jt5205 — MSM5205 (ADPCM) | [https://github.com/jotego/jt5205](https://github.com/jotego/jt5205) | `modules/jt5205` |
<!-- /omf_release:dependencias:ffempirecity -->

<!-- omf_release:dependencias:ffdeadang -->
## Dependencias externas de `ffdeadang`

Este repositorio contiene **solo el código de los cores**. Para compilar `ffdeadang`
hacen falta estas piezas, que se distribuyen desde su propio origen:

| Qué | De dónde | Dónde va |
|---|---|---|
| jtframe — framework de compilacion y modulos comunes (vtimer, SDRAM, descarga, CPU Z80) | [https://github.com/jotego/jtframe](https://github.com/jotego/jtframe) | `modules/jtframe` |
| jt12 — YM2203 x2 (jt03) | [https://github.com/jotego/jt12](https://github.com/jotego/jt12) | `modules/jt12` |
| jt5205 — MSM5205 x2 (ADPCM) | [https://github.com/jotego/jt5205](https://github.com/jotego/jt5205) | `modules/jt5205` |
<!-- /omf_release:dependencias:ffdeadang -->
