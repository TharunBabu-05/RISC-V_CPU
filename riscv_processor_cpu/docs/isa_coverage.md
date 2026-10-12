# ISA Coverage and Known Limitations

## Implemented / Integrated Coverage

| Area | Status | Notes |
|---|---|---|
| RV32I base integer | Implemented | Primary directed test target |
| RV64I mode | Implemented option | Enabled via `XLEN=64` path; the `*W` instructions (OP-IMM-32 / OP-32) are not implemented and raise illegal-instruction |
| M extension (mul/div) | Implemented | Multi-cycle unit: MUL* in 3 cycles, DIV/REM* via iterative radix-2 divider (XLEN+2 cycles) |
| Machine + S/U-mode CSRs/traps | Implemented subset | `misa` (RV32IM / RV64IM), `mvendorid`/`marchid`/`mimpid`/`mhartid` (0), `mstatus`, `mie`, `mtvec` (Direct/Vectored), `mcounteren`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip` (live MEIP), `medeleg`, `mideleg`, `sstatus` (view of `mstatus`), `sie`, `stvec`, `sscratch`, `sepc`, `scause`, `stval`, `sip`, `satp`, 64-bit `mcycle`/`minstret` with `cycle`/`instret` (+`*h` on RV32), Sdtrig CSRs with zero triggers. Privilege modes: **M and U** (S-mode is not implemented: `MPP` holds only M/U and `SRET` is illegal; the supervisor CSRs stay accessible from M-mode for the experimental MMU) |
| Exceptions | Implemented | Illegal instruction (incl. unknown/privileged/read-only CSR access) with `mtval` = instruction, misaligned fetch/load/store with `mtval` = address, ECALL from U/S/M (8/9/11), EBREAK, page faults |
| Interrupts | Implemented | Machine external interrupt; precise (the EX instruction completes, `mepc` = next PC); never taken on a bubble, during a multi-cycle op, CSR write, xRET or fence |
| Branch predictor | Integrated | 2-bit BHT + BTB; a correctly predicted branch/jump costs no flush |
| Sv32 MMU path | Integrated | ITLB/DTLB/PTW + page-fault causes; 4 MiB megapages (misaligned ones fault); `sfence.vma` flushes the TLBs and refetches; ASID-aware TLB tags |
| F extension (RV32F) | Implemented (research core) | Full RV32F, IEEE-754 binary32, all rounding modes, fflags, `mstatus.FS`; optional on the SoC core (`HAS_FPU`, off by default). See `fp_extension.md` |
| Vector (RVV 1.0 subset) | Implemented (research core) | Real RVV encodings: vset{i}vl{i}, unit-stride e8/e16/e32 loads/stores, integer arithmetic, compares, masking, vredsum, vmv. VLEN=128, LMUL=1. Not in the SoC core. See `fp_extension.md` |

## Known Limitations

- riscv-tests (rv32ui/um/mi/uf) pass on both cores except two tests that need unimplemented optional features (hardware misaligned access, PMP); see `phase5_compliance.md`. riscv-arch-test is not set up.
- No PMP, no S-mode, no A (atomics) or C (compressed) extensions.
- Vector support is an RVV 1.0 subset (no LMUL != 1, strided/indexed/segment accesses, widening, fixed-point or vector FP); `misa.V` is not set. No D extension.
- MMU integration is Phase 4-complete Sv32 functionality; Phase 5 coverage is still planned. Known gaps: M-mode accesses are still translated when `satp.MODE` is set (kept for the existing tests), the PTE U bit / `SUM` / `MXR` are not checked, global (G) pages are not special-cased, and page faults raised in IF/MEM are not yet fully precise.
- Misaligned loads/stores are not split in hardware; they raise address-misaligned exceptions for software to handle.
- `sie`/`sip` are separate registers rather than views of `mie`/`mip`, and supervisor interrupt delegation is not implemented.
- `mstatus` is fully writable (WPRI fields are not hard-wired to zero).
- Cache/memory hierarchy is simulation-oriented and requires implementation-specific macro replacement for physical synthesis.
