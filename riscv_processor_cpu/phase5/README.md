# Phase 5: verification and implementation readiness

| Area | Where | Status |
|---|---|---|
| ISA compliance | [`compliance/`](compliance/) — riscv-tests runner and results | All applicable tests pass on both cores ([details](../docs/phase5_compliance.md)) |
| Formal verification | [`../formal/riscv-formal/`](../formal/riscv-formal/) | 52/52 riscv-formal checks pass on the FPGA core ([details](../docs/phase5_formal_verification.md)) |
| Synthesis | [`synthesis/`](synthesis/) — Vivado / Yosys / DC templates | FPGA build meets timing at 25 MHz; the templates other than Vivado are untested |
| Status report | [`phase5_completion_report.md`](phase5_completion_report.md) | What is proven, how, and what is not covered |

Run everything from `riscv_processor_cpu/`:

```powershell
make regress      # all directed and unit testbenches
make compliance   # riscv-tests on the research core and the FPGA design
make formal       # riscv-formal on the FPGA core
```
