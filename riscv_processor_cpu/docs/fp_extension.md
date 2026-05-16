# Floating-Point Status

The floating-point foundation required by Phase 4 vector work is now integrated into `cpu_top.sv`.

## Implemented

- `fp_regfile.sv`: 32-entry FP register file.
- `fpu_unit.sv`: behavioral 3-cycle execution unit.
- OP-FP decode in `cpu_top.sv`.
- CPU-integrated FADD/FSUB/FMUL/FDIV smoke path.
- FP CSRs in `csr_file.sv`:
  - `fflags` at `0x001`
  - `frm` at `0x002`
  - `fcsr` at `0x003`
- `make sim_fp` regression.

## Current Scope

The current FPU is behavioral and integer-compatible for Icarus simulation. It validates pipeline integration, FP register writeback, and multi-cycle stall behavior, but it is not a full IEEE-754 implementation yet.

## Next Hardening

- Replace behavioral arithmetic with IEEE-754 compliant single-precision units.
- Add FP load/store scoreboard and forwarding coverage.
- Add FP exception flag updates into `fflags/fcsr`.
- Expand tests for NaN, infinity, rounding modes, and denormals.
