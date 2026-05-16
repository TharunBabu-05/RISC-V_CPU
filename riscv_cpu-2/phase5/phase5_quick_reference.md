# Phase 5 Quick Reference

**Status**: ✅ COMPLETE  
**Date**: May 16, 2026

---

## Quick Start

### Run All Simulations
```bash
make phase5-all
```

### Run Compliance Tests
```bash
python phase5/compliance/run_rv32_compliance.py --profile rv32i
python phase5/compliance/run_rv32_compliance.py --profile rv32im
# Phase 5 Quick Reference
```bash
cd phase5/formal
sby -f pipeline_control.sby
sby -f hazard_checks.sby
sby -f csr_checks.sby
```

### Run Synthesis (choose one)
```bash
# Vivado (Xilinx FPGA)
cd phase5/synthesis
vivado -mode tcl -source vivado_synth.tcl

# Design Compiler (ASIC)
cd phase5/synthesis
dcshell -f dc_synth.tcl

# Yosys (Open-source)
cd phase5/synthesis
yosys -s yosys_synth.ys
```

---

## Directory Structure

```
phase5/
├── compliance/              # Compliance test harness
│   ├── run_rv32_compliance.py
│   ├── rv32i.profile, rv32im.profile, rv64i.profile, rv64im.profile
│   ├── command_templates.md
│   └── signature/           # Test output signatures
├── formal/                  # Formal verification
│   ├── pipeline_control.sby
│   ├── hazard_checks.sby
│   ├── csr_checks.sby
│   ├── phase5_cpu_formal_top.sv
│   ├── phase5_cpu_phase5_sva.sv
│   └── README.md
├── synthesis/               # Synthesis templates
│   ├── core_constraints.tcl
│   ├── vivado_synth.tcl
│   ├── dc_synth.tcl
│   ├── yosys_synth.ys
│   └── README.md
├── phase5_completion_report.md      # Detailed completion report
├── phase5_implementation_guide.md    # Step-by-step implementation guide
└── README.md                          # Workspace overview
```

---

## Make Targets Summary

```bash
# Simulations
make sim              # RV32I base integer
make sim_muldiv       # RV32M multiply/divide
make sim_branch_edge  # Branch predictor edge cases
make sim_rv64         # RV64I datapath
make sim_mmu          # MMU / Sv32 translation
make sim_fp           # Floating-point integration
make sim_vector       # Vector integration

# Phase 5 specific
make phase5           # List all Phase 5 artifacts
make phase5-all       # Run all simulations
make phase5-report    # Print Phase 5 completion report
make phase5-compliance-run  # Run compliance harness
make phase5-clean     # Clean temporary files

# Maintenance
make clean            # Remove compiled binaries and VCD files
make lint             # Run Verilator lint check
make wave             # Open waveform in GTKWave (requires X11/display)
```

---

## Verification Checklist

- [x] **Directed Simulations** (7/7 PASSING)
  - RV32I basic integer
  - RV32M mul/div
  - Branch predictor edge cases
  - RV64I datapath
  - MMU / Sv32 translation
  - Floating-point integration
  - Vector integration

- [x] **Compliance Framework** (READY)
  - Local tests passing
  - Harness configured for external suites
  - Profiles defined (rv32i, rv32im, rv64i, rv64im)

- [x] **Formal Verification** (READY - requires tool install)
  - Assertion module created
  - Formal top wrapper created
  - Three property job files (pipeline, hazard, CSR)

- [x] **Synthesis** (READY - requires tool)
  - Timing constraints defined
  - Three synthesis scripts (Vivado, DC, Yosys)
  - Memory macro replacement guidance provided

---

## Documentation Files

| File | Purpose |
|------|---------|
| phase5_completion_report.md | Executive summary and sign-off |
| phase5_implementation_guide.md | Detailed step-by-step instructions |
| phase5_quick_reference.md | This file - quick lookup |
| docs/phase5_checklist.md | Phase 5 work item checklist |
| docs/phase5_compliance.md | Compliance flow documentation |
| docs/phase5_formal_verification.md | Formal verification documentation |
| docs/phase5_synthesis.md | Synthesis flow documentation |
| phase5/compliance/README.md | Compliance harness details |
| phase5/compliance/command_templates.md | External test command templates |
| phase5/formal/README.md | Formal job details |
| phase5/synthesis/README.md | Synthesis script details |

---

## Common Tasks

### Task: Run all local regressions
```bash
make phase5-all
```
**Result**: All 7 tests should PASS

### Task: Test RV32I compliance
```bash
python phase5/compliance/run_rv32_compliance.py --profile rv32i
```
**Result**: Signature file written to phase5/compliance/signature/rv32i/

### Task: Verify RTL compiles
```bash
make sim
```
**Result**: Binary created at sim/cpu_sim

### Task: View synthesis timing
```bash
cd phase5/synthesis
vivado -mode tcl -source vivado_synth.tcl
cat timing_summary.txt
```
**Result**: Timing report showing slack

### Task: Find failing test
```bash
# Run specific simulation
make sim_mmu

# If it fails, examine the testbench
cat tb/tb_mmu.sv

# Check the detailed error output for clues
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `iverilog: command not found` | Install Icarus Verilog: `apt-get install iverilog` |
| Compliance harness hangs | Kill process, check `iverilog` installation |
| Formal job timeout | Increase `depth` in .sby file, or wait longer |
| Synthesis tool not found | Install Vivado, Design Compiler, or Yosys |
| Memory model warning | Expected; will be replaced with macros in production |

---

## Phase 5 Exit Criteria (MET)

- ✅ All 7 directed simulations pass
- ✅ Compliance harness operational with local targets
- ✅ Formal verification infrastructure in place
- ✅ Synthesis templates provided for three tool flows
- ✅ Documentation complete
- ✅ Make targets configured
- ✅ Implementation guide provided

---

## Next Steps

1. **For Compliance**: Download external riscv-tests or riscv-arch-test and run full test matrix
2. **For Formal**: Install SymbiYosys and execute formal jobs
3. **For Synthesis**: Choose target tool (Vivado/DC/Yosys) and run synthesis
4. **For Physical Implementation**: Replace memory models with technology-specific macros

---

## References

- [Architecture Overview](../docs/architecture_overview.md)
- [Implementation Guide](phase5_implementation_guide.md)
- [Completion Report](phase5_completion_report.md)
- [Compliance Documentation](../docs/phase5_compliance.md)
- [Formal Documentation](../docs/phase5_formal_verification.md)
- [Synthesis Documentation](../docs/phase5_synthesis.md)
