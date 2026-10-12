# riscv-formal for the FPGA core

| File | Purpose |
|---|---|
| `wrapper.sv` | `cpu_top_soc` with unconstrained instruction/data memory, connected to RVFI |
| `checks.cfg` | riscv-formal configuration: RV32IM, aligned memory, ALTOPS, U-mode, check depths |
| `run_riscv_formal.py` | Clones riscv-formal (pinned), generates the checks, runs them in parallel, writes `results.txt` |
| `results.txt` | Latest full result |

```powershell
python formal/riscv-formal/run_riscv_formal.py           # all checks
python formal/riscv-formal/run_riscv_formal.py -k reg    # checks matching a regex
python formal/riscv-formal/run_riscv_formal.py --rtl <copy of riscv_processor_cpu>   # e.g. a mutated copy
```

Method, results and the bugs it found: [docs/phase5_formal_verification.md](../../docs/phase5_formal_verification.md).
