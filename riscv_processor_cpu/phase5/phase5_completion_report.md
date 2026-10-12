# Phase 5 Status Report

Every result below can be reproduced with the listed command from `riscv_processor_cpu/`. Items without a
result are listed under "Not covered" rather than marked complete.

## Summary

| Area | Result | Reproduce |
|---|---|---|
| Directed and unit testbenches | 22 / 22 pass | `make regress` |
| riscv-tests, FPGA design (`soc_top`, RV32IM) | 64 / 64 applicable pass, 2 not applicable | `make compliance` |
| riscv-tests, research core (RV32IMF) | 75 / 75 applicable pass, 2 not applicable | `make compliance` |
| riscv-tests rv32uf, FPGA design + optional FPU | 11 / 11 pass | `make compliance` |
| riscv-formal, FPGA core | 52 / 52 checks pass | `make formal` |
| FPGA timing at 25 MHz (Vivado 2020.2, xc7s50) | Met: WNS +14.6 ns, 0 failing setup/hold endpoints | Vivado project in `phase8/vivado/` |
| Hardware | Hello/echo and Snake run on the Arty S7-50 | `phase8/README.md` |

## 1. Simulation

`tb/run_regression.py` compiles and runs 22 testbenches and fails if any reports a failure. Highlights:

- `tb_fpu_unit`: 43,013 vectors from an exact-rational IEEE-754 reference model (`tb/fpu_ref.py`), all 24 RV32F
  operations × 5 rounding modes, result bits and fflags.
- `tb_vector_unit`: 12,200 vectors from `tb/vec_ref.py` for the RVV subset.
- CPU-level programs for precise interrupts, traps and CSRs, branch prediction, cache-miss stalls, the MMU, F and V.

## 2. ISA compliance — [details](../docs/phase5_compliance.md)

The official riscv-tests suites are built from source and run on the research core and on the real FPGA design.
`rv32ui-p-ma_data` (needs hardware misaligned access) and `rv32mi-p-pmpaddr` (needs PMP) are reported as not
applicable. Running the suites found and fixed: `minstret` counting at the wrong stage, an inconsistent S-mode
(`MPP`/`SRET`), and missing zero-trigger debug CSRs.

## 3. Formal verification — [details](../docs/phase5_formal_verification.md)

riscv-formal checks the FPGA core over unconstrained instruction and data memory: every RV32IM instruction
against the ISA model, register consistency, PC continuity, causality, uniqueness and illegal-instruction traps.
It found three real bugs (wrong-path fetch from stale branch predictions; redirects hitting a busy multi-cycle
unit; stale operands for an instruction held in EX), all fixed and covered by regressions. Deliberately injected
bugs (a single-operand ADD error, the old CSR-forwarding bug) are caught within seconds.

The earlier `phase5/formal` SymbiYosys jobs restated the RTL equations and were removed.

## 4. Synthesis and timing — [details](../docs/phase5_synthesis.md)

| FPGA design (`soc_top`) | Value |
|---|---|
| Clock | 25 MHz (12 MHz board oscillator × 62.5 / 30) |
| Worst setup slack | +14.6 ns (40 ns period) |
| Slice LUTs / FFs / DSPs / BRAM tiles | 3,749 / 3,674 / 4 / 16 |

Only the Vivado flow has been run. `dc_synth.tcl` and `yosys_synth.ys` are untested templates. The research core
(with FPU and vector unit) is a simulation model and has not been synthesized.

## Not covered

- riscv-arch-test (RISCOF) signature-based compliance.
- riscv-formal CSR/bus checks and interrupts; no RVFI port on the research core.
- PMP, S-mode, hardware misaligned access, A and C extensions.
- Unbounded formal proofs (all checks are bounded to 10–30 cycles).
