## ============================================================
##  arty_s7_50.xdc  —  Xilinx Arty S7-50 Rev. E Pin Constraints
##  Board: Digilent Arty S7-50 (XC7S50-CSGA324)
##
##  Updated to match official Digilent Arty S7-50 Rev. E Master XDC
## ============================================================

## ---- System Clock: 12 MHz on-board oscillator (F14) ----
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports { clk_12mhz }]
create_clock -add -name sys_clk_pin -period 83.333 -waveform {0 41.667} [get_ports { clk_12mhz }]

## ---- Reset Button: BTN0 (G15) ----
## Mapped to BTN0 on Arty S7 Rev. E. Active-high logic in board,
## but our RTL uses active-low rst_n. 
## NOTE: If the button is physically active-high, you may need 
## to invert it in soc_top.sv or change this to LVCMOS33.
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports { rst_btn_n }]

## ---- UART ----
## USB-UART Interface
## uart_rxd_out = PC → FPGA (RX)
## uart_txd_in  = FPGA → PC (TX)
set_property -dict { PACKAGE_PIN R12   IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }]
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { uart_txd_in }]

## ---- LEDs (4x) ----
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN F13   IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN E13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

## ---- Timing Constraints ----
set_false_path -from [get_ports rst_btn_n]
set_input_delay  -clock [get_clocks sys_clk_pin] -max 0 [get_ports uart_rxd_out]
set_input_delay  -clock [get_clocks sys_clk_pin] -min 0 [get_ports uart_rxd_out]
set_output_delay -clock [get_clocks sys_clk_pin] -max 0 [get_ports uart_txd_in]
set_output_delay -clock [get_clocks sys_clk_pin] -min 0 [get_ports uart_txd_in]

## ---- Configuration options ----
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

## Internal VREF for Bank 34 (required for Arty S7)
set_property INTERNAL_VREF 0.675 [get_iobanks 34]
