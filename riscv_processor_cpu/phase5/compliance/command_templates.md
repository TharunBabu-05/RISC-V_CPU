# Phase 5 Compliance Command Templates

Use these templates when pointing the RV32 compliance runner at an external checkout.

## riscv-tests-style Makefile checkout

```text
make -C {suite_root} ISA={isa} XLEN={xlen} EXTENSIONS={extensions} SIGNATURE_DIR={signature_dir}
```

## riscv-arch-test-style shell checkout

```text
{suite_root}/run.sh {profile} {signature_dir}
```

## Notes

- The runner auto-discovers sibling checkouts before falling back to the local regression targets.
- Set `PHASE5_COMPLIANCE_COMMAND_TEMPLATE` only if the checkout requires a custom invocation shape.