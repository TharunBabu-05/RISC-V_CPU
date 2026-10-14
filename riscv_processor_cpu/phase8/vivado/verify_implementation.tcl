# Place and route the synthesized Arty S7 design, then save signoff reports.
set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir vivado_project rv32_soc_arty_s7.xpr]

open_project $project_file
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1

set run_status [get_property STATUS [get_runs impl_1]]
puts "IMPLEMENTATION_STATUS=$run_status"
if {![string match "*Complete*" $run_status]} {
    exit 1
}

open_run impl_1
report_utilization -file [file join $script_dir vivado_project implementation_utilization_check.rpt]
report_timing_summary -file [file join $script_dir vivado_project implementation_timing_check.rpt]
exit 0
