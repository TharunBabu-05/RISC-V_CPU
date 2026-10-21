# Build only the isolated performance profile. Never programs hardware.
set script_dir [file dirname [file normalize [info script]]]
set project [file join $script_dir ddr_project arty_s7_ddr_perf rv32_soc_arty_s7.xpr]
open_project $project
set generics [get_property generic [current_fileset]]
foreach required {ENABLE_ICACHE=1 DUAL_ISSUE=1 UART_BAUD=921600} {
    if {[lsearch -exact $generics $required] < 0} { error "Missing performance generic: $required" }
}
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
}
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Performance synthesis did not complete"
}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "route_design Complete!"} {
    error "Performance implementation did not complete"
}
open_run impl_1
set reports [file join [get_property DIRECTORY [current_project]] validation]
file mkdir $reports
report_utilization -hierarchical -file [file join $reports utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $reports timing.rpt]
report_drc -file [file join $reports drc.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] == 0 || [llength $hold] == 0} { error "Missing timing paths" }
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {
    error "Timing failed: inspect validation/timing.rpt; no bitstream generated"
}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Performance bitstream did not complete"
}
puts "PERF_BUILD_COMPLETE: report and bitstream available; hardware not programmed."
close_project
