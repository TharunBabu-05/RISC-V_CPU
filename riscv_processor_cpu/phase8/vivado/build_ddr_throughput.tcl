# Fresh build of the isolated throughput profile; never programs hardware.
set script_dir [file dirname [file normalize [info script]]]
set project [file join $script_dir ddr_project arty_s7_ddr_throughput rv32_soc_arty_s7.xpr]
open_project $project
set generics [get_property generic [current_fileset]]
foreach required {ENABLE_ICACHE=1 ENABLE_DCACHE=1 DUAL_ISSUE=1 UART_BAUD=921600 LOCAL_DCACHE=1 BUFFER_WRITES=1 STREAM_FETCH=1} {
    if {[lsearch -exact $generics $required] < 0} { error "Missing throughput generic: $required" }
}
set bitfile [file join [get_property DIRECTORY [get_runs impl_1]] arty_s7_ddr_top.bit]
if {[file exists $bitfile]} {
    error "Existing throughput bitstream preserved. Archive it and use a new build directory before rebuilding."
}
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "Throughput synthesis failed" }
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "route_design Complete!"} { error "Throughput implementation failed" }
open_run impl_1
set reports [file join [get_property DIRECTORY [current_project]] validation]
file mkdir $reports
report_utilization -hierarchical -file [file join $reports utilization.rpt]
set timing [report_timing_summary -report_unconstrained -return_string -file [file join $reports timing.rpt]]
report_drc -file [file join $reports drc.rpt]
report_route_status -file [file join $reports route.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] == 0 || [llength $hold] == 0} { error "Missing timing paths" }
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0 ||
    ![string match "*All user specified timing constraints are met*" $timing]} {
    error "Timing failed (including pulse width): inspect validation/timing.rpt; no bitstream generated"
}
set severe [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}]
if {[llength $severe]} { error "Blocking DRC violations: $severe; no bitstream generated" }
puts "THROUGHPUT_ROUTED: setup=[get_property SLACK $setup] ns hold=[get_property SLACK $hold] ns"
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} { error "Throughput bitstream failed" }
puts "THROUGHPUT_BUILD_COMPLETE: $bitfile; hardware not programmed."
close_project
