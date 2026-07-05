# MiSTer2MEGA65 — QMTECH Wukong batch build (non-project mode)
#
# Usage:
#   vivado -mode batch -source wukong-build.tcl -tclargs elab    # elaborate only (fast sanity check)
#   vivado -mode batch -source wukong-build.tcl -tclargs synth   # synthesize, write checkpoint
#   vivado -mode batch -source wukong-build.tcl -tclargs bit     # full flow to bitstream
#   vivado -mode batch -source wukong-build.tcl -tclargs impl    # resume from post_synth.dcp to bitstream
#
# Run from the CORE/ directory. The QNICE firmware must exist:
#   cd m2m-rom && ./make_rom.sh   (needs M2M/QNICE submodule + toolchain, see make_rom.sh)
#
# Wukong port done by 0xa000 in 2026 and licensed under GPL v3

set stage "bit"
if { $argc > 0 } { set stage [lindex $argv 0] }

set part xc7a100tfgg676-2
set top  top_wukong
set outdir ./build-wukong
file mkdir $outdir

if { ![file exists ./m2m-rom/m2m-rom.rom] } {
   puts "ERROR: m2m-rom/m2m-rom.rom missing — run cd m2m-rom && ./make_rom.sh first"
   exit 1
}

# ---------------------------------------------------------------------------
# Sources: R6 project file list minus MEGA65-only files (top_mega65-r6,
# framework, m2m_keyb, mega65kbd_to_matrix, hyperram/*), plus the wukong/ layer
# ---------------------------------------------------------------------------

