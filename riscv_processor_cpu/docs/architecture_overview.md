# Architecture Overview

## Pipeline

```text
IF -> ID -> EX -> MEM -> WB
```

- **IF**: Fetch path with instruction-cache facade and branch predictor assist.
- **ID**: Decode, register fetch, immediate generation, hazard observation.
- **EX**: ALU/branch resolution, mul/div issue, control decisions.
- **MEM**: Data-cache path and MMU-mediated translation checks.
- **WB**: Integer/CSR writeback and retirement accounting.

## Top-Level Integration

```text
I-cache facade
    |
branch predictor -> cpu_top pipeline -> MMU -> D-cache -> L2 -> DRAM model
```

## Major Blocks

- `cpu_top.sv`: pipeline and global integration.
- `control_unit.sv` + `hazard.sv`: decode/control/hazard policy.
- `csr_file.sv` + `interrupt_unit.sv`: trap/CSR control plane.
- `mmu.sv`: Sv32 translation and page-fault signaling.
- `dcache.sv`, `l2_cache.sv`, `dram_ctrl.sv`, `memory.sv`: memory hierarchy model.
- `fp_*` and `vector_*` units: integrated behavioral FP/vector paths.
