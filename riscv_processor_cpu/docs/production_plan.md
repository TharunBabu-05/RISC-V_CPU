# Production Plan (Phase 5) — status with evidence

Each item is ticked only when there is a result in the repository to back it.

## Synthesis / FPGA
- [x] Timing constraints and clock/reset IO for the Arty S7-50 (`phase8/constraints/arty_s7_50.xdc`).
- [x] Memories mapped to FPGA block RAM (`phase8/rtl/bram.sv`, 32 x RAMB36 for parity-banked unaligned access).
- [x] Timing closure at the target frequency: 25 MHz, WNS +6.802 ns, WHS +0.028 ns, 0 failing endpoints
      (Vivado 2020.2; reproducible with `phase8/vivado/verify_implementation.tcl`, with screenshots in `proof/`).
- [ ] Higher clock frequency (the design has roughly 60 % timing headroom at 25 MHz).
- [ ] ASIC flow (`phase5/synthesis/dc_synth.tcl` is an untested template).

## Formal verification
- [x] riscv-formal on the FPGA core: every RV32IM instruction checked against a formal ISA model, plus
      register, PC, causality, uniqueness and illegal-instruction checks (`formal/riscv-formal/`,
      results in `formal/riscv-formal/results.txt`). See [phase5_formal_verification.md](phase5_formal_verification.md).
- [ ] CSR checks (`csrw`, `csr_ill`) and bus checks in riscv-formal.
- [ ] Formal checks for the FPU / vector unit (they are verified by simulation against reference models).

## Compliance
- [x] riscv-tests rv32ui / rv32um / rv32mi / rv32uf executed on the research core: 77/77 applicable pass.
- [x] riscv-tests rv32ui / rv32um / rv32mi executed on the FPGA design: 66/66 applicable pass; rv32uf with the
      optional FPU: 11/11. See [phase5_compliance.md](phase5_compliance.md).
- [ ] riscv-arch-test (RISCOF) signature-based compliance.

## Documentation
- [x] Architecture overview, ISA coverage and known limitations, build/simulation guide.
