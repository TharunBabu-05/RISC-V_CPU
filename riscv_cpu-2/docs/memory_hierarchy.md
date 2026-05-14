# Memory Hierarchy Status (Phase 3)

Phase 3 is integrated into `cpu_top.sv`.

## Integrated Topology

```text
IF -> icache facade
MEM -> MMU -> dcache -> l2_cache -> dram_ctrl -> data_mem
```

## Implemented

- `icache.sv`: instruction-cache facade with the same patchable instruction RAM interface used by the existing testbenches.
- `dcache.sv`: small direct-mapped data-cache wrapper.
- `l2_cache.sv`: unified backing-cache facade.
- `dram_ctrl.sv`: DRAM-controller facade over the simulation data memory.
- Pipeline stall wiring for blocking load misses and MMU translation misses.
- Store policy: write-through, no-write-stall stores. This keeps the simple in-order pipeline coherent with the backing memory model.
- Performance counters in `csr_file.sv`: `mcycle` at CSR `0xB00`, `minstret` at CSR `0xB02`.

## Branch Prediction

- `branch_predictor.sv` is instantiated in `cpu_top.sv`.
- The predictor uses a 2-bit BHT and BTB.
- It is trained from branch/jump resolution in EX.
- Misprediction metadata is carried through IF/ID and ID/EX so the PC can recover to the fallthrough or target path.

## Validation

Covered by:

- `make sim`
- `make sim_branch_edge`
- `make sim_muldiv`
- `make sim_rv64`

## Remaining Phase 3 Hardening

- Add cache hit/miss counters.
- Add tests for byte/halfword store hits and misses through the D-cache.
- Replace the L2 and DRAM facades with cycle-accurate handshake models when moving toward synthesis.
