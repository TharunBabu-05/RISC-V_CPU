# Formal verification

The earlier SymbiYosys jobs in this folder were retired: their assertions restated the RTL's own equations and
could not detect data bugs. Formal verification now uses riscv-formal on the FPGA core:

- setup and runner: [`formal/riscv-formal/`](../../formal/riscv-formal/)
- method and results: [`docs/phase5_formal_verification.md`](../../docs/phase5_formal_verification.md)
