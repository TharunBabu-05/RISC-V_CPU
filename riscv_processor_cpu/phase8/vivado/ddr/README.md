# Arty S7-50 MIG Preset

`arty_s7_50_mig.prj` is the unmodified Digilent Arty S7-50 revision B.0
board preset downloaded from:

https://github.com/Digilent/vivado-boards/blob/master/new/board_files/arty-s7-50/B.0/mig.prj

The preset specifies the board's DDR3L x16 pins, 256 MiB geometry,
100 MHz system clock on R2, 4:1 PHY ratio, external buffered reference clock,
active-low system reset, and 128-bit AXI with no narrow bursts.
`create_ddr_project.tcl` supplies the 200 MHz reference from Clocking Wizard.
MIG generates the DDR pin and timing constraints from this preset; do not
duplicate them with an unrelated board's XDC.

Create a separate project from `phase8/software` with:

```powershell
make ddr_test
& "C:/Xilinx/Vivado/2020.2/bin/vivado.bat" -mode batch `
  -source ../vivado/create_ddr_project.tcl
```

Vivado creates `phase8/vivado/ddr_project/arty_s7_ddr_bringup/rv32_soc_arty_s7.xpr`
and generates Clock Wizard, MIG, and AXI Clock Converter IP. The script does
not launch synthesis, implementation, or bitstream generation. Open that XPR
and run those stages manually after reviewing the Sources and DDR constraints.
The 100 MHz clock is the top-level input named `sys_clk_i`, matching the MIG
XDC package pin constraint for R2.

For the diagnostic bitstream, set top to `arty_s7_ddr_top` and confirm the
BRAM initialization file is `software/build/ddr_test.vmem`. Keep the verified
Snake and bootloader image unchanged. After hardware programming, open PuTTY
at 115200 baud and wait for `DDR:PASS`. This diagnostic writes and reads DDR
from `0x80000000`; it is not a DOOM loader.

The XML's original ModuleName is a Digilent-generated instance name;
Vivado's IP module is created as `ddr3_mig`. Wrapper wiring follows the
Vivado 2020.2 generated instantiation template for this preset.

The 25 MHz CPU and MIG UI clocks are independent. `ddr_cdc.xdc` excludes only
the first calibration-status synchronizer input and the CPU-side AXI reset
synchronizer's asynchronous clear pins from setup/recovery analysis. Later
synchronizer stages, the CPU, AXI bridge, and MIG remain timed. The project
creation script adds this constraint to newly generated DDR projects.

For an already generated DDR project, use Vivado's Tcl Console while that
project is open (the path below assumes this repository location):

```tcl
set ddr_cdc_xdc C:/Users/tharu/RISC-V_CPU/riscv_processor_cpu/phase8/vivado/ddr/ddr_cdc.xdc
add_files -fileset constrs_1 $ddr_cdc_xdc
set_property USED_IN_SYNTHESIS false [get_files $ddr_cdc_xdc]
```

Then reset and rerun `impl_1` to update its timing result and bitstream.
The prior bitstream was written with negative timing slack and is not proof
that the DDR board test will run correctly. Do not constrain the complete
CPU and MIG clocks as asynchronous; this would hide real data paths.
