# Build and Simulation Guide

## Dependencies

Required:

- GNU Make
- Icarus Verilog (`iverilog`, `vvp`)

Optional:

- Verilator (lint)
- GTKWave (waveform viewing)

## Directed Regressions

Run from repository root `riscv_cpu-2/`:

```bash
make sim              # RV32I + CSR + interrupt regression
make sim_branch_edge  # branch timing edge case
make sim_muldiv       # RV32M multiply/divide regression
make sim_rv64         # RV64I datapath sanity regression
make sim_mmu          # Sv32 MMU/page-fault regression
make sim_fp           # FP arithmetic integration regression
make sim_vector       # Vector arithmetic integration regression
```

## Optional Lint

```bash
make lint
```

## Waveforms

```bash
make wave
```

## Clean Artifacts

```bash
make clean
```
