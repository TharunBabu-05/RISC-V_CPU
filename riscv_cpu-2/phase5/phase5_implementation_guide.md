# Phase 5 Implementation Guide

**Last Updated**: May 16, 2026

This guide provides step-by-step instructions for implementation teams to complete the three remaining Phase 5 work items: compliance verification, formal verification, and synthesis/timing closure.

---

## 1. Compliance Testing

### 1.1 Overview

The compliance testing workflow verifies that the CPU implementation passes official RISC-V compliance test suites.

### 1.2 Local Regression (Baseline - ✅ COMPLETE)

First, verify that all local directed simulations pass:

```bash
cd riscv_cpu-2
make sim              # RV32I basic
make sim_muldiv       # RV32M (multiply/divide)
make sim_branch_edge  # Branch predictor edge cases
make sim_rv64         # RV64I datapath
make sim_mmu          # MMU/Sv32 translation
make sim_fp           # FP integration
make sim_vector       # Vector integration
```

**Expected Result**: All tests print "PASS" or similar success message.

### 1.3 Compliance Harness Execution

Run the compliance harness against local regression targets:

```bash
cd riscv_cpu-2

# Test RV32I base integer ISA
python phase5/compliance/run_rv32_compliance.py --profile rv32i

# Test RV32IM (base + multiply/divide)
python phase5/compliance/run_rv32_compliance.py --profile rv32im

# Test RV64I (64-bit mode)
python phase5/compliance/run_rv32_compliance.py --profile rv64i

# Test RV64IM
python phase5/compliance/run_rv32_compliance.py --profile rv64im
```

**Expected Output**:
```
[phase5] RV32I base integer profile
[phase5] running: make sim ...
[phase5] Test suite complete - all tests PASSED
Signature written to: phase5/compliance/signature/rv32i/
```

### 1.4 External Compliance Suite Integration

#### Step 1: Obtain Test Suite

Option A - riscv-tests:
```bash
cd /path/to/parent/of/riscv_cpu-2
git clone https://github.com/riscv-software-consortium/riscv-tests.git
cd riscv-tests
git submodule update --init --recursive
```

Option B - riscv-arch-test:
```bash
cd /path/to/parent/of/riscv_cpu-2
git clone https://github.com/riscv/riscv-arch-test.git
cd riscv-arch-test
git submodule update --init --recursive
```

#### Step 2: Run with External Suite

```bash
cd riscv_cpu-2

# Point harness at external test suite (auto-discovered from sibling directory)
python phase5/compliance/run_rv32_compliance.py --profile rv32i

# Or explicitly specify suite path
python phase5/compliance/run_rv32_compliance.py \
    --profile rv32i \
    --suite-root ../riscv-tests

# Run full test matrix
python phase5/compliance/run_rv32_compliance.py --profile all
```

#### Step 3: Analyze Results

Check signature outputs:
```bash
ls -la phase5/compliance/signature/rv32i/
# Compare with expected signature from test suite documentation
```

If tests fail:
- Check error messages in test runner output
- Review the failing instruction in ISA specification
- Trace through simulation to identify RTL issue
- Fix RTL and re-run

### 1.5 Common Failure Modes

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| All tests fail immediately | Environment not set up | `make build-sim` first |
| Specific instruction fails | Instruction decoding error | Check control_unit.sv decode logic |
| CSR tests fail | CSR file issue | Verify csr_file.sv implementation |
| Privilege mode tests fail | Privilege tracking issue | Check interrupt_unit.sv and csr_file.sv |
| MMU tests fail | Page table walk issue | Debug mmu.sv and tlb behavior |

---

## 2. Formal Verification

### 2.1 Overview

Formal verification mathematically proves correctness of critical pipeline, hazard, and control properties.

### 2.2 Prerequisites

Install SymbiYosys (one-time setup):

**Ubuntu/Debian**:
```bash
# Install dependencies
apt-get install python3 python3-pip yosys
pip install smtbmc

# Build SymbiYosys from source
git clone https://github.com/YosysHQ/SymbiYosys.git
cd SymbiYosys
make install
```

**macOS**:
```bash
brew install yosys python3
pip install smtbmc

git clone https://github.com/YosysHQ/SymbiYosys.git
cd SymbiYosys
make install
```

**Windows** (with WSL):
```bash
# Use WSL Ubuntu instructions above
```

Verify installation:
```bash
sby --version  # Should print SymbiYosys version
```

### 2.3 Run Formal Jobs

Navigate to formal directory and execute:

