# Standalone resource check only. Does not open or change a board project.
set here [file dirname [file normalize [info script]]]
read_verilog -sv [file join $here ../rtl/rv_ddr_cache.sv]
synth_design -top rv_ddr_cache -part xc7s50csga324-1 -mode out_of_context
set out [file join $here ddr_project cache_unit_check]
file mkdir $out
report_utilization -file [file join $out utilization.rpt]
set blocks [get_cells -hier -filter {REF_NAME =~ RAMB*}]
if {[llength $blocks] == 0} { error "DDR cache did not infer block RAM" }
puts "DDR_CACHE_BRAM_PASS: [llength $blocks] block RAM primitives; not a board timing signoff."
