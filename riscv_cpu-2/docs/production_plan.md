# Production Plan (Phase 5)

## Synthesis
- Add timing constraints and clock/reset IO.
- Replace memories with FPGA BRAM or ASIC SRAM macros.
- Run timing closure at target frequency.

## Formal Verify
- Add SVA assertions for pipeline control, hazards, and CSR behavior.
- Use a bounded model checker (SymbiYosys) for key properties.

## Toolchain/Compliance
- Run riscv-tests and riscv-arch-test suites.
- Add ISA config file for compliance harness.

## Documentation
- Architecture overview and pipeline diagrams.
- ISA coverage table and known limitations.
- Build and simulation instructions.
