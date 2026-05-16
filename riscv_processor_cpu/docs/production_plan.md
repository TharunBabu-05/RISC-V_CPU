# Production Plan (Phase 5)

See [phase 5 checklist](phase5_checklist.md) for the current handoff status.

## Synthesis
- [x] Add timing constraints and clock/reset IO.
- [x] Replace memories with FPGA BRAM or ASIC SRAM macros.
- [x] Run timing closure at target frequency.

## Formal Verify
- [x] Add SVA assertions for pipeline control, hazards, and CSR behavior.
- [x] Use a bounded model checker (SymbiYosys) for key properties.

## Toolchain/Compliance
- [x] Document the riscv-tests and riscv-arch-test execution flow.
- [x] Add ISA profile/config guidance for the compliance harness.

## Documentation
- [x] Architecture overview and pipeline diagrams.
- [x] ISA coverage table and known limitations.
- [x] Build and simulation instructions.
