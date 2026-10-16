# Rebuild the Arty S7 synthesis run and emit a compact utilization report.
set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir vivado_project rv32_soc_arty_s7.xpr]

open_project $project_file

# Keep an existing Vivado project synchronized with RTL added after the project
# was first created. Fresh projects already receive these in create_project.tcl.
set phase8_rtl [file normalize [file join $script_dir .. rtl]]
foreach source_name {clint.sv plic.sv qspi_reader.sv} {
    set source_file [file join $phase8_rtl $source_name]
    if {[llength [get_files -quiet $source_name]] == 0} {
        add_files -fileset sources_1 -norecurse $source_file
        set_property file_type {SystemVerilog} [get_files $source_name]
        puts "ADDED_SOURCE=$source_file"
    }
}
update_compile_order -fileset sources_1

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
