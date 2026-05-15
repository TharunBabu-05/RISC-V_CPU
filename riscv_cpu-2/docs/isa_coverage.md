# ISA Coverage and Known Limitations

## Implemented / Integrated Coverage

| Area | Status | Notes |
|---|---|---|
| RV32I base integer | Implemented | Primary directed test target |
| RV64I mode | Implemented option | Enabled via `XLEN=64` path |
| M extension (mul/div) | Implemented | 3-cycle single-issue mul/div unit |
| Machine + S/U-mode CSRs/traps | Implemented subset | `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`, `satp`, `sstatus`, `sie`, `stvec`, `sepc`, `scause`, `sip`, `medeleg`, `mideleg`, `ustatus`, counters; M/S/U tracking |
| Branch predictor | Integrated | 2-bit predictor + BTB behavior |
| Sv32 MMU path | Integrated | ITLB/DTLB/PTW + page-fault causes; `sfence.vma` flush; ASID-aware TLB tags |
| Floating-point path | Integrated (behavioral) | FADD/FSUB/FMUL/FDIV integration path |
| Vector path | Integrated (behavioral) | 4-lane integer vector ALU path |

## Known Limitations

- Compliance suites (`riscv-tests`, `riscv-arch-test`) are planned for full Phase 5 execution flow.
- FP/vector support is currently integration-focused and should be treated as behavioral coverage, not full ISA-complete signoff.
- MMU integration is Phase 4-complete Sv32 functionality; Phase 5 coverage is still planned.
- Cache/memory hierarchy is simulation-oriented and requires implementation-specific macro replacement for physical synthesis.
