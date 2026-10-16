# FPGA Porting Guide

The CPU and SoC are no longer tied to the Arty S7-50 top level. The hardware is
split into three layers:

| Layer | Module | Purpose |
|---|---|---|
| CPU | `cpu_top_soc` | RV32IM five-stage pipeline and external instruction/data buses |
| Portable SoC | `soc_core` | BRAM, UART, CLINT, PLIC, DMA, QSPI reader and address decoder |
| Board wrapper | `generic_fpga_top` or `soc_top` | Clock/reset adaptation, physical pins and vendor primitives |

`soc_core` contains no FPGA-vendor primitive. `soc_top` is retained as the
default Arty S7-50 wrapper. Define `PORTABLE_BUILD` in a non-Xilinx project to
exclude that wrapper and its `clk_wiz_0`/`STARTUPE2` dependencies completely.

## Porting To A New Board

1. Check that the FPGA has enough logic, DSP and block RAM for the selected
   configuration. The proven Arty image uses a 64 KiB parity-banked memory.
2. Add every file in `rtl/portable_soc.f` to the new FPGA project.
3. Define `PORTABLE_BUILD` and use `generic_fpga_top` as the top module when a stable system clock is
   already available.
4. Set `CLK_FREQ_HZ` to the actual clock supplied to the SoC. This parameter
   controls the UART divider; it is not merely documentation.
5. Set `UART_BAUD`, `BRAM_SIZE_BYTES` and `FIRMWARE_FILE` as required.
6. Create the board's pin and timing constraints for `clk`, `reset_n`, UART,
   QSPI and optional status outputs.
7. If a PLL is needed, make a small board wrapper around `soc_core` or
   `generic_fpga_top`. Keep the PLL and its lock/reset logic in that wrapper.
8. Run simulation, synthesize, inspect inferred memories, close timing and only
   then program the board.

The current flash reader toggles SCK every system-clock cycle, producing an SPI
clock of approximately `CLK_FREQ_HZ / 2`. Check the target flash limit. Add a
clock divider in `qspi_reader.sv` before using a high-frequency SoC clock.

## Generic Top-Level Ports

| Port | Direction | Meaning |
|---|---|---|
| `clk` | input | Stable SoC clock at `CLK_FREQ_HZ` |
| `reset_n` | input | Asynchronous active-low board reset; release is synchronized internally |
| `uart_tx`, `uart_rx` | output/input | 8N1 serial console |
| `qspi_cs`, `qspi_sck` | output | SPI flash chip select and clock |
| `qspi_dq[3:0]` | inout | Flash data pins; the current reader uses DQ0 as MOSI and DQ1 as MISO |
| `status[3:0]` | output | Running, clock-ready, UART TX activity and UART RX activity |

## Vendor Notes

- **AMD/Xilinx:** use the Arty `soc_top` as an example for Clocking Wizard and
  `STARTUPE2`. Other Xilinx boards need their own part, clock IP and XDC.
- **Intel/Altera:** generate a PLL in Platform Designer or the IP Catalog and
  connect its output/lock signal in a board wrapper. Use a QSF pin file.
- **Lattice:** instantiate the family PLL when required and provide LPF/PCF
  constraints. The memories are inferred RTL and carry common block-RAM hints.
- **Configuration flash:** some devices expose configuration-flash SCK as an
  ordinary pin; others require a startup primitive. If the on-board flash is
  unavailable to user logic, connect a separate SPI flash or leave QSPI unused.

Changing `BRAM_SIZE_BYTES` also requires linker-script and firmware-memory-map
changes. Keep it a power of two. A board with insufficient internal RAM should
use an external-memory controller rather than silently reducing the memory
while retaining the existing linker scripts.

## Validation

Run from `phase8/tb`:

```sh
make portable
make all
```

The portable test instantiates `generic_fpga_top` at 20 MHz, checks reset
synchronization, verifies propagation of the clock-dependent UART divisor and
confirms that the CPU begins executing from inferred BRAM.
