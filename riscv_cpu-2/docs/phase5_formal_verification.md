# Phase 5 Formal Verification Handoff

## Property Scope

Define SVA assertions around:

- **Pipeline control**
  - Flush clears younger wrong-path instructions.
  - Stall freezes IF/ID state updates.
- **Hazards/forwarding**
  - Load-use hazard introduces exactly required stall behavior.
  - Forwarding selection is mutually exclusive where required.
- **CSR behavior**
  - CSR writes commit only on valid CSR operations.
  - Trap entry updates `mepc/mcause`; `mret` restores control flow.

## Suggested SymbiYosys Flow

1. Create a formal top wrapper that constrains reset/clock and legal instruction assumptions.
2. Add bounded checks for control/hazard/CSR properties.
3. Run BMC first, then induction where applicable.

Example command set:

```bash
# install (one-time)
# pip install symbiyosys

# run formal jobs
sby -f formal/pipeline_control.sby
sby -f formal/hazard_checks.sby
sby -f formal/csr_checks.sby
```

## Exit Criteria

- All selected properties pass at the chosen bound.
- Counterexamples (if any) are triaged and closed with RTL or property fixes.
- Property suite is versioned and runnable in CI/dev environments.
