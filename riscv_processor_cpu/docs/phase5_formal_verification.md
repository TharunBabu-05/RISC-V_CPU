# Formal Verification: riscv-formal

The FPGA core (`phase8/rtl/cpu_top_soc.sv`, RV32IM + Zicsr) is verified with
[riscv-formal](https://github.com/YosysHQ/riscv-formal), the YosysHQ framework that checks a processor against a
formal model of the RISC-V ISA. Setup: `formal/riscv-formal/` (wrapper, `checks.cfg`, runner).

## How it works

- The core exposes an **RVFI** trace port (`ifdef RISCV_FORMAL`, not present in the FPGA build): for every
  retired instruction it reports the instruction word, PC before/after, source register values, the destination
  register write, the memory access, the privilege mode and whether it trapped.
- The wrapper drives **instruction and data memory with unconstrained values**, so the solver explores every
  possible program and memory content.
- SymbiYosys runs bounded model checks (BMC, depth 10 to 30 cycles after reset) with the Boolector solver.
- `RISCV_FORMAL_ALTOPS` replaces MUL/DIV/REM with riscv-formal's reference "alternative" operations (the core
  implements them under the same define), so the M-extension data path, forwarding and stalls are checked without
  asking the solver to reason about a 32×32 multiplier.

| Check | What is proven (for any program and memory contents) |
|---|---|
| `insn_*` (45) | Every RV32IM instruction: correct `rd` value, next PC, memory address/mask/data and trap behaviour, given the operands the core actually used |
| `reg` | Register reads return the last value written to that register (forwarding, interlocks, writeback) |
| `pc_fwd`, `pc_bwd` | Each retired instruction starts at the PC the previous one ended at (no lost or extra instructions) |
| `causal` | Register writes retire before the reads that depend on them |
| `unique` | Retirement order numbers are never reused |
| `ill` | An all-zero (illegal) instruction traps without side effects |
| `cover` | The checks are not vacuous: two instructions retire within the bound |

```powershell
python formal/riscv-formal/run_riscv_formal.py            # all 52 checks (about 10 minutes on 8 threads)
python formal/riscv-formal/run_riscv_formal.py -k insn_add
make formal
```

Needs oss-cad-suite (yosys, sby, boolector) and git; riscv-formal is cloned at a pinned commit.

## Result

**52 / 52 checks pass** — see `formal/riscv-formal/results.txt`.

## Evidence that the checks catch real bugs

| Experiment | Result |
|---|---|
| ADD made wrong only when `rs1 = 0x00001234` | `insn_add` fails in 16 s |
| Re-introduce bug #2 (CSR read result not forwarded) | `reg` fails in 21 s |

Running riscv-formal for the first time also found three real bugs, all fixed (16 of 52 checks failed before):

1. **Stale branch-predictor entries were never corrected for non-branch instructions.** If the instruction at
   a predicted address is no longer a branch (code rewritten by a loader or self-modifying code), fetch continued
   down the predicted path. Fixed in both cores; regression: `tb/tb_btb_stale.sv`.
2. **A redirect could hit an instruction still busy in a multi-cycle unit.** The fix for (1) exposed that a
   misprediction on a MUL/DIV/FP/vector instruction flushed it mid-operation while the PC could not update. EX
   redirects now wait until the EX instruction finishes.
3. **Operands of an instruction held in EX went stale.** A value forwarded from WB in the first EX cycle was lost
   once the producer retired, so a store or ALU op held behind a cache miss used the old register value (research
   core: wrong store data). EX now refreshes its operands while held; regression: `tb/tb_mem_stall.sv`.

## What replaced the earlier formal jobs

The previous `phase5/formal` jobs asserted that signals equalled the same expressions the RTL used to compute them
(e.g. `fwd_a == <forwarding equation>`), ran only 10 cycles with NOP-filled memory, and could not detect data
bugs: CSR forwarding bug #2 passed them. They were removed in favour of riscv-formal.

## Not covered

- CSR semantics (`csrw`, `csr_ill` checks), interrupts (the wrapper ties the interrupt line low), and the
  riscv-formal bus checks are not configured.
- The research core (`rtl/cpu_top.sv`) has no RVFI port; it is covered by riscv-tests and simulation. Its FPU
  and vector unit are verified against reference models in simulation, not formally.
- Bounded proofs (BMC) only: properties hold for every behaviour within the check depth, not unboundedly.
