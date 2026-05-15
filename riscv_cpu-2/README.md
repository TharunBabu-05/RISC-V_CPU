# RISC-V Pipelined CPU

SystemVerilog implementation of a 5-stage RISC-V CPU.

## Current Status

The project is now past the original baseline pipeline and has Phase 3 integrated into the top-level CPU. Phase 4 started with Sv32 MMU wiring and page-fault tests, and Phase 5 handoff artifacts are now documented in `docs/`.

## Architecture

```text
IF -> ID -> EX -> MEM -> WB
```

Top-level integration:

```text
I-cache facade
    |
branch predictor -> cpu_top pipeline -> MMU -> D-cache -> L2 -> DRAM model
```

## Implemented Features

- RV32I 5-stage integer pipeline
- RV64I datapath option with `XLEN=64`
- RV32M/RV64M multiply/divide unit with 3-cycle single-issue latency
- Data forwarding and load-use hazard stalls
- Branch/jump flush and branch-edge regression coverage
- 2-bit branch predictor with BTB, trained from EX stage
- L1 instruction-cache facade
- L1 data-cache wrapper with blocking load misses and write-through stores
- Unified L2/DRAM model behind the D-cache
- Machine CSR subset including `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`, `satp`
- Performance counters: `mcycle` and `minstret`
- Machine external interrupt, ECALL/EBREAK, MRET
- Initial Sv32 MMU integration with ITLB/DTLB, PTW, and page-fault causes
- Floating-point register file plus CPU-integrated behavioral FADD/FSUB/FMUL/FDIV path
- Vector register file plus CPU-integrated 4-lane integer VADD/VSUB/VAND/VOR path
- FP/vector CSR addresses for `fflags`, `frm`, `fcsr`, `vstart`, `vxsat`, `vxrm`, `vl`, `vtype`

## Project Structure

```text
riscv_cpu-2/
  rtl/
    alu.sv
    branch_predictor.sv
    control_unit.sv
    cpu_top.sv
    csr_file.sv
    dcache.sv
    dram_ctrl.sv
    hazard.sv
    icache.sv
    imm_gen.sv
    interrupt_unit.sv
    l2_cache.sv
    memory.sv
    mmu.sv
    muldiv.sv
    regfile.sv
  tb/
    tb_branch_edge.sv
    tb_cpu.sv
    tb_cpu64.sv
    tb_mmu.sv
    tb_muldiv.sv
  docs/
  sim/
  Makefile
```

## Dependencies

Required:

- Icarus Verilog (`iverilog`, `vvp`)
- GNU Make

Optional:

- GTKWave
- Verilator

## Quick Start

```bash
make sim              # RV32I + CSR + interrupt regression
make sim_branch_edge  # branch timing edge case
make sim_muldiv       # RV32M multiply/divide regression
make sim_rv64         # RV64I datapath sanity regression
make sim_mmu          # Sv32 MMU/page-fault regression
make sim_fp           # FP arithmetic integration regression
make sim_vector       # Vector arithmetic integration regression
make lint             # optional Verilator lint
```

Icarus Verilog may print "constant selects in always_* processes" warnings for some SystemVerilog constructs. The current directed simulations complete successfully despite those warnings.

## Phase 5 Handoff

- `docs/production_plan.md`
- `docs/phase5_synthesis.md`
- `docs/phase5_formal_verification.md`
- `docs/phase5_compliance.md`
- `docs/architecture_overview.md`
- `docs/isa_coverage.md`
- `docs/build_simulation_guide.md`

