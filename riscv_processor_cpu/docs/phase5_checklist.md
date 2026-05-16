# Phase 5 Checklist

## Handoff Status

- [x] Compliance flow is documented for `riscv-tests` and `riscv-arch-test`.
- [x] Formal verification scope is documented for pipeline, hazard, and CSR properties.
- [x] Synthesis handoff guidance is documented for clocking, resets, and memory replacement.
- [x] ISA coverage and known limitations are captured in one place.
- [x] Directed simulation regressions and build instructions remain aligned with the phase plan.
- [x] A `make phase5` entry point lists the phase-5 handoff artifacts.

## Execution Notes

- External compliance, formal, and synthesis runs still depend on local tool installation and target-specific constraints.
- The repository now contains the artifacts needed to start those runs without further structural setup.

## Related Docs

- [Compliance handoff](phase5_compliance.md)
- [Formal verification handoff](phase5_formal_verification.md)
- [Synthesis handoff](phase5_synthesis.md)
- [ISA coverage](isa_coverage.md)
- [Build guide](build_simulation_guide.md)