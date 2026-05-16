## ============================================================
##  create_project.tcl  —  Vivado Project Creation Script
##  Board: Xilinx Arty S7-50 (XC7S50-CSGA324)
##
##  Usage (from Vivado Tcl Console or command line):
##    vivado -mode tcl -source create_project.tcl
##  OR open Vivado → Tools → Run Tcl Script → select this file
##
##  This script:
##    1. Creates a new Vivado project
##    2. Adds all Phase 8 RTL and shared RTL sources
##    3. Adds the Arty S7-50 pin constraints
##    4. Creates a Clocking Wizard IP (MMCM: 12 MHz → 100 MHz)
##    5. Sets the top module to soc_top
##    6. Runs synthesis and implementation
##    7. Generates the programming bitstream
## ============================================================

## ---- Project Settings ----
set project_name  "rv32_soc_arty_s7"
set project_dir   [file normalize "./vivado_project"]
set target_part   "xc7s50csga324-1"   ;# Arty S7-50

## ---- Source Directories ----
set rtl_dir       [file normalize "../rtl"]        ;# Original CPU RTL
set phase8_rtl    [file normalize "./rtl"]         ;# Phase 8 SoC RTL

## ---- Create Project ----
create_project $project_name $project_dir -part $target_part -force
set_property board_part digilentinc.com:arty-s7-50:part0:1.1 [current_project]

## ---- Add Phase 8 SoC RTL Files ----
set soc_sources [list \
    $phase8_rtl/cpu_top_soc.sv   \
    $phase8_rtl/soc_top.sv       \
    $phase8_rtl/uart_tx.sv       \
    $phase8_rtl/uart_rx.sv       \
    $phase8_rtl/uart.sv          \
    $phase8_rtl/bram.sv          \
]

## ---- Add Shared CPU RTL Files (from original rtl/) ----
set cpu_sources [list \
    $rtl_dir/alu.sv              \
    $rtl_dir/branch_predictor.sv \
    $rtl_dir/control_unit.sv     \
    $rtl_dir/csr_file.sv         \
    $rtl_dir/fp_regfile.sv       \
    $rtl_dir/fpu_unit.sv         \
    $rtl_dir/hazard.sv           \
    $rtl_dir/imm_gen.sv          \
    $rtl_dir/interrupt_unit.sv   \
    $rtl_dir/muldiv.sv           \
    $rtl_dir/regfile.sv          \
    $rtl_dir/vector_regfile.sv   \
    $rtl_dir/vector_unit.sv      \
]

## Add all source files
add_files -fileset sources_1 $soc_sources
add_files -fileset sources_1 $cpu_sources

## Set file type to SystemVerilog
set_property file_type {SystemVerilog} [get_files *.sv]

## ---- Add Constraints File ----
add_files -fileset constrs_1 [file normalize "./constraints/arty_s7_50.xdc"]

## ---- Set Top Module ----
set_property top soc_top [current_fileset]

## ---- Create Clocking Wizard IP (12 MHz → 100 MHz via MMCM) ----
## This generates the clk_wiz_0 module referenced in soc_top.sv
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0

set_property -dict [list \
    CONFIG.Component_Name        {clk_wiz_0}           \
    CONFIG.PRIM_SOURCE           {Single_ended_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ          {12.000}               \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000}         \
    CONFIG.USE_LOCKED            {true}                 \
    CONFIG.USE_RESET             {false}                \
    CONFIG.RESET_TYPE            {ACTIVE_LOW}           \
] [get_ips clk_wiz_0]

generate_target all [get_ips clk_wiz_0]

## ---- Synthesis Settings ----
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE Default    [get_runs synth_1]

## ---- Run Synthesis ----
puts "\n============================================"
puts " Starting Synthesis..."
puts "============================================\n"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis FAILED! Check the Messages window."
}
puts " Synthesis COMPLETE!"
open_run synth_1

## Print resource utilization
report_utilization -file $project_dir/utilization_synth.rpt
report_timing_summary -max_paths 10 -file $project_dir/timing_synth.rpt

## ---- Run Implementation ----
puts "\n============================================"
puts " Starting Implementation..."
puts "============================================\n"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation FAILED! Check the Messages window."
}
puts " Implementation COMPLETE!"
open_run impl_1

## ---- Final Reports ----
report_utilization       -file $project_dir/utilization_impl.rpt
report_timing_summary    -max_paths 20 -file $project_dir/timing_impl.rpt
report_power             -file $project_dir/power.rpt

## ---- Bitstream Location ----
set bitstream "$project_dir/${project_name}.runs/impl_1/soc_top.bit"
puts "\n============================================"
puts " DONE! Bitstream: $bitstream"
puts " To program: Open Hardware Manager → Program Device"
puts "============================================\n"
