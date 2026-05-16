#!/usr/bin/env dcshell -f

# dc_synth.tcl - Synopsys Design Compiler Synthesis Script for RV32 CPU
# Usage: dcshell -f dc_synth.tcl

set project_name "risc_v_cpu"
set rtl_dir "../rtl"
set constraint_file "./core_constraints.tcl"
set top_module "cpu_top"
set target_lib "NangateOpenCellLibrary"  # Example library; replace with actual PDK

# Initialize
analyze -format sverilog -lib WORK [glob $rtl_dir/*.sv]
elaborate $top_module -lib WORK -update

puts "Design Elaborated: $top_module"

# Set design environment
set_operating_conditions -max_leakage_power -min $target_lib
set_wire_load_model -name global $target_lib
set_wire_load_selection_group $target_lib

# Read constraints
source $constraint_file
set_max_fanout 32 $top_module

puts "Constraints Applied"

# Compile with optimization
puts "Starting Synthesis..."
compile -map_effort high -area_effort high -verbose

puts "\n=== POST-SYNTHESIS TIMING ==="
report_timing -max_paths 10 > timing_report.txt
report_timing

puts "\n=== POST-SYNTHESIS AREA ==="
report_area > area_report.txt
report_area

puts "\n=== DESIGN STATISTICS ==="
report_statistics

# Save netlist
write -format verilog -hierarchy -output cpu_synth.v

puts "Synthesis Complete!"
puts "Check timing_report.txt and area_report.txt for results."

exit
