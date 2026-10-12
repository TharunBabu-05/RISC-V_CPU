# riscv-tests compliance runner

`run_compliance.py` builds the official riscv-tests ISA suites and runs them on the research core and on the
FPGA SoC design. Results are in [`results/`](results/). See [docs/phase5_compliance.md](../../docs/phase5_compliance.md)
for the method, the current results and the two tests marked not applicable.

```powershell
python phase5/compliance/run_compliance.py --help
```

`build/` holds generated ELF/hex files and compiled testbenches (not committed).
