# ISA Coverage and Known Limitations

## Implemented / Integrated Coverage

| Area | Status | Notes |
|---|---|---|
| RV32I base integer | Implemented | Primary directed and FPGA target |
| RV64I mode | Implemented option | Enabled via `XLEN=64`; OP-IMM-32 / OP-32 instructions are not implemented |
| M extension | Implemented | Three-cycle multiply and iterative divide/remainder |
| M/S/U privilege | Implemented | `MRET`/`SRET`, delegated traps, machine/supervisor trap CSRs, CSR aliases, and counters |
| PMP | Implemented | Four entries with OFF, TOR, NA4 and NAPOT matching, lock semantics, and instruction/load/store access faults |
| Exceptions | Implemented | Illegal instruction, instruction-address misalignment, ECALL U/S/M, EBREAK, page faults, and access faults |
| Interrupts | Implemented | Precise M/S delivery, delegation, Direct/Vectored targets, live MEIP, and software-writable supervisor pending bits |
| Misaligned data | Implemented | Scalar byte/halfword/word accesses spanning word boundaries complete in hardware; vector misalignment still traps |
| Branch predictor | Integrated | Two-bit BHT plus BTB; `FENCE.I` invalidates stale instruction-cache state |
| Sv32 MMU | Integrated | ITLB/DTLB/PTW, ASIDs, 4 MiB megapages, U/S permissions, `SUM`, `MXR`, page faults, and `SFENCE.VMA` |
| Cache hierarchy | Integrated | Direct-mapped L1 I/D and L2 caches with write-through data policy, refill, invalidation, and hit/miss counters |
| F extension | Implemented (research core) | RV32F binary32, rounding modes, flags, and `mstatus.FS`; optional in the SoC (`HAS_FPU`) |
| Vector extension | Implemented subset (research core) | VLEN=128, LMUL=1 integer subset with configuration, arithmetic, masks, reductions, and unit-stride memory |

## Verification Status

- Directed and unit regression: 26/26 testbenches pass.
- Official riscv-tests: research 77/77, SoC 66/66, optional SoC FPU 11/11; no N/A tests.
- riscv-formal: 52/52 configured RV32IM/RVFI checks pass on `cpu_top_soc`.
- UART loopback/collision test: 20/20 bytes pass, including simultaneous RX arrival and CPU read.

## Known Limitations

- No A (atomics), C (compressed), hypervisor, or external debug transport implementation.
- RV64 `*W` instructions, D extension, and a complete RVV implementation are not present.
- Global Sv32 PTEs are not specially retained across ASID-selective flushes.
- `mstatus` implements the fields used by this core but is not a complete WARL/WPRI implementation of every privileged-spec field.
- The standard RVFI proof uses an aligned-memory abstraction because its single memory transaction cannot describe one access spanning two words; hardware cross-word behavior is covered by directed and ISA compliance tests.
- `dram_ctrl` is a synthesizable zero-wait backing-memory controller model, not an external DDR PHY. External DDR requires a board-specific controller and a ready/valid cache interface.
- riscv-arch-test/RISCOF is not yet configured.