```bash
cd riscv_cpu-2/phase5/formal

# Run all three formal jobs
sby -f pipeline_control.sby
sby -f hazard_checks.sby
sby -f csr_checks.sby

# Or run individually with verbose output
sby -f pipeline_control.sby -v
```

**Expected Output**:
```
SBY 21:00:00 [cpu_formal_top] Starting verification
SBY 21:00:15 [cpu_formal_top] Checking assumptions...
SBY 21:00:30 [cpu_formal_top] PASSED (BMC limit 20)
```

### 2.4 Interpret Results

**PASSED**: All properties verified up to specified bound (20 cycles by default).

**FAILED**: Counterexample exists. Review:
```bash
ls pipeline_control.sby_dir/
# Check engine0.gtkw in GTKWave to view trace
gtkwave pipeline_control.sby_dir/engine0.vcd
```

### 2.5 Modify Properties

To add new properties, edit `phase5/formal/phase5_cpu_phase5_sva.sv`:

```systemverilog
// Example: New property for instruction sequence
sequence good_seq;
    if_id_write && (if_id_instr != 32'h0000_0013) ##1
    id_ex_reg_write ##1
    ex_mem_reg_write ##1
    wb_reg_write;
endsequence

assert_never @(posedge clk) (past_valid && $fell(rst_n));
```

Re-run formal jobs after property modifications.

### 2.6 Interpreting Counterexamples

If a property fails:

1. **Examine waveform** in GTKWave
2. **Identify failure condition** (which cycle, which signals)
3. **Determine root cause**: RTL bug, property too strict, or incorrect assumption
4. **Fix RTL or property** as appropriate
5. **Re-run to verify fix**

---

## 3. Synthesis & Timing Closure

### 3.1 Overview

Synthesis converts RTL to a technology-specific netlist and verifies timing closure.

### 3.2 Available Scripts

Three synthesis templates are provided:

- **Vivado** (Xilinx FPGA): `vivado_synth.tcl`
- **Design Compiler** (ASIC): `dc_synth.tcl`
- **Yosys** (Open-source): `yosys_synth.ys`

### 3.3 Vivado Flow (FPGA)

#### Prerequisites
```bash
# Vivado must be installed from Xilinx
which vivado
```

#### Run Synthesis
```bash
cd riscv_cpu-2/phase5/synthesis

# Method 1: Non-project mode
vivado -mode tcl -source vivado_synth.tcl

# Method 2: Project mode (GUI)
vivado -mode gui &
# File -> Open Project
# Then right-click cpu_top in Sources, Run Synthesis
```

#### Review Results
```bash
# Check timing
cat timing_summary.txt
cat timing_paths.txt

# Check area
cat area_summary.txt
```

#### Timing Closure
If Worst Negative Slack (WNS) < 0:

1. **Identify failing paths** in `timing_paths.txt`
2. **Options**:
   - Increase clock period: Edit `set_input_delay` and `set_output_delay`
   - Add pipeline stage to long datapath (e.g., split EX stage)
   - Reduce fanout on critical nets
3. **Modify RTL or constraints** as needed
4. **Re-run synthesis** until WNS ≥ 0

### 3.4 Design Compiler Flow (ASIC)

#### Prerequisites
```bash
# Design Compiler must be installed from Synopsys
which dcshell
```

#### Run Synthesis
```bash
cd riscv_cpu-2/phase5/synthesis

# Set PDK library path (example)
export MW_DESIGN_LIBRARY=/path/to/pdk/lib

# Run synthesis
dcshell -f dc_synth.tcl
```

#### Review Results
```bash
cat timing_report.txt
cat area_report.txt
```

### 3.5 Yosys Flow (Open-source)

#### Prerequisites
```bash
apt-get install yosys
which yosys
```

#### Run Synthesis
```bash
cd riscv_cpu-2/phase5/synthesis
yosys -s yosys_synth.ys
```

#### Review Results
```bash
# Synthesis log automatically printed
# Output files: cpu_synth.v, cpu_synth.json, netlist.json
```

### 3.6 Post-Synthesis Simulation

Verify that synthesized netlist remains functionally correct:

```bash
cd riscv_cpu-2

# Compile post-synthesis netlist with testbench
iverilog -g2012 \
    -o sim/cpu_sim_synth \
    phase5/synthesis/cpu_synth.v \
    tb/tb_cpu.sv

# Run post-synthesis simulation
cd sim && vvp cpu_sim_synth

# Expected: Same behavior as pre-synthesis RTL simulation
```

If post-synthesis simulation fails:
- Check for timing violations (setup/hold)
- Verify memory replacement (if using macros)
- Review constraints application

