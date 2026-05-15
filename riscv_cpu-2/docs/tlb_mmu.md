# TLB/MMU Status (Phase 4)

Phase 4 is complete. Sv32 translation is wired into the top-level CPU and has a directed regression.

## Implemented

- `satp` CSR at address `0x180`.
- Sv32 mode enable through `satp[31]`.
- ASID support through `satp[30:22]` and ASID-tagged ITLB/DTLB entries.
- Architectural privilege state tracking for M/S/U.
- S-mode CSR subset: `sstatus`, `sie`, `stvec`, `sscratch`, `sepc`, `scause`, `sip`.
- U-mode CSR subset: `ustatus`.
- Trap delegation CSRs: `medeleg`, `mideleg`.
- Instruction and data translation through `mmu.sv`.
- Separate ITLB and DTLB arrays.
- Page table walker using the memory hierarchy PTW read port.
- Pipeline stalls while translation is not ready.
- Page fault causes connected into trap handling:
  - instruction page fault: cause `12`
  - load page fault: cause `13`
  - store page fault: cause `15`
- `sfence.vma` flush for ITLB/DTLB.
- Precise MEM-stage faulting PC capture for data page faults.
- `make sim_mmu` target.

## Current Scope

The MMU is a simulation-stage integration suitable for functional development. It now tracks privilege state, implements ASID-aware TLB matching, and includes the Phase 4 privilege/CSR surface needed by the CPU.

## Validation

Covered by `tb/tb_mmu.sv`:

- Mapped load succeeds.
- A=0 load fault.
- D=0 store fault.
- R=0 load fault.
- X=0 instruction fault.

## Next Phase 4 Work

None. Phase 4 is complete; remaining work belongs to Phase 5 compliance, formal verification, or synthesis prep.
