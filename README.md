<div align="center">

<img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&weight=800&size=34&pause=900&color=00F5FF&center=true&vCenter=true&width=980&height=90&lines=RISC-V+RV32IM+CPU+Built+From+Scratch;5-Stage+Pipeline+%7C+Persistent+QSPI+Boot;Snake+Running+On+My+Own+Processor" alt="Animated project title" />

<br>

![Architecture](https://img.shields.io/badge/ISA-RV32IM%20Core-00f5ff?style=for-the-badge&logo=riscv&logoColor=white)
![Pipeline](https://img.shields.io/badge/Pipeline-5%20Stage-ff2bd6?style=for-the-badge)
![Board](https://img.shields.io/badge/FPGA-Arty%20S7--50-ffb000?style=for-the-badge&logo=xilinx&logoColor=white)
![Clock](https://img.shields.io/badge/Clock-25%20MHz-31ff70?style=for-the-badge)
![Firmware](https://img.shields.io/badge/Firmware-Hello%20%2B%20Snake-8a5cff?style=for-the-badge)
![Boot](https://img.shields.io/badge/Boot-QSPI%20Flash-ff6b35?style=for-the-badge)
![DMA](https://img.shields.io/badge/DMA-Memory%20%2B%20UART-00c853?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-End--to--End%20Verified-00d26a?style=for-the-badge)

<h3>Custom 32-bit RISC-V processor, synthesized onto FPGA and booting Snake permanently from flash.</h3>

<b>Power on. Validate flash. Copy to RAM. Run the game.</b>

<br><br>

<img src="proof/snake_qspi_boot_hardware.png" alt="Snake running on the custom RISC-V CPU after QSPI flash boot" width="70%">

<br>

<sub>Real RV32 instructions, real FPGA hardware, real persistent firmware.</sub>

</div>

---

## ✨ Project Snapshot

For a source-derived visual explanation of the CPU pipeline, FPGA SoC, firmware build,
verification flow, and UART runtime path, open
[`riscv_processor_cpu/docs/architecture_workflow.html`](riscv_processor_cpu/docs/architecture_workflow.html)
in a browser.

This repository contains a complete custom **RISC-V 32-bit CPU and FPGA SoC** project. The processor was designed from scratch in SystemVerilog, expanded through multiple architecture phases, deployed to a Digilent **Arty S7-50**, and verified with persistent firmware and a live UART application.

The current hardware milestone is fully physical: the FPGA configures from the board's QSPI flash, the resident Boot ROM validates an `RVF1` image with CRC-32, copies Snake into BRAM, executes `FENCE.I`, and starts the playable game over PuTTY. If flash is absent or damaged, the same loader enters UART recovery instead of executing an unsafe image.

| POWER-ON BOOT | INTEGRITY | RECOVERY | APPLICATION |
| :---: | :---: | :---: | :---: |
| QSPI configuration flash | Header + size + entry + CRC-32 | Flow-controlled UART upload | Interactive Snake in PuTTY |

```text
┌──────────────────────────────────────────────────────────────────────┐
│                    RISC-V RV32IM FPGA SoC                            │
├─────────────┬─────────────┬─────────────┬─────────────┬──────────────┤
│ IF          │ ID          │ EX          │ MEM         │ WB           │
│ Fetch       │ Decode      │ ALU/MulDiv  │ BRAM/UART   │ Register WB  │
└──────┬──────┴──────┬──────┴──────┬──────┴──────┬──────┴──────┬───────┘
       │             │             │             │             │
       ▼             ▼             ▼             ▼             ▼
  Branch logic   Hazard unit   Forwarding    Load/store     Retirement

              ┌─────────────────────────────────────┐
              │ 64KB unified Block RAM              │
              │ Port A: instruction fetch           │
              │ Port B: data load/store             │
              └──────────────────┬──────────────────┘
                                 │
                                 ▼
              ┌─────────────────────────────────────┐
              │ UART @ 0x1000_0000                  │
              │ 115200 baud, 8N1, PuTTY terminal    │
              └─────────────────────────────────────┘
```

<div align="center">
  <img src="architecture_animated.svg" alt="Animated architecture diagram" width="96%">
</div>

---

## 🏆 What Is Working Now

| Layer | Status | Notes |
| :--- | :---: | :--- |
| RV32I base integer ISA | ✅ | Arithmetic, branches, loads/stores, jumps, immediates |
| 5-stage pipeline | ✅ | IF, ID, EX, MEM, WB |
| Hazard handling | ✅ | Load-use stalls plus forwarding paths |
| M extension hardware | ✅ | Multi-cycle `mul` (3 cycles) and iterative `div`/`rem` (34 cycles) unit |
| FPGA timing closure | ✅ | QSPI-enabled build meets 25 MHz timing: WNS **+6.753 ns**, WHS **+0.021 ns**, 0 failing endpoints |
| CSR / exception infrastructure | ✅ | M/S/U privilege, delegated traps, `MRET`/`SRET`, vectored trap delivery, 64-bit counters |
| Physical Memory Protection | ✅ | Four PMP entries with OFF/TOR/NA4/NAPOT matching and lock enforcement |
| FPGA SoC integration | ✅ | Arty S7-50 top level with clocking, parity-banked BRAM, UART, CLINT, PLIC, LEDs; DMA integrated and awaiting the next Vivado run |
| Hardware interrupts | ✅ | 64-bit `mtime`/`mtimecmp`, machine software IRQ, and 5-source priority/claim controller |
| DMA controller | ✅ RTL | CPU-priority bus mastering, 8/16/32-bit memory copies, UART flow control, progress/error status, and PLIC completion IRQ; FPGA timing run pending |
| UART bring-up | ✅ | Hello + keyboard echo verified; simultaneous RX/read collision regression passes |
| UART bootloader | ✅ | CRC-32 checked application uploads to `0x0000_4000` without FPGA re-synthesis |
| QSPI flash boot | ✅ | Persistent `RVF1` image, CRC-checked RAM copy, automatic start, and UART recovery verified on FPGA |
| C firmware support | ✅ | `startup.S`, linker script, UART driver, aligned and cross-word byte/halfword/word accesses |
| Cache hierarchy | ✅ | Direct-mapped L1 I/D and L2 caches with refill, invalidation, write-through stores, and counters |
| Snake firmware | ✅ | Playable in PuTTY using `W/A/S/D`, `Q`, `R` |
| ISA compliance (riscv-tests) | ✅ | All applicable official tests pass: 66/66 FPGA, 77/77 research, 11/11 FPGA + FPU; zero N/A |
| Formal verification (riscv-formal) | ✅ | 52/52 checks pass on the FPGA core: every RV32IM instruction proven against the ISA model |
| F extension / RVV subset | ✅ | IEEE-754 RV32F unit and RVV 1.0 integer subset in the research core (not in the FPGA build) |

---

## ⚡ Persistent Boot: Hardware Proof

The complete chain is verified on the Arty S7-50: the combined MCS image was
programmed and verified in the 128-Mbit configuration flash, the Spartan-7
configured successfully, and Snake ran from the application copied into BRAM
by the custom Boot ROM.

<table>
  <tr>
    <td width="50%" align="center"><b>1. Flash programmed and verified</b></td>
    <td width="50%" align="center"><b>2. FPGA configured from QSPI</b></td>
  </tr>
  <tr>
    <td><img src="proof/qspi_flash_programmed.png" alt="Vivado reports QSPI flash programming and verification completed successfully"></td>
    <td><img src="proof/fpga_programmed_qspi.png" alt="Vivado Hardware Manager shows the Spartan-7 and S25FL128S configuration flash programmed"></td>
  </tr>
</table>

<div align="center">
  <b>3. Persistent firmware executed on the custom CPU</b><br><br>
  <img src="proof/snake_qspi_boot_hardware.png" alt="Snake game running in PuTTY after persistent QSPI boot" width="72%">
</div>

```text
QSPI @ 0x0040_0000 -> RVF1 header -> CRC-32 -> BRAM @ 0x0000_4000
                    -> FENCE.I -> application entry -> RISC-V Snake
```

---

## ✅ Synthesis & Implementation Proof

Vivado 2020.2 results for the hardened `rv32_soc_arty_s7` project
(`xc7s50csga324-1`). The current QSPI-enabled build completes synthesis,
implementation, bitstream generation, flash programming, and physical-board
execution successfully.

### Synthesis — `synth_1` complete

<div align="center">
  <img src="proof/vivado_synthesis_design_runs_2.png" alt="Vivado Design Runs: updated synth_1 and impl_1 resource usage" width="96%">
</div>

| Resource | Used | Available | Utilization |
| :--- | ---: | ---: | ---: |
| Slice LUTs | 6,733 | 32,600 | 20.65 % |
| Flip-flops | 4,315 | 65,200 | 6.62 % |
| Block RAM tiles | 32 | 75 | 42.7 % |
| DSP slices | 4 | 120 | 3.3 % |

### Implementation — all timing constraints met

<div align="center">
  <img src="proof/vivado_implementation_timing_met_2.png" alt="Updated Vivado Design Timing Summary: all user specified timing constraints are met" width="96%">
</div>

| Check | Worst slack | Total negative slack | Failing endpoints |
| :--- | ---: | ---: | ---: |
| Setup | **+6.753 ns** | 0.000 ns | 0 / 13,303 |
| Hold | **+0.021 ns** | 0.000 ns | 0 / 13,303 |
| Pulse width | +16.667 ns | 0.000 ns | 0 / 4,387 |

### Before vs after the timing fix

| | Before | After |
| :--- | :---: | :---: |
| Worst negative slack @ 25 MHz | **−61.314 ns** (51 failing endpoints) | **+6.753 ns** (0 failing) |
| Slice LUTs | 9,683 | 6,733 after implementation |
| Timing status | Constraints **not** met | All constraints met |

---

## 🎮 The Moment It Became Real

The latest milestone is the one that matters most emotionally and technically:

> A custom RISC-V CPU, running on FPGA, executing your own firmware, drawing a live Snake game over UART.

```text
 RISC-V Snake  |  Score: 60  |  Controls: W=Up  S=Down  A=Left  D=Right  Q=Quit

 +--------------------------------------+
 |                                      |
 |              *                       |
 |                                      |
 |                 +-----------------+  |
 |                 |   GAME  OVER!   |  |
 |                 |   Score: 60     |  |
 |                 | Press R to retry|  |
 |                 +-----------------+  |
 |                                      |
 +--------------------------------------+
```

This is the first game running on the processor.

---

## 🧠 Core Architecture

### CPU Pipeline

| Stage | Purpose |
| :---: | :--- |
| **IF** | Fetch instruction from BRAM using the program counter |
| **ID** | Decode opcode, read registers, generate immediates, detect hazards |
| **EX** | ALU operations, branch resolution, jump target generation, mul/div issue |
| **MEM** | Data memory and memory-mapped peripheral access |
| **WB** | Register file writeback and retirement |

### SoC Memory Map

| Address Range | Device | Description |
| :--- | :--- | :--- |
| `0x0000_0000` - `0x0000_FFFF` | Unified BRAM | Firmware, data, `.bss`, stack |
| `0x0200_0000` - `0x0200_FFFF` | CLINT | `msip`, 64-bit `mtimecmp`, 64-bit `mtime` |
| `0x0C00_0000` - `0x0C3F_FFFF` | PLIC | Priority, pending, enable, threshold, claim/complete |
| `0x1000_0000` - `0x1000_000F` | UART | TX, RX, status registers |
| `0x1000_1000` - `0x1000_100F` | QSPI reader | Flash address, byte data, control/status, peripheral ID |
| `0x1000_2000` - `0x1000_201F` | DMA | Source, destination, length, control, status, progress, ID, remaining bytes |

### DMA Data Movement

The Phase 8 SoC includes a synthesizable single-channel bus-master DMA engine.
Firmware programs a source address, destination address, byte length, transfer
width, and independent source/destination increment controls. The DMA then
uses data-bus cycles that the CPU is not using, so instruction execution can
continue without adding a stall/ready signal to the existing pipeline.

Current RTL integration verifies BRAM-to-BRAM copies and flow-controlled
BRAM-to-UART transmission. Fixed-address endpoints make the same engine usable
for RX/TX FIFOs in future SPI, display, VGA, or external-memory peripherals;
their ready signals are added to the SoC arbiter just like UART readiness.
Completion and errors are sticky, invalid addresses terminate instead of
hanging, and interrupt-enabled transfers arrive through PLIC source ID 5.
Bare-metal helpers are provided in
[`dma.h`](riscv_processor_cpu/phase8/software/dma.h).

### FPGA Top Level

The active board deployment lives in:

- [`riscv_processor_cpu/phase8/rtl/soc_top.sv`](riscv_processor_cpu/phase8/rtl/soc_top.sv)
- [`riscv_processor_cpu/phase8/rtl/cpu_top_soc.sv`](riscv_processor_cpu/phase8/rtl/cpu_top_soc.sv)
- [`riscv_processor_cpu/phase8/rtl/bram.sv`](riscv_processor_cpu/phase8/rtl/bram.sv)
- [`riscv_processor_cpu/phase8/rtl/uart.sv`](riscv_processor_cpu/phase8/rtl/uart.sv)
- [`riscv_processor_cpu/phase8/rtl/clint.sv`](riscv_processor_cpu/phase8/rtl/clint.sv)
- [`riscv_processor_cpu/phase8/rtl/plic.sv`](riscv_processor_cpu/phase8/rtl/plic.sv)
- [`riscv_processor_cpu/phase8/constraints/arty_s7_50.xdc`](riscv_processor_cpu/phase8/constraints/arty_s7_50.xdc)

---

## 🛠️ Hardware Bring-Up Fixes

These were the key real-board issues solved during FPGA deployment:

### 1. MMCM Clock Reality Check

The Arty S7 board clock is **12 MHz**. The clocking wizard configuration generates:

```text
12 MHz x 62.5 / 30 = 25 MHz
```

So the SoC UART is configured with:

```systemverilog
.CLK_FREQ(25_000_000),
.BAUD_RATE(115_200)
```

### 2. UART RX Floating Pin

The UART RX line must idle high. The FPGA input pin needed an internal pull-up:

```tcl
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { uart_rx }];
```

Without this, the UART receiver could see false start bits and inject garbage.

### 3. Byte-Level C Firmware Support

Assembly hello firmware worked with word operations, but C strings require byte loads and stores. The SoC now handles:

- `SB`, `SH`, `SW`
- `LB`, `LBU`, `LH`, `LHU`, `LW`

This was essential for `snake.c`, `uart_puts()`, strings, cursor movement, and game drawing.

### 4. Timing Closure — Single-Cycle Dividers

The first implementation missed timing by **61 ns** at 25 MHz (40 ns clock period). Two dividers computed a full 32-bit quotient in one clock cycle — `muldiv.sv` for `div`/`rem` and the FPU stub for `fdiv` — producing a ~100 ns path through 335 logic levels.

The fix:

- `muldiv.sv` registers its operands, multiplies in 3 cycles with a single 33×33 signed multiplier, and divides with a radix-2 restoring divider that produces one quotient bit per cycle (34 cycles).
- The FPU stub's divider was removed from the board build (the FPU now uses its own iterative FDIV/FSQRT and is not part of the FPGA SoC by default).

Result: the current QSPI-enabled design closes timing with **+6.753 ns setup slack** and **+0.021 ns hold slack**. See [Synthesis & Implementation Proof](#-synthesis--implementation-proof).

### 5. UART RX Read/Arrival Collision

RX arrival now has priority when a CPU read and a newly completed UART byte occur in the same cycle. The replacement byte remains valid instead of being silently cleared.

### 6. Physical Memory Protection

The core now implements four PMP entries with OFF, TOR, NA4 and NAPOT regions, lowest-entry priority, machine-mode bypass rules, lock bits, and instruction/load/store access-fault generation.

### 7. Hardware Misaligned Accesses

Scalar byte, halfword and word operations can cross a 32-bit word boundary. The FPGA memory uses even/odd true dual-port BRAM banks so both adjacent words are available in one cycle while still mapping to block RAM.

### 8. Supervisor Privilege

The privileged architecture now supports M/S/U modes, trap and interrupt delegation, supervisor CSRs and aliases, `SRET`, Sv32 permission checks, `SUM`, `MXR`, `TVM`, and `TSR` behavior.

### 9. Functional Cache Hierarchy

The research core now has direct-mapped L1 instruction/data caches and a unified L2 with refill, write-through stores, invalidation and hit/miss counters. The backing DRAM controller is a synthesizable zero-wait model; a physical DDR PHY remains board-specific work.

---

## 📁 Repository Map

```text
RISC-V_CPU/
├── README.md                         # Main showcase and quickstart
├── proof/                            # Timing, flash programming, FPGA, and runtime proof
├── riscv-tests/                      # Submodule: official ISA tests (git submodule update --init --recursive)
└── riscv_processor_cpu/
    ├── rtl/                          # Main advanced CPU architecture modules
    │   ├── cpu_top.sv
    │   ├── alu.sv
    │   ├── control_unit.sv
    │   ├── hazard.sv
    │   ├── muldiv.sv
    │   ├── csr_file.sv
    │   ├── branch_predictor.sv
    │   ├── icache.sv / dcache.sv
    │   ├── mmu.sv
    │   ├── fpu_unit.sv
    │   └── vector_unit.sv
    ├── tb/                           # Testbenches + Python reference models + run_regression.py
    ├── docs/                         # Architecture and verification notes
    ├── formal/riscv-formal/          # riscv-formal setup for the FPGA core
    ├── phase5/compliance/            # riscv-tests runner and results
    ├── phase5/                       # Synthesis templates and Phase 5 report
    └── phase8/                       # FPGA SoC deployment
        ├── rtl/                      # Arty S7 SoC RTL
        ├── software/                 # Bare-metal firmware
        ├── constraints/              # Arty S7 pin constraints
        ├── tb/                       # SoC and UART tests
        └── vivado/                   # Vivado project
```

---

## 🚀 Run It On The Arty S7-50

### Persistent QSPI Boot Flow

The SoC now includes a synthesized Boot ROM and a read-only controller for the
Arty S7 configuration flash. The Boot ROM validates an `RVF1` image stored at
flash offset `0x0040_0000`, copies it to BRAM at `0x0000_4000`, checks CRC-32,
and starts it automatically. Invalid or missing firmware enters UART recovery.

Before your one-time Vivado synthesis, install the Boot ROM:

```powershell
cd riscv_processor_cpu\phase8\software
make bootloader_program
```

After you generate the new `soc_top.bit` in Vivado, build the persistent Snake
image and MCS file:

```powershell
make flash_image
make qspi_mcs
```

Program `riscv_processor_cpu/phase8/vivado/vivado_project/rv32_soc_with_app.mcs`
as the Arty S7 configuration-memory image, verify it, select QSPI boot, and
power-cycle the board. See the
[Phase 8 deployment guide](riscv_processor_cpu/phase8/README.md) for image
format, recovery behavior, and an explicit `BITSTREAM=...` example.

### Fast UART Recovery Flow

The FPGA SoC now has a resident QSPI/UART Boot ROM. Install it into the
bitstream once:

```powershell
cd riscv_processor_cpu\phase8\software
make bootloader_program
```

Reset `synth_1`, generate the bitstream and program the FPGA. For later Snake
updates, close PuTTY and run:

```powershell
make app
make upload PORT=COM4
```

After the uploader reports `RVBL:OK`, reopen PuTTY and press `G`. The loader
receives the relocated image at `0x0000_4000`, checks its size and CRC-32,
executes `FENCE.I`, and transfers control to the application. Application-only
updates no longer require a Vivado rebuild.

Bootloader v3 combines QSPI auto-boot with the existing 16-byte hardware RX
FIFO and 32-byte acknowledged UART blocks. The PC does not send the next block
until the CPU confirms the previous one was stored, and any loss of
synchronization reports the exact byte offset.
The uploader uses the hardware-verified 2 ms inter-byte gap by default. The
delay can still be overridden with `UPLOAD_DELAY=<milliseconds>` when testing
another USB-UART adapter.

The UART image is volatile. BTN0 restarts QSPI validation and a power cycle or
FPGA reprogramming discards the UART-loaded copy. See the
[Phase 8 deployment guide](riscv_processor_cpu/phase8/README.md) for commands,
protocol details and the direct-BRAM recovery workflow.

### 1. Open The Firmware Folder

```powershell
cd riscv_processor_cpu\phase8\software
```

### 2. Choose A Firmware

#### Hello World + Echo

Use this to verify UART, reset, BRAM boot, and keyboard input:

```powershell
make hello_program
```

#### Snake Game

Use this to install the playable game:

```powershell
make program
```

Both commands copy the selected program into:

```text
riscv_processor_cpu/phase8/rtl/firmware.vmem
```

### 3. Reset Vivado Synthesis

Vivado embeds `firmware.vmem` into BRAM during **synthesis**, not at the final bitstream step.

When directly replacing `firmware.vmem` or installing a new bootloader:

1. Open the Vivado project:

   ```text
   riscv_processor_cpu/phase8/vivado/vivado_project/rv32_soc_arty_s7.xpr
   ```

2. In **Design Runs**, right-click `synth_1`.
3. Click **Reset Runs**.
4. Click **Generate Bitstream**.
5. Program the device with `soc_top.bit`.
6. Press **BTN0** on the Arty S7 to boot the CPU.

### 4. PuTTY Setup

| Setting | Value |
| :--- | :--- |
| Connection | Serial |
| Port | `COM4` |
| Speed | `115200` |
| Data | 8 bits |
| Parity | None |
| Stop bits | 1 |
| Flow control | None |
| Local echo | Force off |
| Local line editing | Force off |
| Window size | 80 x 25 or larger |

---

## 🎯 Firmware Programs

| Firmware | Source | Command | Purpose |
| :--- | :--- | :--- | :--- |
| Hello + Echo | [`hello_asm.S`](riscv_processor_cpu/phase8/software/hello_asm.S) | `make hello_program` | Hardware bring-up and UART proof |
| Snake | [`snake.c`](riscv_processor_cpu/phase8/software/snake.c) | `make program` | Interactive game on the custom CPU |
| UART-loaded Snake | [`snake.c`](riscv_processor_cpu/phase8/software/snake.c) | `make app`, then `make upload PORT=COM4` | CRC-checked update without re-synthesis |
| QSPI-persistent Snake | [`snake.c`](riscv_processor_cpu/phase8/software/snake.c) | `make flash_image`, then `make qspi_mcs` | Automatic CRC-checked boot after power-on |

Snake controls:

| Key | Action |
| :---: | :--- |
| `W` | Up |
| `A` | Left |
| `S` | Down |
| `D` | Right |
| `Q` | Quit |
| `R` | Retry after game over |

---

## 🧪 Verification And Testing

| Layer | Command | Result |
| :--- | :--- | :--- |
| Directed + unit testbenches | `make regress` | 26/26 pass (incl. PMP, S-mode delegation, unaligned BRAM, 43,013 FPU and 12,200 vector vectors) |
| UART loopback + collision | UART testbench | 20/20 bytes pass, including simultaneous receive/read |
| UART bootloader | `tb_bootloader.sv` | Upload, CRC-32 verification, `FENCE.I`, jump and `APP:OK` pass |
| QSPI Boot ROM | `tb_qspi_boot.sv` | Valid copy/boot, corrupt-image rejection, blocked unsafe jump, and UART recovery pass |
| CLINT + PLIC | Directed unit and SoC-map testbenches | `msip`, `mtimecmp`, priority, threshold, claim/complete, and CPU `mip` delivery pass |
| DMA controller | Unit + full SoC integration testbenches | Tail widths, fixed/incrementing addresses, backpressure, errors, BRAM copy, UART streaming, and PLIC ID 5 pass |
| Official riscv-tests (ISA compliance) | `make compliance` | FPGA 66/66, research 77/77, FPGA + FPU 11/11; **154/154 total, zero N/A** |
| riscv-formal (formal, FPGA core) | `make formal` | 52/52 checks pass |
| Timing closure (Vivado, 25 MHz) | — | QSPI build: WNS +6.753 ns, WHS +0.021 ns, 0 failing endpoints |
| FPGA bitstream | Vivado 2020.2 | Synthesis, placement, routing and `write_bitstream` complete with 0 errors |
| On the board | — | QSPI flash programmed and verified; FPGA configured; persistent Snake boot running on Arty S7-50 |

The verification flows found and fixed real bugs along the way, including wrong-path fetch from stale branch
predictions, stale operands behind cache misses, `minstret` timing, UART RX collisions, PMP corner cases,
cross-word memory accesses, and M/S/U privilege transitions. Details:
[compliance](riscv_processor_cpu/docs/phase5_compliance.md),
[formal](riscv_processor_cpu/docs/phase5_formal_verification.md),
[FPU / vector](riscv_processor_cpu/docs/fp_extension.md).

Useful references:

Run the complete Phase 8 interrupt-controller suite with
`make -C riscv_processor_cpu/phase8/tb`.

- [`riscv_processor_cpu/docs/architecture_overview.md`](riscv_processor_cpu/docs/architecture_overview.md)
- [`riscv_processor_cpu/docs/isa_coverage.md`](riscv_processor_cpu/docs/isa_coverage.md)
- [`riscv_processor_cpu/docs/phase5_formal_verification.md`](riscv_processor_cpu/docs/phase5_formal_verification.md)
- [`riscv_processor_cpu/docs/phase5_compliance.md`](riscv_processor_cpu/docs/phase5_compliance.md)
- [`riscv_processor_cpu/phase8/README.md`](riscv_processor_cpu/phase8/README.md)

---

## 🧰 Toolchain

| Tool | Role |
| :--- | :--- |
| SystemVerilog | CPU, SoC, UART, BRAM RTL |
| Vivado 2020.2 | FPGA synthesis, implementation, bitstream |
| Arty S7-50 | Physical FPGA target |
| `riscv-none-elf-gcc` | Bare-metal firmware build |
| Icarus Verilog / VVP | Simulation |
| PuTTY | UART terminal |
| SymbiYosys + riscv-formal | Formal verification of the FPGA core |
| riscv-tests | Official ISA compliance suites |
| Python | Reference models (FPU, vector) and test runners |

---

## 🧭 Project Timeline

```mermaid
timeline
    title RISC-V CPU Project Journey
    CPU Core : RV32I base datapath
             : Register file, ALU, decode, memory
    Pipeline : IF / ID / EX / MEM / WB
             : Hazards and forwarding
    ISA Growth : M extension
               : CSR and exception infrastructure
               : Caches, MMU, FP, vector research blocks
    Verification : Simulation and reference models
                 : riscv-tests compliance
                 : riscv-formal proofs
    FPGA SoC : Arty S7-50 top level
             : 64KB BRAM
             : Memory-mapped UART
    Firmware : Hello World + Echo
             : Snake game in bare-metal C
    Milestone : First game running on the custom CPU
```

---

## ⚡ LED Diagnostics

| LED | Meaning |
| :---: | :--- |
| LD0 | CPU released from reset |
| LD1 | PLL/MMCM locked |
| LD2 | UART TX activity |
| LD3 | UART RX activity |

---

## 🌈 Why This Project Matters

Building a CPU is one level of understanding.

Pipelining it is another.

Putting it on an FPGA, discovering real timing, reset, UART, BRAM, and C runtime issues, fixing them, and then running a game on it is the point where the processor becomes real hardware.

This repository captures that full path:

```text
Idea -> RTL -> Pipeline -> ISA -> Verification -> SoC -> FPGA -> Firmware -> Game
```

---

## 🙌 Credits

Special thanks to the AI tools and debugging assistants that helped along the journey, but the milestone belongs to the builder who kept pushing through every hardware bug until the board finally played the game.

<div align="center">

<br>

<img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&weight=700&size=24&pause=1200&color=31FF70&center=true&vCenter=true&width=980&height=70&lines=From+RTL+to+FPGA.;From+Firmware+to+Game.;A+Processor+That+Actually+Runs." alt="Closing animation" />

<br>

**RV32IM CPU • Arty S7-50 • UART Snake • Hardware Verified**

</div>
