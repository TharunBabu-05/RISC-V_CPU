# Combine an already-generated FPGA bitstream and application flash image.
# This script does not run synthesis, implementation, or bitstream generation.
set script_dir [file dirname [file normalize [info script]]]

if {$argc < 2 || $argc > 3} {
    puts "Usage: vivado -mode batch -source generate_qspi_mcs.tcl -tclargs <soc_top.bit> <snake_flash.bin> ?output.mcs?"
    exit 1
}

set bitstream [file normalize [lindex $argv 0]]
set app_image [file normalize [lindex $argv 1]]
set output_file [file join $script_dir vivado_project rv32_soc_with_app.mcs]
if {$argc == 3} {
    set output_file [file normalize [lindex $argv 2]]
}

if {![file exists $bitstream]} { error "Bitstream not found: $bitstream" }
if {![file exists $app_image]} { error "Application image not found: $app_image" }

# 16 MiB flash. The FPGA configuration starts at zero; application data starts
# at 4 MiB, leaving ample space for the Spartan-7 configuration image.
write_cfgmem -force -format mcs -size 16 -interface SPIx4 \
    -loadbit "up 0x00000000 $bitstream" \
    -loaddata "up 0x00400000 $app_image" \
    -file $output_file

puts "QSPI_MCS=$output_file"
puts "APP_FLASH_OFFSET=0x00400000"
