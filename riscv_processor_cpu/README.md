<div align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&weight=800&size=40&pause=1000&color=00FFFF&center=true&vCenter=true&width=800&height=80&lines=RISC-V+RV32I+Processor;Custom+FPGA+SoC+Deployment;Formally+Verified+Architecture" alt="Typing SVG" />
</div>

<div align="center">
  <a href="#"><img src="https://img.shields.io/badge/Architecture-RV32IM-00ffcc?style=for-the-badge&logo=riscv&logoColor=white" alt="Arch"></a>
  <a href="#"><img src="https://img.shields.io/badge/Pipeline-5%20Stage-ff007f?style=for-the-badge&logo=opslevel&logoColor=white" alt="Pipeline"></a>
  <a href="#"><img src="https://img.shields.io/badge/Verification-SymbiYosys%20Formal-7000ff?style=for-the-badge&logo=hackthebox&logoColor=white" alt="Formal"></a>
  <a href="#"><img src="https://img.shields.io/badge/Target-Arty%20S7--50-ffaa00?style=for-the-badge&logo=xilinx&logoColor=white" alt="FPGA"></a>
  <a href="#"><img src="https://img.shields.io/badge/Status-FPGA%20Ready-00ff55?style=for-the-badge&logo=checkmarx&logoColor=white" alt="Status"></a>
</div>

<br>

<div align="center">
  <img src="./architecture_animated.svg" alt="Animated SoC Architecture" width="100%">
  <br>
  <i>(Animated High-Level Pipeline & SoC Bus Architecture)</i>
</div>

<br>

## 🌌 Project Overview
Welcome to the ultimate custom **RISC-V CPU & SoC** project! This repository contains a fully working, formally verified 5-stage pipelined RV32IM processor written from scratch in SystemVerilog, explicitly tailored for FPGA deployment.

The processor comes integrated into a custom System-on-Chip (SoC) environment complete with memory-mapped BRAM, a custom UART peripheral, and bare-metal firmware running a fully playable **Snake Game** directly on the FPGA via a serial terminal!

---

## ✨ Dynamic Features

<details open>
<summary><b><span style="font-size: 1.2em">🔥 High-Performance Core Pipeline</span></b></summary>
<br>
<ul>
  <li><b>5-Stage Pipeline:</b> Classic Instruction Fetch, Decode, Execute, Memory, and Writeback stages designed for minimal structural hazards.</li>
  <li><b>Data Forwarding & Hazard Handling:</b> Fully transparent bypassed data paths for 1-cycle latency without stalling on dependent instructions.</li>
  <li><b>Hardware Math:</b> Custom <code>M</code> extension support with a dedicated Multiplier and Divider unit running concurrently with the ALU.</li>
  <li><b>Synchronous Memory Ready:</b> Precisely timed for 1-cycle latency Block RAMs without penalizing CPI.</li>
</ul>
</details>

<details open>
<summary><b><span style="font-size: 1.2em">🛡️ Formally Verified (Mathematical Proofs)</span></b></summary>
<br>
<ul>
  <li>Verified using <b>SymbiYosys (SBY)</b> with the Boolector and Yices2 solvers.</li>
  <li>Mathematical assertion properties prove that the control logic, CSR registers, and hazard mitigations are fundamentally flawless and mathematically impossible to break under normal operating bounds.</li>
</ul>
</details>

<details open>
<summary><b><span style="font-size: 1.2em">🎮 SoC & FPGA Integration</span></b></summary>
<br>
<ul>
  <li><b>Custom Peripherals:</b> Memory-mapped UART TX/RX with 2-stage metastability synchronizers.</li>
  <li><b>Synthesizable Memory:</b> Synchronous 64KB Block RAM (BRAM) inferred perfectly for Xilinx 7-Series FPGAs.</li>
  <li><b>Firmware Stack:</b> Custom GCC <code>Makefile</code>, bare-metal C runtime (<code>startup.S</code>), linker scripts, and polling-based hardware drivers.</li>
  <li><b>Fully Playable Demo:</b> A pure C ANSI-escape sequence snake game that runs over serial terminal at 115200 baud!</li>
</ul>
</details>

---

## 🛠️ Tools & Technologies

<div align="center">
  <table>
    <tr>
      <td align="center"><b>Hardware Description</b></td>
      <td align="center"><b>Verification & Simulation</b></td>
      <td align="center"><b>Synthesis & Deployment</b></td>
      <td align="center"><b>Firmware Development</b></td>
    </tr>
    <tr>
      <td align="center"><img src="https://img.shields.io/badge/SystemVerilog-0A0A1A?style=for-the-badge&logo=c&logoColor=00FFFF" alt="SystemVerilog"/></td>
      <td align="center">
        <img src="https://img.shields.io/badge/OSS%20CAD%20Suite-7000FF?style=flat-square&logo=linux&logoColor=white" alt="OSS CAD Suite"/><br>
        <img src="https://img.shields.io/badge/SymbiYosys-FF007F?style=flat-square" alt="SBY"/><br>
        <img src="https://img.shields.io/badge/Icarus_Verilog-00AAFF?style=flat-square" alt="Iverilog"/>
      </td>
      <td align="center">
        <img src="https://img.shields.io/badge/Xilinx_Vivado-2020.2-FFAA00?style=for-the-badge&logo=xilinx&logoColor=white" alt="Vivado"/><br>
        <img src="https://img.shields.io/badge/Arty_S7--50-E34F26?style=flat-square" alt="Arty S7"/>
      </td>
      <td align="center">
        <img src="https://img.shields.io/badge/C-Bare_Metal-0055FF?style=flat-square&logo=c&logoColor=white" alt="C"/><br>
        <img src="https://img.shields.io/badge/GCC-riscv--none--elf-00FFAA?style=flat-square&logo=gnu&logoColor=111111" alt="GCC"/>
      </td>
    </tr>
  </table>
</div>

---

## 🚀 How to Run (Arty S7-50 Deployment)

Follow these steps to deploy the SoC to your FPGA and play the game:

### 1️⃣ Compile the Firmware
You need the RISC-V GCC toolchain (`riscv-none-elf-gcc`).
```bash
cd phase8/software
make CROSS=riscv-none-elf program
```
<i>This compiles `snake.c`, links it via `link.ld`, and generates `firmware.vmem` which is automatically injected into the BRAM during synthesis.</i>

### 2️⃣ Synthesize the Bitstream
Open **Vivado 2020.2** and generate the project using the automated script:
1. Go to `Tools` -> `Run Tcl Script...`
2. Select `phase8/vivado/create_project.tcl`
3. Wait for Synthesis and Implementation to complete (~5-10 mins).

### 3️⃣ Program & Play!
1. Open **Hardware Manager** in Vivado and program the device with `soc_top.bit`.
2. Open **PuTTY** or **Tera Term** on the board's COM port (Baud: `115200`, Data: `8`, Parity: `None`, Stop: `1`).
3. **Press any key** to start RISC-V Snake! (Use `W, A, S, D` to move).

---

<div align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&weight=600&size=20&pause=2000&color=FF00CC&center=true&vCenter=true&width=600&height=40&lines=Crafted+with+SystemVerilog;Running+at+100MHz+on+Silicon;The+Future+is+RISC-V" alt="Typing SVG" />
  <br>
  <p><b>Designed and built with passion.</b></p>
</div>
