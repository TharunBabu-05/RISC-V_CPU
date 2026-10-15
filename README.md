<div align="center">

<img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&weight=800&size=34&pause=900&color=00F5FF&center=true&vCenter=true&width=980&height=90&lines=RISC-V+RV32IM+CPU+Built+From+Scratch;5-Stage+Pipeline+%7C+FPGA+SoC+%7C+UART+Firmware;Snake+Game+Running+On+My+Own+Processor" alt="Animated title" />

<br>

![Architecture](https://img.shields.io/badge/ISA-RV32IM%20Core-00f5ff?style=for-the-badge&logo=riscv&logoColor=white)
![Pipeline](https://img.shields.io/badge/Pipeline-5%20Stage-ff2bd6?style=for-the-badge)
![Board](https://img.shields.io/badge/FPGA-Arty%20S7--50-ffb000?style=for-the-badge&logo=xilinx&logoColor=white)
![Clock](https://img.shields.io/badge/Clock-25%20MHz-31ff70?style=for-the-badge)
![Firmware](https://img.shields.io/badge/Firmware-Hello%20%2B%20Snake-8a5cff?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Hardware%20Verified-00d26a?style=for-the-badge)

<h3>Custom 32-bit RISC-V processor, synthesized onto FPGA, booting real bare-metal firmware.</h3>

<b>Final proof:</b> the CPU runs an interactive UART Snake game in PuTTY on the Arty S7-50.

</div>

---

## ✨ Project Snapshot

For a source-derived visual explanation of the CPU pipeline, FPGA SoC, firmware build,
verification flow, and UART runtime path, open
[`riscv_processor_cpu/docs/architecture_workflow.html`](riscv_processor_cpu/docs/architecture_workflow.html)
in a browser.

This repository contains a complete custom **RISC-V 32-bit CPU and FPGA SoC** project. The processor was designed from scratch in SystemVerilog, expanded through multiple architecture phases, deployed to a Digilent **Arty S7-50**, and verified with real firmware over UART.

The current hardware milestone is no longer just simulation: the CPU boots from on-chip BRAM, talks through a memory-mapped UART peripheral, accepts keyboard input from PuTTY, and runs a playable **Snake game** compiled as bare-metal firmware.

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
| FPGA timing closure | ✅ | All constraints met at 25 MHz — WNS **+6.802 ns**, WHS **+0.028 ns**, 0 failing endpoints |
| CSR / exception infrastructure | ✅ | M/S/U privilege, delegated traps, `MRET`/`SRET`, vectored trap delivery, 64-bit counters |
| Physical Memory Protection | ✅ | Four PMP entries with OFF/TOR/NA4/NAPOT matching and lock enforcement |
| FPGA SoC integration | ✅ | Arty S7-50 top level with clocking, parity-banked BRAM, UART, LEDs |
| UART bring-up | ✅ | Hello + keyboard echo verified; simultaneous RX/read collision regression passes |
| UART bootloader | ✅ | CRC-32 checked application uploads to `0x0000_4000` without FPGA re-synthesis |
| C firmware support | ✅ | `startup.S`, linker script, UART driver, aligned and cross-word byte/halfword/word accesses |
| Cache hierarchy | ✅ | Direct-mapped L1 I/D and L2 caches with refill, invalidation, write-through stores, and counters |
| Snake firmware | ✅ | Playable in PuTTY using `W/A/S/D`, `Q`, `R` |
| ISA compliance (riscv-tests) | ✅ | All applicable official tests pass: 66/66 FPGA, 77/77 research, 11/11 FPGA + FPU; zero N/A |
| Formal verification (riscv-formal) | ✅ | 52/52 checks pass on the FPGA core: every RV32IM instruction proven against the ISA model |
| F extension / RVV subset | ✅ | IEEE-754 RV32F unit and RVV 1.0 integer subset in the research core (not in the FPGA build) |

---

## ✅ Synthesis & Implementation Proof

Screenshots from Vivado 2020.2 for the hardened `rv32_soc_arty_s7` project (`xc7s50csga324-1`). They show the current synthesis, implementation, utilization, and timing results. The generated bitstream is ready for the next physical-board programming pass; the earlier board proof documents Hello/Echo and Snake running on this processor.

### Synthesis — `synth_1` complete

<div align="center">
  <img src="proof/vivado_synthesis_design_runs_2.png" alt="Vivado Design Runs: updated synth_1 and impl_1 resource usage" width="96%">
</div>

| Resource | Used | Available | Utilization |
| :--- | ---: | ---: | ---: |
| Slice LUTs | 6,475 | 32,600 | 19.9 % |
| Flip-flops | 3,869 | 65,200 | 5.9 % |
| Block RAM tiles | 32 | 75 | 42.7 % |
| DSP slices | 4 | 120 | 3.3 % |

### Implementation — all timing constraints met

<div align="center">
  <img src="proof/vivado_implementation_timing_met_2.png" alt="Updated Vivado Design Timing Summary: all user specified timing constraints are met" width="96%">
</div>

| Check | Worst slack | Total negative slack | Failing endpoints |
| :--- | ---: | ---: | ---: |
| Setup | **+6.802 ns** | 0.000 ns | 0 / 12,261 |
| Hold | **+0.028 ns** | 0.000 ns | 0 / 12,261 |
| Pulse width | +16.667 ns | 0.000 ns | 0 / 3,942 |

### Before vs after the timing fix

| | Before | After |
| :--- | :---: | :---: |
| Worst negative slack @ 25 MHz | **−61.314 ns** (51 failing endpoints) | **+6.802 ns** (0 failing) |
| Slice LUTs | 9,683 | 6,367 after implementation |
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
| `0x1000_0000` - `0x1000_000F` | UART | TX, RX, status registers |

### FPGA Top Level

The active board deployment lives in:

- [`riscv_processor_cpu/phase8/rtl/soc_top.sv`](riscv_processor_cpu/phase8/rtl/soc_top.sv)
- [`riscv_processor_cpu/phase8/rtl/cpu_top_soc.sv`](riscv_processor_cpu/phase8/rtl/cpu_top_soc.sv)
- [`riscv_processor_cpu/phase8/rtl/bram.sv`](riscv_processor_cpu/phase8/rtl/bram.sv)
- [`riscv_processor_cpu/phase8/rtl/uart.sv`](riscv_processor_cpu/phase8/rtl/uart.sv)
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

Result: the current hardened design closes timing with **+6.802 ns setup slack** and **+0.028 ns hold slack**. See [Synthesis & Implementation Proof](#-synthesis--implementation-proof).

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
├── proof/                            # Vivado synthesis + implementation screenshots
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

### Fast UART Bootloader Flow

The FPGA SoC now has a resident UART bootloader. Install it into the bitstream
once:

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

Bootloader v2 combines a 16-byte hardware RX FIFO with 32-byte acknowledged
blocks. The PC does not send the next block until the CPU confirms the previous
one was stored, and any loss of synchronization reports the exact byte offset.
The uploader uses the hardware-verified 2 ms inter-byte gap by default. The
delay can still be overridden with `UPLOAD_DELAY=<milliseconds>` when testing
another USB-UART adapter.

The uploaded image survives BTN0 reset but is volatile across power loss or
FPGA reprogramming. See the
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
| Official riscv-tests (ISA compliance) | `make compliance` | FPGA 66/66, research 77/77, FPGA + FPU 11/11; **154/154 total, zero N/A** |
| riscv-formal (formal, FPGA core) | `make formal` | 52/52 checks pass |
| Timing closure (Vivado, 25 MHz) | — | WNS +6.802 ns, WHS +0.028 ns, 0 failing endpoints |
| FPGA bitstream | Vivado 2020.2 | Synthesis, placement, routing and `write_bitstream` complete with 0 errors |
| On the board | — | Hello/echo and Snake running on the Arty S7-50 |

The verification flows found and fixed real bugs along the way, including wrong-path fetch from stale branch
predictions, stale operands behind cache misses, `minstret` timing, UART RX collisions, PMP corner cases,
cross-word memory accesses, and M/S/U privilege transitions. Details:
[compliance](riscv_processor_cpu/docs/phase5_compliance.md),
[formal](riscv_processor_cpu/docs/phase5_formal_verification.md),
[FPU / vector](riscv_processor_cpu/docs/fp_extension.md).

Useful references:

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
