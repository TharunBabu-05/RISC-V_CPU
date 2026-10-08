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
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33  PULLDOWN TRUE } [get_ports { rst_btn }]

## ---- UART ----
## USB-UART Interface
## uart_rxd_out = PC → FPGA (RX)
## uart_txd_in  = FPGA → PC (TX)
set_property -dict { PACKAGE_PIN R12   IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }]
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { uart_txd_in }]

## ---- LEDs (4x: LD2..LD5 on Arty S7 board) ----
## led[0] = LD2 (rst_n: CPU running)
## led[1] = LD3 (pll_locked: 25 MHz MMCM locked)
## led[2] = LD4 (off)
## led[3] = LD5 (off)
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN F13   IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN E13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

## ---- Timing Constraints ----
## Asynchronous I/O: buttons, LEDs, and UART (115200 baud is asynchronous to core clock)
set_false_path -from [get_ports rst_btn]
set_false_path -from [get_ports uart_rxd_out]
set_false_path -to   [get_ports uart_txd_in]
set_false_path -to   [get_ports {led[*]}]

## ---- Configuration options ----
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

## Internal VREF for Bank 34 (required for Arty S7)
set_property INTERNAL_VREF 0.675 [get_iobanks 34]
