# Synthesis/resource check of the complete SoC without MIG or board I/O.
# This is not routed timing signoff and does not touch an existing project.
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here ../../..]]
set manifest [open [file join $here ../rtl/portable_soc.f] r]
set lines [split [read $manifest] "\n"]
close $manifest
foreach line $lines {
    set line [string trim $line]
    if {$line ne "" && ![string match "#*" $line]} {
        read_verilog -sv [file join $root $line]
    }
}
set fw [file normalize [file join $here ../software/build/ddr_loader.vmem]]
synth_design -top soc_core -part xc7s50csga324-1 -mode out_of_context \
    -generic [list FIRMWARE_FILE=$fw ENABLE_EXT_MEM=1 ENABLE_ICACHE=1 ENABLE_DCACHE=1 \
        DUAL_ISSUE=1 LOCAL_DCACHE=1 BUFFER_WRITES=1 STREAM_FETCH=1 UART_BAUD=921600]
create_clock -name clk_sys -period 40 [get_ports clk_sys]
set out [file join $here ddr_project throughput_synthesis_check]
file mkdir $out
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
foreach pattern {*g_icache* *g_local_cache*u_cache*} {
    set blocks [get_cells -hier -filter "REF_NAME =~ RAMB* && NAME =~ $pattern"]
    if {[llength $blocks] == 0} { error "No inferred cache BRAM: $pattern" }
    puts "THROUGHPUT_BRAM_PASS: $pattern = [llength $blocks] primitives"
}
puts "THROUGHPUT_SYNTH_PASS: board implementation and timing remain untested."
