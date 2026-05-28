## ============================================================
##  create_project.tcl  —  Vivado Project Creation Script
##  Board: Xilinx Arty S7-50 (xc7s50csga324-1)
##  Vivado: 2020.2
##
##  STEP 1: Close any open project in Vivado first.
##  STEP 2: Tools → Run Tcl Script → select this file.
## ============================================================

## ---- Hardcoded Absolute Paths (most reliable for Vivado 2020.2) ----
set phase8_rtl  "C:/Users/tharu/RISC-V_CPU/riscv_processor_cpu/phase8/rtl"
set cpu_rtl     "C:/Users/tharu/RISC-V_CPU/riscv_processor_cpu/rtl"
set xdc_file    "C:/Users/tharu/RISC-V_CPU/riscv_processor_cpu/phase8/constraints/arty_s7_50.xdc"
set project_dir "C:/Users/tharu/RISC-V_CPU/riscv_processor_cpu/phase8/vivado/vivado_project"

puts "============================================"
puts "  RISC-V SoC — Vivado Project Setup"
puts "============================================"
puts "  Phase8 RTL : $phase8_rtl"
puts "  CPU RTL    : $cpu_rtl"
puts "  XDC        : $xdc_file"
puts "  Project    : $project_dir"
puts "============================================"

## ---- Verify directories exist ----
if {![file isdirectory $phase8_rtl]} {
    error "ERROR: Phase8 RTL directory not found: $phase8_rtl"
}
if {![file isdirectory $cpu_rtl]} {
    error "ERROR: CPU RTL directory not found: $cpu_rtl"
}
if {![file exists $xdc_file]} {
    error "ERROR: XDC file not found: $xdc_file"
}
puts "  All source directories verified OK."

## ---- Close any open project ----
catch {close_project}

## ---- Create Project ----
puts "\n--- Creating Vivado project ---"
create_project rv32_soc_arty_s7 $project_dir -part xc7s50csga324-1 -force

## Set board (optional — only works if Digilent board files are installed)
if {[catch {set_property board_part digilentinc.com:arty-s7-50:part0:1.1 [current_project]} err]} {
    puts "  NOTE: Board files not installed (OK — part xc7s50csga324-1 is still set)."
} else {
    puts "  Board part set: Arty S7-50."
}
puts "  Project created OK."

## ---- Add Phase 8 SoC RTL Files ----
puts "\n--- Adding Phase 8 SoC RTL files ---"
set soc_files [list \
    "$phase8_rtl/soc_top.sv"     \
    "$phase8_rtl/cpu_top_soc.sv" \
    "$phase8_rtl/uart_tx.sv"     \
    "$phase8_rtl/uart_rx.sv"     \
    "$phase8_rtl/uart.sv"        \
    "$phase8_rtl/bram.sv"        \
]
foreach f $soc_files {
    if {[file exists $f]} {
        add_files -fileset sources_1 $f
        puts "  Added: [file tail $f]"
    } else {
        puts "  WARNING — not found: $f"
    }
}

## ---- Add Shared CPU RTL Files ----
puts "\n--- Adding shared CPU RTL files ---"
set cpu_files [list \
    "$cpu_rtl/alu.sv"              \
    "$cpu_rtl/branch_predictor.sv" \
    "$cpu_rtl/control_unit.sv"     \
    "$cpu_rtl/csr_file.sv"         \
    "$cpu_rtl/fp_regfile.sv"       \
    "$cpu_rtl/fpu_unit.sv"         \
    "$cpu_rtl/hazard.sv"           \
    "$cpu_rtl/imm_gen.sv"          \
    "$cpu_rtl/interrupt_unit.sv"   \
    "$cpu_rtl/muldiv.sv"           \
    "$cpu_rtl/regfile.sv"          \
    "$cpu_rtl/vector_regfile.sv"   \
    "$cpu_rtl/vector_unit.sv"      \
]
foreach f $cpu_files {
    if {[file exists $f]} {
        add_files -fileset sources_1 $f
        puts "  Added: [file tail $f]"
    } else {
        puts "  WARNING — not found: $f"
    }
}

## ---- Set file type to SystemVerilog ----
puts "\n--- Setting SystemVerilog file type ---"
set all_sv [get_files -of_objects [get_filesets sources_1] *.sv]
if {[llength $all_sv] > 0} {
    set_property file_type {SystemVerilog} $all_sv
    puts "  Set SystemVerilog on [llength $all_sv] files."
} else {
    puts "  WARNING: No .sv files found in sources_1!"
}

## ---- Add Constraints ----
puts "\n--- Adding XDC constraints ---"
add_files -fileset constrs_1 $xdc_file
puts "  Added: arty_s7_50.xdc"

## ---- Set Top Module ----
set_property top soc_top [current_fileset]
update_compile_order -fileset sources_1
puts "\n  Top module set to: soc_top"

## ---- Clocking Wizard IP (MMCM: 12 MHz → 100 MHz) ----
puts "\n--- Creating Clocking Wizard IP (clk_wiz_0) ---"
create_ip \
    -name clk_wiz \
    -vendor xilinx.com \
    -library ip \
    -version 6.0 \
    -module_name clk_wiz_0

set_property -dict [list \
    CONFIG.Component_Name                 {clk_wiz_0}                      \
    CONFIG.PRIM_SOURCE                    {Single_ended_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ                   {12.000}                          \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ     {100.000}                         \
    CONFIG.USE_LOCKED                     {true}                            \
    CONFIG.USE_RESET                      {false}                           \
    CONFIG.RESET_TYPE                     {ACTIVE_LOW}                      \
] [get_ips clk_wiz_0]

generate_target all [get_ips clk_wiz_0]
puts "  clk_wiz_0 IP created (12 MHz → 100 MHz MMCM)."

## ---- Synthesis Settings ----
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE Default [get_runs synth_1]

puts "\n============================================"
puts "  Project setup COMPLETE!"
puts "  Sources, IP and constraints are all added."
puts ""
puts "  Next steps (do these MANUALLY in Vivado):"
puts "    1. Check Sources panel — all .sv files should be listed"
puts "    2. Click 'Run Synthesis'  in the Flow Navigator"
puts "    3. Click 'Run Implementation'"
puts "    4. Click 'Generate Bitstream'"
puts "============================================"