### 3.7 Memory Macro Replacement

Current simulation models (`memory.sv`, `dcache.sv`) use behavioral arrays. For physical implementation:

#### FPGA (Xilinx)
```verilog
// Replace inferred arrays with BRAM IP
// In memory.sv or dcache.sv:

// OLD: logic [31:0] mem [0:2047];
// NEW: Use Xilinx BRAM instantiation

blk_mem_gen_v8_4_5 #(
    .READ_WIDTH_A(32),
    .WRITE_WIDTH_A(32),
    .ADDR_WIDTH_A(11),
    .MEMORY_SIZE(8192)  // 2K x 32 bits
) bram_inst (
    .clka(clk),
    .ena(en),
    .wea(we),
    .addra(addr),
    .dina(din),
    .douta(dout)
);
```

#### ASIC (PDK-specific)
```verilog
// Replace with foundry SRAM macros
// Example: 2K x 32b SRAM

sram_2kx32 #(
    .ADDR_WIDTH(11),
    .DATA_WIDTH(32)
) sram_inst (
    .clk(clk),
    .we(write_en),
    .addr(address),
    .din(write_data),
    .dout(read_data)
);
```

### 3.8 Timing Closure Checklist

- [ ] Synthesis completes without errors
- [ ] No unresolved black-boxes (all modules synthesized)
- [ ] Setup/hold slack ≥ 0 at target frequency
- [ ] Post-synthesis simulation matches pre-synthesis
- [ ] Memory macros replaced (for physical implementation)
- [ ] IO paths constrained appropriately
- [ ] Power estimation reviewed (if applicable)
- [ ] Netlist delivered to place & route

---

## 4. Troubleshooting

### Compliance Issues

**Q: Python compliance harness hangs**  
A: Check if Icarus Verilog is installed: `which iverilog`. Install if missing.

**Q: Tests timeout**  
A: Increase timeout in `run_rv32_compliance.py` or check for infinite loops in RTL.

**Q: Signature mismatch**  
A: Compare generated signature with expected signature from official test suite. Failing instructions indicate RTL bugs.

### Formal Issues

**Q: SymbiYosys fails to run**  
A: Verify SymbiYosys installation: `sby --version`. Check PATH includes SymbiYosys bin.

**Q: Properties timeout at bounded check limit**  
A: Increase `depth` parameter in .sby files (e.g., `depth 40`). Note: Larger bounds = longer runtime.

**Q: Counterexample hard to interpret**  
A: Open trace in GTKWave and step through cycle by cycle. Check initial conditions and assumptions.

### Synthesis Issues

**Q: Synthesis tool not found**  
A: Verify tool installation and PATH. Set tool license environment if required.

**Q: Timing does not close**  
A: Identify critical path in timing report. Options: increase period, relax IO delays, add pipeline stage.

**Q: Post-synthesis sim mismatch**  
A: Check for async reset issues, check memory write logic, verify constraint application.

---

## 5. Sign-Off Criteria

All three Phase 5 work items must meet these criteria:

### Compliance ✅
- [ ] Local regressions: 100% pass rate
- [ ] External suites (rv32i, rv32im): All tests pass or failures documented
- [ ] Signatures match expected outputs
- [ ] Root causes captured for any failures

### Formal Verification ✅
- [ ] All three property jobs (pipeline, hazard, CSR) reach PASSED
- [ ] No counterexamples in bounded region
- [ ] Properties verified to depth ≥ 20

### Synthesis ✅
- [ ] Synthesis completes without errors
- [ ] Timing closure achieved at target frequency
- [ ] Post-synthesis simulation passes
- [ ] Memory macros replaced (for physical flow)

---

## 6. Deliverables

Upon completion, archive and deliver:

```
phase5_final_deliverables.tar.gz
├── rtl/                       (Final RTL netlist)
├── netlists/                  (Synthesized netlists if applicable)
├── reports/
│   ├── timing_summary.txt
│   ├── timing_paths.txt
│   ├── area_summary.txt
│   ├── compliance_results.txt
│   └── formal_results.txt
├── signatures/                (Compliance test signatures)
├── documentation/             (Phase 5 final docs)
└── phase5_completion_report.md
```

---

## 7. Contact & Further Support

- **Architecture Questions**: See `docs/architecture_overview.md`
- **Build Issues**: Check `docs/build_simulation_guide.md`
- **ISA Coverage**: Refer to `docs/isa_coverage.md`
- **Formal Details**: See `phase5/formal/README.md`
- **Synthesis Details**: See `phase5/synthesis/README.md`
