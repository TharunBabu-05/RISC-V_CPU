# Rebuild the Arty S7 synthesis run and emit a compact utilization report.
set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir vivado_project rv32_soc_arty_s7.xpr]

open_project $project_file
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1

set run_status [get_property STATUS [get_runs synth_1]]
puts "SYNTHESIS_STATUS=$run_status"
if {![string match "*Complete*" $run_status]} {
    exit 1
}

open_run synth_1
report_utilization -file [file join $script_dir vivado_project synthesis_utilization_check.rpt]
exit 0
