# Building the core (reproducible) — Empire City: 1931

🇬🇧 English (below) · [🇪🇸 Español](#compilar-el-core-reproducible--empire-city-1931)

Steps to rebuild the `.rbf` from scratch. No patch is required: the 68705 firmware and the game ROMs are
loaded at **runtime** from the `.mra`, so the bitstream is distributable as-is. Tested for MiSTer.

## Requirements
- A [**jtcores**](https://github.com/jotego/jtcores) checkout (brings jtframe + jt12/jt03 + jt5205 as
  modules) and its toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (the version your MiSTer board needs).
- Your Empire City **ROMs** (not included), **including the 68705 firmware** `empcityu_68705.3j` — see
  [`DETAILS.md`](DETAILS.md).

## Steps

1. **Place the core** inside jtcores (the jtframe CORENAME is `empirecity`):
   ```
   cp -r cores/empirecity  <jtcores>/cores/empirecity
   ```

2. **Build** (generate + compile):
   ```
   cd <jtcores> && source setprj.sh
   jtcore empirecity -mister -c
   ```
   This generates `<jtcores>/cores/empirecity/mister/` (Quartus project + the memgen GAMETOP
   `jtempirecity_game_sdram.v`) and compiles it. The result is the `.rbf` under `mister/output_files/`.

   > The core is **dual-clock (clk48 ↔ clk96)**, so the timing constraint `syn/empirecity_clk48_96.sdc`
   > **is required** for the fitter to close timing — it is included in this repo and jtcore picks it up
   > from `cores/empirecity/syn/`.

## The 68705

The `empcity` set uses a **Motorola 68705** microcontroller for protection, coin handling and the ADPCM
trigger. It runs on jtframe's **`jtframe_6805mcu`** (jtframe already has a 6805 core — no from-scratch LLE
needed). Its firmware (`empcityu_68705.3j`) is declared as a PROM region in the `.mra`, so it enters the
download stream and is **loaded at runtime** — **not baked** into the bitstream. The same applies to the
7 CLUT PROMs and the tile/sprite graphics.

## Legal / distribution
- This repo's **code** is GPLv3 and contains no ROMs or firmware.
- The **`.rbf` in [`releases/`](releases/)** was built with these steps: neither the game ROMs nor the
  68705 firmware are inside → it is **distributable**. The **ROMs and the firmware** are provided by each
  user.

---

# Compilar el core (reproducible) — Empire City: 1931

🇪🇸 Español · [🇬🇧 English ↑](#building-the-core-reproducible--empire-city-1931)

Pasos para reconstruir el `.rbf` desde cero. No hace falta ningún parche: el firmware del 68705 y las ROMs
del juego se cargan en **runtime** desde el `.mra`, así que el bitstream es distribuible tal cual. Probado
para MiSTer.

## Requisitos
- Un checkout de [**jtcores**](https://github.com/jotego/jtcores) (trae jtframe + jt12/jt03 + jt5205 como
  módulos) y su toolchain (`setprj.sh`, `jtcore`).
- **Quartus** (la versión que pida tu placa MiSTer).
- Tus **ROMs** de Empire City (no se incluyen), **incluido el firmware del 68705** `empcityu_68705.3j` —
  ver [`DETAILS.md`](DETAILS.md).

## Pasos

1. **Coloca el core** dentro de jtcores (el CORENAME de jtframe es `empirecity`):
   ```
   cp -r cores/empirecity  <jtcores>/cores/empirecity
   ```

2. **Compila** (genera + compila):
   ```
   cd <jtcores> && source setprj.sh
   jtcore empirecity -mister -c
   ```
   Esto genera `<jtcores>/cores/empirecity/mister/` (proyecto Quartus + el GAMETOP de memgen
   `jtempirecity_game_sdram.v`) y lo compila. El resultado es el `.rbf` en `mister/output_files/`.

   > El core es **de doble reloj (clk48 ↔ clk96)**, así que el constraint de timing
   > `syn/empirecity_clk48_96.sdc` **es necesario** para que el fitter cierre timing — va incluido en este
   > repo y jtcore lo recoge de `cores/empirecity/syn/`.

## El 68705

El set `empcity` usa un microcontrolador **Motorola 68705** para la protección, la gestión de monedas y el
disparo del ADPCM. Corre sobre **`jtframe_6805mcu`** de jtframe (jtframe ya tiene un core 6805 — no hace
falta LLE desde cero). Su firmware (`empcityu_68705.3j`) se declara como región PROM en el `.mra`, de modo
que entra en el stream de descarga y se **carga en runtime** — **no va horneado** en el bitstream. Lo mismo
vale para las 7 PROMs de CLUT y los gráficos de tiles/sprites.

## Legalidad / distribución
- El **código** de este repo es GPLv3 y no contiene ROMs ni firmware.
- El **`.rbf` de [`releases/`](releases/)** se compiló con estos pasos: ni las ROMs del juego ni el
  firmware del 68705 van dentro → es **distribuible**. Las **ROMs y el firmware** los aporta cada usuario.
