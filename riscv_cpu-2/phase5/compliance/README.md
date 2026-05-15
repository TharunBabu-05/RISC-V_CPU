# Compliance Profiles

The profiles below are the starting point for the compliance harness.

## Profiles

- rv32i: base integer tests
- rv32im: integer plus multiply/divide tests
- rv64i: 64-bit datapath smoke tests
- rv64im: 64-bit datapath plus multiply/divide tests

## Usage

- Run the local RV32 scaffold with `python run_rv32_compliance.py`.
- Point the runner at an external checkout with `--suite-root` or set `PHASE5_COMPLIANCE_SUITE_ROOT`.
- Override the command shape with `--command-template` or `PHASE5_COMPLIANCE_COMMAND_TEMPLATE` when a checkout uses a custom invocation.

## Execution Notes

- Use the simulation build already wired into the repository to smoke-test the target ISA before external compliance runs.
- Capture signature-region expectations in the harness once the external test runner is connected.