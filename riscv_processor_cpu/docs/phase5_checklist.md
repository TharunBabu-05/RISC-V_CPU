# Phase 5 Checklist

Ticked items have a result in the repository; unticked items are open.

## Done
- [x] riscv-tests executed on both cores, all applicable tests pass — [phase5_compliance.md](phase5_compliance.md)
- [x] riscv-formal on the FPGA core, 52/52 checks pass — [phase5_formal_verification.md](phase5_formal_verification.md)
- [x] FPGA timing closure at 25 MHz (Vivado), hardware verified on the Arty S7-50 — [phase5_synthesis.md](phase5_synthesis.md)
- [x] Directed and unit regression with a failing exit code on any failure (`make regress`)
- [x] Four-entry PMP, hardware scalar misaligned access, and M/S/U privilege support
- [x] ISA coverage and known limitations in one place — [isa_coverage.md](isa_coverage.md)

## Open
- [ ] riscv-arch-test (RISCOF) signature-based compliance
- [ ] riscv-formal CSR and bus checks; formal coverage of interrupts
- [ ] RVFI port for the research core (FPU / vector are verified by simulation only)

## Related Docs
- [Compliance](phase5_compliance.md) · [Formal verification](phase5_formal_verification.md) ·
  [Synthesis](phase5_synthesis.md) · [ISA coverage](isa_coverage.md) · [Build guide](build_simulation_guide.md)
