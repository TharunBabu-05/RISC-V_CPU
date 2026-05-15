# Formal Verification Jobs

These SymbiYosys job files seed the Phase 5 formal flow.

## Property Targets

- pipeline control: flush and stall behavior
- hazard handling: load-use stall and forwarding exclusivity
- CSR behavior: trap entry and return sequencing

## Next Step

- Add a formal top wrapper that binds the existing CPU RTL to the assertions targeted by these jobs.