set vhdl_2008 {
   ../M2M/vhdl/tdp_ram.vhd
   ../M2M/vhdl/2port2clk_ram.vhd
   ../M2M/vhdl/2port2clk_ram_byteenable.vhd
   ../M2M/QNICE/vhdl/EAE.vhd
   ../M2M/QNICE/vhdl/cpu_constants.vhd
   ../M2M/QNICE/vhdl/alu.vhd
   ../M2M/QNICE/vhdl/alu_shifter.vhd
   ../M2M/vhdl/av_pipeline/vga_recover_counters.vhd
   ../M2M/vhdl/ram_init.vhd
   ../M2M/vhdl/av_pipeline/vga_osm.vhd
   ../M2M/vhdl/av_pipeline/video_overlay.vhd
   ../M2M/vhdl/av_pipeline/analog_pipeline.vhd
   ../M2M/vhdl/av_pipeline/ascal.vhd
   ../M2M/vhdl/controllers/M65/audio.vhd
   ../M2M/QNICE/vhdl/tools.vhd
   ../M2M/vhdl/av_pipeline/video_modes_pkg.vhd
   vhdl/globals.vhd
   ../M2M/vhdl/controllers/HDMI/types_pkg.vhd
   ../M2M/vhdl/cdc_stable.vhd
   ../M2M/vhdl/cdc_pulse.vhd
   ../M2M/vhdl/av_pipeline/video_counters.vhd
   ../M2M/vhdl/av_pipeline/crop.vhd
   ../M2M/vhdl/av_pipeline/clk_synthetic_enable.vhd
   ../M2M/vhdl/memory/avm_decrease.vhd
   ../M2M/vhdl/memory/avm_increase.vhd
   ../M2M/vhdl/axi_fifo_small.vhd
   ../M2M/vhdl/controllers/HDMI/sync_reg.vhd
   ../M2M/vhdl/controllers/HDMI/hdmi_tx_encoder.vhd
   ../M2M/vhdl/controllers/HDMI/vga_to_hdmi.vhd
   ../M2M/vhdl/controllers/HDMI/serialiser_10to1_selectio.vhd
   ../M2M/vhdl/av_pipeline/digital_pipeline.vhd
   ../M2M/vhdl/hdmi_flicker_free.vhd
   ../M2M/vhdl/av_pipeline/av_pipeline.vhd
   ../M2M/vhdl/memory/avm_arbit.vhd
   ../M2M/vhdl/memory/avm_arbit_general.vhd
   ../M2M/vhdl/memory/axi_fifo.vhd
   ../M2M/vhdl/memory/avm_fifo.vhd
   ../M2M/QNICE/vhdl/basic_uart.vhd
   ../M2M/vhdl/QNICE/qnice_globals.vhd
   ../M2M/QNICE/vhdl/block_ram.vhd
   ../M2M/QNICE/vhdl/block_rom.vhd
   ../M2M/QNICE/vhdl/bus_uart.vhd
   ../M2M/QNICE/vhdl/byte_bram.vhd
   vhdl/clk.vhd
   ../M2M/vhdl/clk_m2m.vhd
   ../M2M/vhdl/clock_counter.vhd
   vhdl/config.vhd
   ../M2M/vhdl/i2c/cpu_to_i2c_master.vhd
   ../M2M/QNICE/vhdl/cycle_counter.vhd
   ../M2M/vhdl/debounce.vhd
   ../M2M/vhdl/debouncer.vhd
   ../M2M/vhdl/democore/democore_game.vhd
   ../M2M/vhdl/democore/vga_controller.vhd
   ../M2M/vhdl/democore/democore_video.vhd
   ../M2M/vhdl/democore/democore_audio.vhd
   ../M2M/vhdl/democore/democore.vhd
   ../M2M/QNICE/vhdl/fifo.vhd
   ../M2M/vhdl/controllers/HDMI/video_out_clock.vhd
   ../M2M/vhdl/reset_manager.vhd
   ../M2M/vhdl/controllers/M65/kb_matrix_ram.vhdl
   ../M2M/vhdl/controllers/M65/matrix_to_keynum.vhdl
   ../M2M/QNICE/vhdl/qnice_cpu.vhd
   ../M2M/vhdl/QNICE/sdmux.vhd
   ../M2M/QNICE/vhdl/sdcard.vhd
   ../M2M/vhdl/QNICE/qnice_mmio.vhd
   ../M2M/vhdl/QNICE/qnice.vhd
   ../M2M/vhdl/qnice2hyperram.vhd
   ../M2M/vhdl/controllers/M65/mouse_input.vhdl
   ../M2M/vhdl/qnice_wrapper.vhd
   ../M2M/vhdl/i2c/rtc_master.vhd
   ../M2M/vhdl/i2c/rtc_controller.vhd
   ../M2M/vhdl/qnice_arbit.vhd
   ../M2M/vhdl/i2c/i2c_master.vhd
   ../M2M/vhdl/i2c/i2c_controller.vhd
   ../M2M/vhdl/i2c/rtc_wrapper.vhd
   vhdl/keyboard.vhd
   vhdl/main.vhd
   ../M2M/vhdl/vdrives.vhd
   vhdl/mega65.vhd
   ../M2M/QNICE/vhdl/register_file.vhd
   ../M2M/QNICE/vhdl/sd_spi.vhd
   ../M2M/vhdl/wukong/c64kbd_to_matrix.vhd
   ../M2M/vhdl/wukong/m2m_keyb_wukong.vhd
   ../M2M/vhdl/wukong/avm_to_wb.vhd
   ../M2M/vhdl/wukong/ddr3_wrapper_wukong.vhd
   ../M2M/vhdl/wukong/clk_wukong.vhd
   ../M2M/vhdl/wukong/framework_wukong.vhd
   ../M2M/vhdl/wukong/top_wukong.vhd
}

set verilog {
   ../M2M/vhdl/wukong/uberddr3/ddr3_controller.v
   ../M2M/vhdl/wukong/uberddr3/ddr3_phy.v
   ../M2M/vhdl/wukong/uberddr3/ddr3_top_wukong.v
}

