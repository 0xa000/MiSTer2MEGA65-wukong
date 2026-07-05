# MiSTer2MEGA65 — QMTECH Wukong port

This fork adds a board variant of the [MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65)
framework for the QMTECH Wukong board (XC7A100T-2FGG676, 50 MHz oscillator,
256 MB DDR3, HDMI out), wired the same way as
[mega65-core-wukong](https://github.com/0xa000/mega65-core-wukong):
a real C64 keyboard on J12, joysticks on the J10/J11 PMODs, one SD card slot.

All MEGA65 sources are untouched; the port lives in parallel files:

| | |
|---|---|
| `M2M/vhdl/wukong/top_wukong.vhd` | board top (pin names match `wukong.xdc` of mega65-core-wukong) |
| `M2M/vhdl/wukong/framework_wukong.vhd` | framework variant (diff against `M2M/vhdl/framework.vhd` to review) |
| `M2M/vhdl/wukong/clk_wukong.vhd` | 50→100 MHz PLL, everything downstream of it is stock M2M |
| `M2M/vhdl/wukong/c64kbd_to_matrix.vhd` | C64 matrix scanner (charge trick), MEGA65-matrix compatible |
| `M2M/vhdl/wukong/m2m_keyb_wukong.vhd` | keyboard controller using the scanner |
| `M2M/vhdl/wukong/avm_to_wb.vhd` | Avalon-MM → pipelined Wishbone bridge |
| `M2M/vhdl/wukong/ddr3_wrapper_wukong.vhd` | DDR3 replaces HyperRAM behind the same Avalon interface |
| `M2M/vhdl/wukong/uberddr3/` | [UberDDR3](https://github.com/AngeloJacobo/UberDDR3) (Wukong adaptation from mega65-core-wukong) |
| `M2M/WUKONG.xdc` | pins + timing (replaces `common.xdc` + `MEGA65-*.xdc` for this board) |
| `CORE/wukong-build.tcl` | batch build flow |

## Building

```
git submodule update --init --recursive
(cd M2M/QNICE/tools && ./make-toolchain.sh)      # QNICE assembler, once
(cd CORE/m2m-rom && ./make_rom.sh)               # firmware ROM
cd CORE
vivado -mode batch -source wukong-build.tcl -tclargs bit
```

Stages: `elab` (fast sanity check), `synth` (checkpoint + reports), `impl`
(resume from the synth checkpoint), `bit` (full flow). Output lands in
`CORE/build-wukong/`.

## What works differently from a MEGA65

* **Menu key**: the C64 keyboard has no Help key, so **RESTORE opens the
  on-screen menu**. Consequently cores cannot see a real RESTORE keypress.
* **Sound** comes out of HDMI only (no analog audio path on the board).
* **SD**: the single slot appears as M2M's "external" slot (which wins in
  the firmware's auto mode); the internal slot reads "no card".
* **LEDs**: led0 = power led (from the core), led1 = drive led, and led1 is
  lit solid until the DDR3 controller finishes calibration (bring-up aid).
* **RTC**: no RTC chip; the firmware reads idle I2C buses, so date/time are
  garbage. Filed under "known, harmless for now".
* Dropped entirely: VGA/VDAC, paddles, IEC, cartridge port, second SD slot,
  MEGA65 keyboard LEDs.

## Memory architecture

M2M routes all external memory traffic (ascal framebuffer, QNICE, vdrives)
through a 16-bit burst-capable Avalon-MM port in a 100 MHz clock domain.
On the MEGA65 that is the HyperRAM; here it is:

```
16-bit Avalon @100 MHz → avm_fifo (CDC) → avm_increase (16→128)
   → avm_to_wb → UberDDR3 (83.33 MHz controller, 333.33 MHz DDR3)
```

The DDR3/controller/reference clock ratios mirror the proven
mega65-core-wukong configuration.

## Status

* Elaborates and synthesizes cleanly in Vivado 2023.2
  (~28% LUTs, ~38% BRAM, ~26% DSP of the XC7A100T with the demo core).
* Not yet verified on hardware.
