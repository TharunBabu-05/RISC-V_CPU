#!/usr/bin/env python3
"""
run_regression.py - Compile and run every directed / unit testbench.

A testbench passes when it finishes ($finish), prints no FAIL/ERROR line and,
if it has a summary line, that line says "All checks passed". The exit code is
non-zero if any testbench fails, so `make regress` cannot report a false pass.

    python tb/run_regression.py            # everything
    python tb/run_regression.py -k fpu     # testbenches whose name contains "fpu"
"""
import argparse
import concurrent.futures
import re
import subprocess
import sys
from pathlib import Path

CPU = Path(__file__).resolve().parent.parent
SIM = CPU / "sim" / "regress"          # build/run directory (not committed)
RTL = ["alu", "muldiv", "regfile", "imm_gen", "csr_file", "interrupt_unit", "pmp_unit", "branch_predictor", "fp_regfile",
       "fpu_unit", "vector_regfile", "vector_unit", "control_unit", "hazard", "memory", "dram_ctrl", "l2_cache",
       "dcache", "icache", "mmu", "cpu_top"]

# testbenches that run the whole research core
CPU_TBS = ["tb_cpu", "tb_muldiv", "tb_branch_edge", "tb_cpu64", "tb_mmu", "tb_fp", "tb_vector", "tb_phase6_alu",
           "tb_phase6_hazards", "tb_phase6_control", "tb_csr_forward", "tb_dcache_store", "tb_branch_predict",
           "tb_irq_precise", "tb_trap", "tb_mem_stall", "tb_rv64_jalr", "tb_btb_stale"]
CPU_TBS += ["tb_pmp", "tb_privilege", "tb_unaligned"]
# unit testbenches: (name, rtl modules, vector generator)
UNIT_TBS = [("tb_muldiv_unit", ["muldiv"], None),
            ("tb_mmu_unit", ["mmu"], None),
            ("tb_fpu_unit", ["fpu_unit"], "fpu_ref.py"),
            ("tb_vector_unit", ["vector_unit"], "vec_ref.py")]
UNIT_TBS += [("tb_bram_unaligned", ["../phase8/rtl/bram"], None)]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def run_tb(name, files, plusargs=()):
    exe = SIM / name
    r = run(["iverilog", "-g2012", "-I", str(CPU / "rtl"), "-I", str(CPU / "tb"), "-o", str(exe)] + files)
    errors = [l for l in r.stderr.splitlines() if "error" in l.lower()]
    if r.returncode or errors:
        return name, False, "compile: " + (errors or r.stderr.splitlines()[-1:] or ["?"])[0]
    r = run(["vvp", "-n", str(exe)] + list(plusargs), cwd=str(SIM), timeout=3600)
    out = r.stdout + r.stderr
    bad = [l for l in out.splitlines() if re.search(r"\bFAIL|ERROR", l)]
    summary = [l for l in out.splitlines() if "checks passed" in l.lower() or "FAILED" in l]
    ok = ("$finish" in out) and not bad and all("passed" in l.lower() for l in summary)
    detail = (summary[-1].strip() if summary else f"{sum('PASS' in l for l in out.splitlines())} PASS lines")
    return name, ok, detail if ok else (bad[0].strip() if bad else "did not finish")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("-k", "--filter", default="")
    p.add_argument("-j", "--jobs", type=int, default=4)
    args = p.parse_args()
    SIM.mkdir(parents=True, exist_ok=True)

    rtl = [str(CPU / "rtl" / f"{m}.sv") for m in RTL]
    jobs = []
    for tb in CPU_TBS:
        if args.filter in tb:
            jobs.append((tb, rtl + [str(CPU / "tb" / f"{tb}.sv")], ()))
    for tb, mods, gen in UNIT_TBS:
        if args.filter not in tb:
            continue
        plus = ()
        if gen:
            vec = SIM / (gen.replace("_ref.py", "_vectors.txt"))
            r = run([sys.executable, str(CPU / "tb" / gen), "vectors", str(vec)])
            if r.returncode:
                sys.exit(f"{gen} failed: {r.stderr}")
            plus = (f"+VECTORS={vec.name}",)
        jobs.append((tb, [str(CPU / "rtl" / f"{m}.sv") for m in mods] + [str(CPU / "tb" / f"{tb}.sv")], plus))

    with concurrent.futures.ThreadPoolExecutor(args.jobs) as ex:
        results = list(ex.map(lambda j: run_tb(*j), jobs))
    for name, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL':<5} {name:<20} {detail}")
    failed = sum(1 for _, ok, _ in results if not ok)
    print(f"\n{len(results) - failed}/{len(results)} testbenches passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
