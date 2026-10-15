# 🚀 RISC-V RV32IM SoC on Arty S7-50 FPGA — Complete Implementation & Deployment Guide

> **Target Board:** Digilent Arty S7-50 (`XC7S50-CSGA324-1`)  
> **Core Architecture:** 5-Stage Pipelined RV32IM with Unified 64KB BRAM, UART, CLINT & PLIC
> **System Clock:** 25 MHz (MMCM synthesis from 12 MHz on-board oscillator)  
> **Serial Baud Rate:** 115,200 baud (8N1)

---

## 📋 Table of Contents
1. [Overview & Project Milestones](#-overview--project-milestones)
2. [Hardware Architecture & Key Bug Fixes](#-hardware-architecture--key-bug-fixes)
   - [Clock Generation (MMCM 25 MHz)](#1-clock-generation-mmcm-25-mhz)
   - [UART RX Pull-Up Resistor Fix](#2-uart-rx-pull-up-resistor-fix)
   - [Byte-Level Load & Store Alignment Fix](#3-byte-level-load--store-alignment-fix)
3. [The Two Firmware Programs](#-the-two-firmware-programs)
4. [Step-by-Step: How to Switch Firmware](#-step-by-step-how-to-switch-firmware)
   - [Option A: Deploy Hello World + Key Echo Firmware](#option-a-deploy-hello-world--key-echo-firmware)
   - [Option B: Deploy Snake Game Firmware](#option-b-deploy-snake-game-firmware)
5. [CRITICAL: The Vivado Re-Synthesis Workflow](#-critical-the-vivado-re-synthesis-workflow)
6. [PuTTY Serial Terminal Configuration](#-putty-serial-terminal-configuration)
7. [Testing, LEDs & Controls](#-testing-leds--controls)
8. [Troubleshooting Cheatsheet](#-troubleshooting-cheatsheet)

---

## 🌌 Overview & Project Milestones

This project integrates our custom **RV32IM pipelined processor** into a standalone System-on-Chip (SoC) deployed on the **Xilinx Arty S7-50 FPGA**. 

### 🏆 Milestones Completed
1. **Pipelined RV32I Core:** 5 stages (IF, ID, EX, MEM, WB) with hazard detection and data forwarding.
2. **Hardware M-Extension:** Multiplier and Divider unit (`mul`, `div`, `rem`).
3. **Verification:** the FPGA core passes all applicable official riscv-tests (66/66) and 52/52 riscv-formal checks (every RV32IM instruction proven against the ISA model). See `docs/phase5_compliance.md` and `docs/phase5_formal_verification.md`.
4. **On-Chip Memory:** 64KB logical dual-port Block RAM with parity banking for single-cycle cross-word loads/stores (Port A: instruction fetch, Port B: data load/store).
5. **Memory-Mapped UART:** TX/RX peripheral at physical address `0x1000_0000` with 115200 baud support.
6. **Core-Local Interrupts:** CLINT-style 64-bit `mtime`/`mtimecmp` timer and machine software interrupt.
7. **Platform Interrupts:** Four-source, single-context PLIC with priorities, enables, threshold, and claim/complete.
8. **Hardware Debug Indicators:** Status LEDs tied to CPU run state, PLL lock, and serial communication.
9. **Two Bare-Metal Firmwares:**
   - Diagnostic `hello_asm.S`: Hardware bring-up and interactive keyboard echo.
   - Interactive `snake.c`: Full ANSI terminal Snake game with real-time controls.

---

## 🛠 Hardware Architecture & Key Bug Fixes

During physical bring-up on the Arty S7 FPGA, three critical hardware issues were discovered and solved:

### Interrupt Architecture

The Phase 8 SoC now delivers all three RISC-V machine interrupt classes to the
CPU CSR/trap unit:

| Cause | `mip`/`mie` bit | Hardware source |
| :--- | :---: | :--- |
| Machine software interrupt | 3 (`MSIP`) | CLINT `msip` register |
| Machine timer interrupt | 7 (`MTIP`) | `mtime >= mtimecmp` |
| Machine external interrupt | 11 (`MEIP`) | PLIC claimable source |

The PLIC reserves source IDs 1 through 4 for UART RX, GPIO, SPI, and an
external/platform input. UART RX is connected in the current board SoC. The
GPIO, SPI, and external source slots are implemented in the controller and are
ready to connect when those peripheral blocks are added.

#### Interrupt Register Map

| Address | Register | Description |
| :--- | :--- | :--- |
| `0x0200_0000` | CLINT `msip` | Bit 0 asserts/clears the software interrupt |
| `0x0200_4000` / `0x0200_4004` | CLINT `mtimecmp` low/high | 64-bit timer deadline |
| `0x0200_BFF8` / `0x0200_BFFC` | CLINT `mtime` low/high | 64-bit free-running cycle counter |
| `0x0C00_0004` ... `0x0C00_0010` | PLIC priority | Source priorities 1..7; zero disables |
| `0x0C00_1000` | PLIC pending | Pending source bits `[4:1]` |
| `0x0C00_2000` | PLIC enable | Machine-context enable bits `[4:1]` |
| `0x0C20_0000` | PLIC threshold | Minimum accepted priority |
| `0x0C20_0004` | PLIC claim/complete | Read source ID to claim; write it to complete |

Firmware definitions and safe RV32 helpers live in
[`software/soc.h`](software/soc.h) and
[`software/interrupts.h`](software/interrupts.h). Existing Snake and bootloader
firmware remain polling-based and unchanged; interrupt-driven firmware must set
`mtvec`, enable the desired `mie` bits, and set global `mstatus.MIE`.

Run `make -C riscv_processor_cpu/phase8/tb` from the repository root to execute
the CLINT unit test, PLIC arbitration test, CPU interrupt-cause test, and full
SoC address-map integration test.

Vivado 2020.2 synthesis, placement, routing, and bitstream generation complete
for this interrupt-enabled build. At 25 MHz, final timing is WNS `+7.673 ns`,
WHS `+0.030 ns`, with zero failing endpoints. Post-route use is 6,687 LUTs,
4,195 registers, 32 BRAM tiles, and 4 DSP slices.

### 1. Clock Generation (MMCM 25 MHz)
* **On-board oscillator:** 12 MHz oscillator on pin `F14` (`clk_12mhz` in the XDC).
* **MMCM parameters:** `CLKFBOUT_MULT_F = 62.5`, `DIVCLK_DIVIDE = 1`, `CLKOUT0_DIVIDE_F = 30.0`.
* **Actual Clock:** $12\text{ MHz} \times \frac{62.5}{30} = \mathbf{25\text{ MHz}}$.
* **Fix Applied:** Configured `CLK_FREQ = 25_000_000` in [`soc_top.sv`](rtl/soc_top.sv) so the UART clock divider matches 115,200 baud exactly:
  $$\text{Divider} = \frac{25\,000\,000}{115\,200} \approx 217\text{ cycles/bit}$$

### 2. UART RX Pull-Up Resistor Fix
* **Problem:** In serial UART, an idle line must stay at logic **HIGH (1)**. Because the FPGA RX pin (`V12`) originally lacked an internal pull-up, it floated LOW during reset or button press, causing the UART RX core to interpret the float as continuous zero bits (an infinite stream of false start bits and garbage characters).
* **Fix Applied in [`arty_s7_50.xdc`](constraints/arty_s7_50.xdc):**
  ```tcl
  set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { uart_rx }];
  ```

### 3. Byte-Level Load & Store Alignment Fix
* **Problem:** 
  - `hello_asm.S` only performed 32-bit word loads and stores (`lw`/`sw`), which worked immediately.
  - C programs (`snake.c`) perform byte reads (`lbu`/`lb`) for strings and byte writes (`sb`) for character buffers.
  - The BRAM bus only transfers 32-bit words. When the CPU executed `lbu`, without formatting logic it received the entire unshifted 32-bit word, causing strings to repeat characters and fail to detect the null terminator `\0`.
  - When the CPU executed `sb`, the single byte in `rs2[7:0]` was not aligned to the destination byte lane (`b_we`).
* **Fix Applied in [`cpu_top_soc.sv`](rtl/cpu_top_soc.sv):**
  - **Store Data Replication:** Replicated `ex_fwd_b[7:0]` across all 4 byte lanes for `SB`, and halfwords for `SH`.
  - **Load Data Extraction:** Added combinational extraction in the MEM stage based on `ex_mem_alu_result[1:0]` and `ex_mem_funct3` to properly zero-extend (`LBU`, `LHU`) and sign-extend (`LB`, `LH`).

---

## 📦 The Two Firmware Programs

| Feature | 1️⃣ Hello World + Echo (`hello_asm.S`) | 2️⃣ Snake Game (`snake.c`) |
| :--- | :--- | :--- |
| **Language** | Pure RISC-V Assembly (`RV32I`) | Bare-Metal C + `startup.S` runtime |
| **Primary Goal** | Hardware diagnostics & baud rate validation | Full interactive application showcase |
| **Terminal Output** | `Hello from RISC-V SoC!`<br>`Type anything:` | ANSI Game Board (40×20 cells), Score, Food (`*`), Snake (`@oooo`) |
| **Keyboard Input** | Echoes back each character (Enter key $\to$ `\r\n`) | Real-time WASD steering, non-blocking |
| **Target Build File** | `build/hello.vmem` | `build/snake.vmem` |
| **Installed Location** | [`phase8/rtl/firmware.vmem`](rtl/firmware.vmem) | [`phase8/rtl/firmware.vmem`](rtl/firmware.vmem) |

---

## 🔄 Step-by-Step: How to Switch Firmware

### Preferred: Resident UART Bootloader

The resident bootloader occupies the first 16 KiB of BRAM. Applications are
linked at `0x0000_4000`, leaving 48 KiB for application code, data, BSS and
stack. Uploads carry an image length and CRC-32, and are rejected if either is
invalid.

Install the bootloader into the FPGA bitstream once:

```powershell
cd riscv_processor_cpu\phase8\software
make bootloader_program
```

Reset synthesis, generate the bitstream and program the FPGA using the Vivado
procedure below. On reset, the terminal displays:

```text
RV32 UART Bootloader v2
U=upload  A=upload+run  G=run  I=info
RVBL:IDLE
```

For later Snake updates, close PuTTY because only one application can own the
serial port, then run:

```powershell
make app
make upload PORT=COM4
```

After `RVBL:OK`, reopen PuTTY and press `G`. Snake starts without another
Vivado synthesis or bitstream build. `make upload PORT=COM4 RUN=1` can start it
immediately, but its initial terminal output may be missed while the uploader
still owns the port.

Bootloader v2 uses a 16-byte hardware RX FIFO and transfers the image in
32-byte flow-controlled blocks. After each block, the CPU returns
`RVBL:NEXT <received-bytes>`; the uploader waits for that acknowledgement
before continuing. A broken transfer therefore stops at a known offset instead
of allowing later binary bytes to become commands. The default remains a
hardware-verified 2 ms inter-byte gap. It can be overridden with
`UPLOAD_DELAY=<milliseconds>` when testing another USB-UART adapter.

| Key | Bootloader action |
| :---: | :--- |
| `U` | Upload and verify an application, then remain in the loader |
| `A` | Upload, verify and immediately run an application |
| `G` | Jump to the application at `0x0000_4000` |
| `I` | Print the application address, capacity and uploaded size |

BTN0 returns to the loader while preserving the uploaded image. Power loss or
FPGA reprogramming clears the uploaded application, but the resident loader
remains in the bitstream. `tb/tb_bootloader.sv` verifies serial upload, CRC-32,
`FENCE.I`, handoff and execution of a real RV32 test application.

### Legacy Direct-BRAM Firmware Installation

The original workflow remains available for recovery and diagnostics. It
replaces the bootloader and requires FPGA synthesis. Run the appropriate
PowerShell / Makefile command in the `phase8/software` folder:

```powershell
cd riscv_processor_cpu\phase8\software
```

### Option A: Deploy Hello World + Key Echo Firmware
1. Build and install the Hello World firmware into `phase8/rtl/firmware.vmem`:
   ```powershell
   make hello_program
   ```
   *(This compiles `hello_asm.S` and copies `build/hello.vmem` $\to$ `../rtl/firmware.vmem`)*.

---

### Option B: Deploy Snake Game Firmware
1. Build and install the Snake game firmware into `phase8/rtl/firmware.vmem`:
   ```powershell
   make program
   ```
   *(This compiles `startup.S`, `uart.c`, `snake.c`, links via `link.ld`, and copies `build/snake.vmem` $\to$ `../rtl/firmware.vmem`)*.

---

## ⚠️ CRITICAL: The Vivado Re-Synthesis Workflow

> [!IMPORTANT]
> **Why you cannot just click "Generate Bitstream":**  
> In Xilinx Vivado, memory initialization files specified via `$readmemh("firmware.vmem", mem)` are baked into the synthesized BRAM netlist during **Synthesis (`synth_1`)**, **NOT** during bitstream generation!  
> Because `firmware.vmem` is an external data file, Vivado **does not automatically know** that you replaced it. If you only click "Generate Bitstream", Vivado will say *"Synthesis is up to date"* and simply reuse the previous bitstream with the OLD firmware!

### Required When Replacing `firmware.vmem`

These steps are not needed for normal `make upload` application updates. They
are required after `make hello_program`, `make program`, or
`make bootloader_program` because those commands replace `firmware.vmem`.

1. **Reset Synthesis Runs in Vivado:**
   - Look at the **Design Runs** window at the bottom of the Vivado GUI.
   - Right-click **`synth_1`** $\to$ click **Reset Runs**  
     *(Or use the top menu: **Flow** $\to$ **Reset Synthesis Runs**)*.
   
2. **Generate New Bitstream:**
   - In the left **Flow Navigator**, click **Generate Bitstream**.
   - If prompted: *"Launch runs?"*, click **OK** / **Yes**.
   - Vivado will run **Synthesis** $\to$ **Implementation** $\to$ **Write Bitstream** (~3–4 minutes).

3. **Program the Arty S7 FPGA:**
   - In the Flow Navigator, expand **Program and Debug** $\to$ click **Open Hardware Manager**.
   - Click **Open target** $\to$ **Auto Connect**.
   - Click **Program device** $\to$ choose `xc7s50_0` $\to$ confirm bitstream file:
     ```
     riscv_processor_cpu\phase8\vivado\vivado_project\rv32_soc_arty_s7.runs\impl_1\soc_top.bit
     ```
   - Click **Program**.

4. **Reset the CPU on the Board:**
   - Press **BTN0** (Reset button, rightmost button on the Arty S7 board).

---

## 🖥 PuTTY Serial Terminal Configuration

Open **PuTTY** on your computer and configure the connection:

### 1. Connection Settings
* **Connection type:** `Serial`
* **Serial line:** `COM4` *(Verify your Arty S7 port in Windows Device Manager)*
* **Speed (Baud):** `115200`
* **Data bits:** `8`, **Stop bits:** `1`, **Parity:** `None`, **Flow control:** `None`

### 2. Terminal Settings (Crucial for Snake Game)
* Go to **Terminal** category in PuTTY:
  - **Local echo:** `Force off`
  - **Local line editing:** `Force off`
* Go to **Window** category:
  - **Columns:** `80` (or higher / maximized)
  - **Rows:** `25` (or higher / maximized)
* Click **Open**.

---

## 🕹 Testing, LEDs & Controls

### Board LED Diagnostics (Arty S7-50)
| LED | Signal | Meaning When Lit |
| :---: | :---: | :--- |
| **LD0** | `rst_n` | **CPU is active and running** (turns off only while BTN0 is held). |
| **LD1** | `pll_locked` | **MMCM clock generator is locked** at 25 MHz. |
| **LD2** | `uart_tx` | **UART TX active** (blinks while CPU sends characters). |
| **LD3** | `uart_rx` | **UART RX valid** (blinks when a character is typed). |

---

### What to Expect on Terminal:

#### When Running Firmware 1 (Hello World + Echo):
```text
Hello from RISC-V SoC!
Type anything:
_
```
* Every key you type immediately appears on the terminal.
* Pressing `Enter` cleanly advances to a new line (`\r\n`).

#### When Running Firmware 2 (Snake Game):
```text
=========================================
  Welcome to RISC-V Snake!
  Running on YOUR custom RV32 CPU on FPGA
=========================================

  Controls: W/A/S/D to move, Q to quit

  Press any key to start...
```
* **Press any key** to begin.
* **Controls:**
  - `W`: Move Up
  - `S`: Move Down
  - `A`: Move Left
  - `D`: Move Right
  - `Q`: Quit
  - `R`: Retry after Game Over

---

## 🔧 Troubleshooting Cheatsheet

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| **PuTTY still shows old firmware** after compilation | Vivado reused old synthesis checkpoint. | Right-click `synth_1` in Vivado $\to$ **Reset Runs**, then click **Generate Bitstream**. |
| **PuTTY shows nothing / blank screen** | CPU in reset or baud rate mismatch. | 1. Check **LD0** and **LD1** are lit.<br>2. Press **BTN0** to reset.<br>3. Confirm baud rate is `115200` on `COM4`. |
| **PuTTY prints continuous garbage / error icons** | RX pin floating without pull-up. | Verify [`arty_s7_50.xdc`](constraints/arty_s7_50.xdc) has `PULLUP TRUE` on `uart_rx`. |
| **Typed characters do not echo** | COM port occupied or TX line error. | Close other serial monitors (Arduino IDE, TeraTerm), unplug and reconnect USB cable. |
| **Snake game field is broken / overlapping** | Terminal window too small or local echo enabled. | Maximize PuTTY window (minimum 80×25) and set **Local echo** to `Force off`. |
