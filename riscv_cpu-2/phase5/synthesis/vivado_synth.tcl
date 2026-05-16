#!/usr/bin/env tclsh

# vivado_synth.tcl - Xilinx Vivado Synthesis Script for RV32 CPU
# Usage: vivado -mode tcl -source vivado_synth.tcl

set project_name "risc_v_cpu"
set rtl_dir "../rtl"
set constraint_file "./core_constraints.tcl"
set top_module "cpu_top"
set target_part "xcu200-fsgd484-2-e"  # Example: UltraScale+ device

# Create project
create_project $project_name . -part $target_part -force

# Add RTL source files
foreach sv_file [glob $rtl_dir/*.sv] {
    add_files -fileset sources_1 $sv_file
}

# Add constraints
if {[file exists $constraint_file]} {
    add_files -fileset constrs_1 $constraint_file
}

# Set properties
set_property "top" $top_module [current_fileset]

# Synthesis
puts "Starting Synthesis..."
synth_design -top $top_module -mode out_of_context -verbose

# Report timing and area
puts "\n=== POST-SYNTHESIS TIMING ==="
report_timing_summary -file timing_summary.txt
report_timing -sort_by slack -max_paths 10 -file timing_paths.txt

puts "\n=== POST-SYNTHESIS AREA ==="
report_area -file area_summary.txt

# Save netlist
write_verilog -force cpu_synth.v

puts "Synthesis Complete!"
puts "Check timing_summary.txt and area_summary.txt for results."

exit
