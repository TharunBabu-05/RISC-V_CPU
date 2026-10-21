# Creates an isolated DDR bring-up project. Never launches synthesis or implementation.
# Run: vivado -mode batch -source create_ddr_project.tcl
set ddr_script_dir [file dirname [file normalize [info script]]]
set ddr_project_dir [file join $ddr_script_dir ddr_project arty_s7_ddr_bringup]
if {[info exists argc] && $argc > 0} {
    set ddr_project_dir [file normalize [lindex $argv 0]]
}
if {[file exists $ddr_project_dir]} {
    error "DDR project already exists: $ddr_project_dir. Open its .xpr, or pass a NEW directory."
}
set ddr_fw [file normalize [file join $ddr_script_dir ../software/build/ddr_test.vmem]]
if {[info exists argc] && $argc > 1} {
    set ddr_fw [file normalize [lindex $argv 1]]
}
if {![file exists $ddr_fw]} { error "First run make ddr_test in phase8/software" }
set ddr_profile baseline
if {[info exists argc] && $argc > 2} { set ddr_profile [lindex $argv 2] }
if {$ddr_profile ni {baseline perf}} { error "Unknown DDR profile: $ddr_profile" }
set ddr_generics "FIRMWARE_FILE=[file tail $ddr_fw]"
if {$ddr_profile eq "perf"} {
    append ddr_generics " ENABLE_ICACHE=1 DUAL_ISSUE=1 UART_BAUD=921600"
}
set ddr_preset [file join $ddr_script_dir ddr arty_s7_50_mig.prj]
if {![file exists $ddr_preset]} { error "Missing Digilent MIG board preset: $ddr_preset" }

# Reuse the verified CPU/BRAM/UART source list and board constraints.
set argc 1
set argv [list $ddr_project_dir]
source [file join $ddr_script_dir create_project.tcl]
set_property top arty_s7_ddr_top [current_fileset]
set_property generic $ddr_generics [current_fileset]
foreach name {rv_bus_to_axi128.sv arty_s7_ddr_top.sv} {
    add_files [file normalize [file join $ddr_script_dir ../rtl $name]]
}
add_files $ddr_fw
set_property file_type {Memory Initialization Files} [get_files $ddr_fw]
set ddr_cdc_xdc [file join $ddr_script_dir ddr ddr_cdc.xdc]
add_files -fileset constrs_1 $ddr_cdc_xdc
set_property USED_IN_SYNTHESIS false [get_files $ddr_cdc_xdc]
# Keep the reference clock constrained on the real top-level R2 input. MIG's
# generated XDC owns the R2 package pin and its 100 MHz primary clock.
# 25 MHz CPU and a buffered 200 MHz IDELAY reference. MIG independently uses
# the board's 100 MHz oscillator on R2. The board preset supplies DDR pins.
set_property -dict [list CONFIG.CLKOUT2_USED true \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 200.000] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name ddr3_mig
set_property CONFIG.XML_INPUT_FILE $ddr_preset [get_ips ddr3_mig]
generate_target all [get_ips ddr3_mig]

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name ddr_axi_cdc
set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.ADDR_WIDTH 28 \
    CONFIG.DATA_WIDTH 128 CONFIG.ID_WIDTH 4 CONFIG.ACLK_ASYNC 1 \
    CONFIG.SYNCHRONIZATION_STAGES 3] [get_ips ddr_axi_cdc]
generate_target all [get_ips ddr_axi_cdc]
update_compile_order -fileset sources_1
puts "DDR_PROJECT=[get_property DIRECTORY [current_project]]"
puts "TOP=arty_s7_ddr_top; profile=$ddr_profile; $ddr_generics"
puts "Project/IP generation only. Run synthesis, implementation and bitstream manually."
