# Compliance Profiles

The profiles below are the starting point for the compliance harness.

## Profiles

- rv32i: base integer tests
- rv32im: integer plus multiply/divide tests
- rv64i: 64-bit datapath smoke tests
- rv64im: 64-bit datapath plus multiply/divide tests

## Usage

- Run the local RV32 scaffold with `python run_rv32_compliance.py`.
- The runner auto-discovers sibling `riscv-tests` or `riscv-arch-test` checkouts when they exist next to the repo.
- Point the runner at a specific checkout with `--suite-root` or set `PHASE5_COMPLIANCE_SUITE_ROOT`.
- Override the command shape with `--command-template` or `PHASE5_COMPLIANCE_COMMAND_TEMPLATE` when a checkout uses a custom invocation.
- Signature outputs are mapped under `phase5/compliance/signature/<profile>` and passed through as `SIGNATURE_DIR` for external checkouts.

## Execution Notes

- Use the simulation build already wired into the repository to smoke-test the target ISA before external compliance runs.
- Capture signature-region expectations in the harness once the external test runner is connected.