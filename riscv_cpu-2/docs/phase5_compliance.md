# Phase 5 Toolchain and Compliance Handoff

## 1) riscv-tests Bring-up

- Build and run RV32I core tests first.
- Enable RV64I tests only when `XLEN=64` configuration is selected.
- Add RV32M/RV64M suites where mul/div is enabled.

## 2) riscv-arch-test Integration

- Use target shell to compile/link tests for this core memory map.
- Provide signature region support for pass/fail comparison.
- Run tests by ISA profile (RV32I -> RV32IM -> RV64 variants).

## 3) ISA/Profile Declaration

Current RTL-oriented profile:

- Base ISA: RV32I
- Optional width: RV64I (`XLEN=64`)
- Extensions integrated: M
- Experimental/integration paths present: MMU (Sv32), FP behavior path, vector behavior path
- Privilege focus: Machine mode subset (CSR/trap support)

## 4) Recommended Execution Order

1. Directed testbenches (`make sim*`).
2. `riscv-tests` smoke set.
3. `riscv-arch-test` selected profile.
4. Expand to full nightly compliance matrix.

## Exit Criteria

- All mandatory tests in selected ISA profile pass.
- Failing tests are documented with root cause and status.
- Compliance command lines and configs are checked into repo tooling.
