# Add the transaction-bus RTL to an existing Phase 8 Vivado project.
# Run this from Tools -> Run Tcl Script while rv32_soc_arty_s7 is open.

if {[current_project -quiet] eq ""} {
    error "Open the rv32_soc_arty_s7 project before running this script."
}

set script_dir [file dirname [file normalize [info script]]]
set phase8_dir [file normalize "$script_dir/.."]
set phase8_rtl "$phase8_dir/rtl"
set cpu_rtl    [file normalize "$phase8_dir/../rtl"]

set transaction_sources [list \
    "$phase8_rtl/soc_core_txn.sv" \
    "$phase8_rtl/rv_bus_arbiter.sv" \
    "$phase8_rtl/rv_bus_to_axi_lite.sv" \
    "$cpu_rtl/mmu.sv" \
]

foreach source_file $transaction_sources {
    if {![file exists $source_file]} {
        error "Required source file is missing: $source_file"
    }

    set existing [get_files -quiet $source_file]
    if {[llength $existing] == 0} {
        add_files -fileset sources_1 -norecurse $source_file
        puts "Added: $source_file"
    } else {
        puts "Already present: $source_file"
    }
    set_property file_type SystemVerilog [get_files $source_file]
}

update_compile_order -fileset sources_1
reset_run synth_1
puts "Transaction-bus sources are installed. Run Synthesis again."
