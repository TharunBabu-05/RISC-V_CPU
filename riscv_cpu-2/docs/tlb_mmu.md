# TLB/MMU Status (Phase 4)

Phase 4 has started. Sv32 translation is now wired into the top-level CPU and has a directed regression.

## Implemented

- `satp` CSR at address `0x180`.
- Sv32 mode enable through `satp[31]`.
- Instruction and data translation through `mmu.sv`.
- Separate ITLB and DTLB arrays.
- Page table walker using the memory hierarchy PTW read port.
- Pipeline stalls while translation is not ready.
- Page fault causes connected into trap handling:
  - instruction page fault: cause `12`
  - load page fault: cause `13`
  - store page fault: cause `15`
- `make sim_mmu` target.

## Current Scope

The MMU is a simulation-stage integration suitable for functional development. It does not yet implement full privilege-mode tracking or a production-grade trap handler environment.

## Validation

Covered by `tb/tb_mmu.sv`:

- Mapped load succeeds.
- A=0 load fault.
- D=0 store fault.
- R=0 load fault.
- X=0 instruction fault.

## Next Phase 4 Work

- Add explicit privilege mode state (M/S/U).
- Add `sfence.vma`.
- Add ASID handling or document ASID as unsupported.
- Add more precise faulting-PC capture for MEM-stage faults.
- Begin vector extension only after the floating-point path is fully integrated.
