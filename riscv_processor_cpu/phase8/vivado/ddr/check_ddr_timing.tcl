# Analyze the existing routed checkpoint with the DDR CDC exceptions.
# This does not rerun synthesis, implementation, or bitstream generation.
set script_dir [file dirname [file normalize [info script]]]
set routed [file normalize [file join $script_dir .. ddr_project arty_s7_ddr_bringup rv32_soc_arty_s7.runs impl_1 arty_s7_ddr_top_routed.dcp]]
if {![file exists $routed]} { error "Routed DDR checkpoint not found: $routed" }
open_checkpoint $routed
read_xdc [file join $script_dir ddr_cdc.xdc]
set ready_pins [get_pins -quiet -hierarchical -regexp {.*ready_pipe_reg\[0\]/D$}]
set reset_pins [get_pins -quiet -hierarchical -regexp {.*axi_sys_reset_pipe_reg\[[0-3]\]/CLR$}]
if {[llength $ready_pins] != 1 || [llength $reset_pins] != 4} {
    error "Unexpected DDR CDC endpoint count: ready=[llength $ready_pins], reset=[llength $reset_pins]"
}
set worst [get_timing_paths -max_paths 1]
if {[llength $worst] == 0} { error "No timed paths found" }
puts "DDR_CDC_WORST_SLACK=[get_property SLACK $worst]"
puts "DDR_CDC_WORST_START=[get_property STARTPOINT_PIN $worst]"
puts "DDR_CDC_WORST_END=[get_property ENDPOINT_PIN $worst]"