set sverilog {
   ../M2M/vhdl/av_pipeline/audio_out.v
   ../M2M/vhdl/controllers/MiSTer/iir_filter.v
   ../M2M/vhdl/controllers/MiSTer/scandoubler.v
   ../M2M/vhdl/controllers/MiSTer/csync.sv
   ../M2M/vhdl/controllers/MiSTer/hq2x.sv
   ../M2M/vhdl/controllers/MiSTer/video_freezer.sv
   ../M2M/vhdl/controllers/MiSTer/video_mixer.sv
}

read_vhdl -vhdl2008 $vhdl_2008
read_verilog $verilog
read_verilog -sv $sverilog
read_xdc ../M2M/WUKONG.xdc
read_xdc CORE.xdc

# Non-project mode does not scan for Xilinx Parameterized Macros by itself;
# without this the XPM_CDC timing constraints (xpm_cdc_array_single,
# xpm_cdc_async_rst, xpm_fifo_axis, ...) are silently skipped and all
# framework clock-domain crossings fail timing.
auto_detect_xpm

# ---------------------------------------------------------------------------
# Flow
# ---------------------------------------------------------------------------

# Constraints that only resolve on the synthesized netlist (referenced from
# WUKONG.xdc, where XDC application at elaboration time cannot find the cells)
proc apply_post_synth_constraints {} {
   # Place the IOSERDES_train of UberDDR3 manually (else the tool may place
   # these blocks where they block the route for the ddr3_clk_p OBUFDS).
   # The Wukong adaptation of UberDDR3 does not generate train IOSERDES in
   # this configuration, so absence is expected and fine.
   set otrain [get_cells -quiet -hier -filter {NAME =~ "*ddr3_phy_inst*OSERDESE2_train*"}]
   set itrain [get_cells -quiet -hier -filter {NAME =~ "*ddr3_phy_inst*ISERDESE2_train*"}]
   if { [llength $otrain] == 1 && [llength $itrain] == 1 } {
      set_property LOC OLOGIC_X0Y91 $otrain
      set_property LOC ILOGIC_X0Y94 $itrain
      puts "== DDR3 train cells located: $otrain / $itrain =="
   } else {
      puts "== DDR3 train IOSERDES not present in this UberDDR3 configuration — no LOC applied =="
   }
   # ascal's reset_na distribution is asynchronous by design. Upstream M2M
   # uses "set_false_path -through .../i_ascal/reset_na", but that
   # hierarchical pin does not survive synthesis in this flow; the equivalent
   # is to cut all paths into the reset resynchronization registers inside
   # ascal (avl_/i_/o_reset_na_reg), covering D as well as async CLR/PRE.
   set ascal_rst [get_pins -quiet -hier -filter {
      (NAME =~ "*/i_ascal/*reset_na_reg*/D") ||
      (NAME =~ "*/i_ascal/*reset_na_reg*/CLR") ||
      (NAME =~ "*/i_ascal/*reset_na_reg*/PRE")}]
   if { [llength $ascal_rst] > 0 } {
      set_false_path -to $ascal_rst
      puts "== ascal reset_na false path applied to [llength $ascal_rst] pins =="
   } else {
      puts "CRITICAL WARNING: ascal reset_na resync registers not found — false path not applied"
   }
}

if { $stage == "elab" } {
   synth_design -rtl -top $top -part $part
   puts "== Elaboration OK =="
   exit 0
}

if { $stage == "impl" && [file exists $outdir/post_synth.dcp] } {
   open_checkpoint $outdir/post_synth.dcp
} else {
   synth_design -top $top -part $part
   write_checkpoint -force $outdir/post_synth.dcp
   report_utilization -file $outdir/utilization_synth.rpt
   report_timing_summary -file $outdir/timing_synth.rpt
}

if { $stage == "synth" } {
   puts "== Synthesis OK =="
   exit 0
}

apply_post_synth_constraints

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force $outdir/post_route.dcp
report_utilization -file $outdir/utilization_route.rpt
report_timing_summary -file $outdir/timing_route.rpt

write_bitstream -force $outdir/wukong-m2m.bit
puts "== Bitstream written to $outdir/wukong-m2m.bit =="
