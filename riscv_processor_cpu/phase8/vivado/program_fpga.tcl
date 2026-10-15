# Program the connected Arty S7 with the latest implemented bitstream.
set script_dir [file dirname [file normalize [info script]]]
set bitstream [file join $script_dir vivado_project \
    rv32_soc_arty_s7.runs impl_1 soc_top.bit]

if {![file exists $bitstream]} {
    puts stderr "Bitstream not found: $bitstream"
    exit 1
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set devices [get_hw_devices -quiet xc7s50_0]
if {[llength $devices] == 0} {
    set devices [get_hw_devices -quiet *xc7s50*]
}
if {[llength $devices] == 0} {
    puts stderr "No Arty S7 XC7S50 device found."
    close_hw_manager
    exit 1
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
refresh_hw_device $device
puts "PROGRAM_STATUS=Complete DEVICE=$device BITSTREAM=$bitstream"

close_hw_manager
exit 0
