# ISA Compliance: riscv-tests

The official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) ISA suites are built from source
and run in simulation on both cores by `phase5/compliance/run_compliance.py`.

## How it works

1. Each test in the selected suites (`isa/<suite>/Makefrag`) is compiled from riscv-tests source with
   `riscv-none-elf-gcc`, using the standard `p` environment (physical memory, single hart). The `rv32ui` and
   `rv32uf` tests run in **user mode**; `rv32mi` tests run in machine mode.
2. The image is linked for the target: `0x80000000` for the research core, `0x0` for the FPGA SoC BRAM.
3. Icarus Verilog runs the image on the core. The test reports through its `tohost` word:
   `1` = pass, `(n << 1) | 1` = test case *n* failed. No result within 200,000 cycles is a timeout.
4. Results are written to `phase5/compliance/results/<core>.txt`.

| Configuration | Testbench | Design under test | Suites |
|---|---|---|---|
| `research` | `tb/tb_riscv_tests.sv` | `rtl/cpu_top.sv` (RV32IMF) | rv32ui, rv32um, rv32mi, rv32uf |
| `soc` | `tb/tb_riscv_tests_soc.sv` | `phase8/rtl/soc_top.sv`, the FPGA design (RV32IM) | rv32ui, rv32um, rv32mi |
| `soc-fpu` | `tb/tb_riscv_tests_soc.sv` | `soc_top` with the optional FPU (`HAS_FPU = 1`) | rv32uf |

```powershell
python phase5/compliance/run_compliance.py                       # everything
python phase5/compliance/run_compliance.py --core soc --suite rv32ui
python phase5/compliance/run_compliance.py --test rv32mi-csr -v  # one test
make compliance                                                  # same as the first line
```

Needs `riscv-none-elf-gcc` on `PATH` (or `CROSS=<prefix>`), Icarus Verilog, and the `riscv-tests` checkout
(with its `env` submodule) next to `riscv_processor_cpu/`.

## Results

| Configuration | Passed | Not applicable | Failed |
|---|---|---|---|
| research | **75 / 75** | 2 | 0 |
| soc (FPGA design) | **64 / 64** | 2 | 0 |
| soc-fpu | **11 / 11** | 0 | 0 |

Full logs: [research](../phase5/compliance/results/research.txt), [soc](../phase5/compliance/results/soc.txt),
[soc-fpu](../phase5/compliance/results/soc-fpu.txt).

**Not applicable** (still built, run and reported, but they need optional features this CPU does not have):

| Test | Why |
|---|---|
| `rv32ui-p-ma_data` | Requires misaligned loads/stores to complete in hardware. This core raises address-misaligned exceptions instead, which the ISA permits; `rv32mi-p-ma_addr` and the four `rv32mi-p-*-misaligned` tests, which check that behaviour, pass. |
| `rv32mi-p-pmpaddr` | Requires Physical Memory Protection (PMP), which is not implemented. |

## Bugs found by running the suites

Running riscv-tests for the first time exposed real problems, all fixed:

- `minstret` counted instructions at WB while CSRs are read and written in EX, so counter reads/writes were off
  by the instructions still in the pipeline (`rv32mi-p-instret_overflow`). It now counts as instructions leave EX,
  and an instruction that writes a counter suppresses its own increment.
- `mstatus.MPP` accepted the S-mode encoding and `SRET` executed although S-mode does not exist, so software was
  told S-mode was present (`rv32mi-p-illegal` hung waiting for a supervisor interrupt). `MPP` now holds only M/U
  and `SRET` is illegal.
- The debug-trigger CSRs (`tselect`, `tdata1-3`) trapped; they are now implemented with zero triggers, as the debug
  specification allows (`rv32mi-p-breakpoint`).

## Not covered

- [riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test) (signature-based compliance with a reference
  model, e.g. via RISCOF) is not set up.
- The vector subset has no riscv-tests suite; it is covered by `tb/tb_vector_unit.sv` and `tb/tb_vector.sv`.
