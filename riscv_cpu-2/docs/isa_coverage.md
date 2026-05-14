# ISA Coverage and Known Limitations

## Implemented / Integrated Coverage

| Area | Status | Notes |
|---|---|---|
| RV32I base integer | Implemented | Primary directed test target |
| RV64I mode | Implemented option | Enabled via `XLEN=64` path |
| M extension (mul/div) | Implemented | 3-cycle single-issue mul/div unit |
| Machine CSRs/traps | Implemented subset | `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`, `satp`, counters |
| Branch predictor | Integrated | 2-bit predictor + BTB behavior |
| Sv32 MMU path | Integrated (initial) | ITLB/DTLB/PTW + page-fault causes |
| Floating-point path | Integrated (behavioral) | FADD/FSUB/FMUL/FDIV integration path |
| Vector path | Integrated (behavioral) | 4-lane integer vector ALU path |

## Known Limitations

- Compliance suites (`riscv-tests`, `riscv-arch-test`) are planned for full Phase 5 execution flow.
- FP/vector support is currently integration-focused and should be treated as behavioral coverage, not full ISA-complete signoff.
- MMU integration is initial Sv32 functionality; full privileged-architecture completeness is not yet declared.
- Cache/memory hierarchy is simulation-oriented and requires implementation-specific macro replacement for physical synthesis.
