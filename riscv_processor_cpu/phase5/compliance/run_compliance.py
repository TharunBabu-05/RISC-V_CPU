#!/usr/bin/env python3
"""
run_compliance.py - Run the official riscv-tests ISA suites on this CPU.

Builds every test of the selected suites from riscv-tests/isa (the "p"
environment: physical memory, single core), simulates it with Icarus
Verilog on the chosen core, and reads the result the test writes to
`tohost` (1 = pass, (n << 1) | 1 = test case n failed).

Cores:
  research   rtl/cpu_top.sv            (RV32IMF + Zicsr, separate I/D memories)
  soc        phase8/rtl/soc_top.sv     (the FPGA board design, RV32IM + Zicsr)
  soc-fpu    soc_top with the optional FPU enabled (HAS_FPU = 1)

Examples:
  python phase5/compliance/run_compliance.py                       # all cores, all suites
  python phase5/compliance/run_compliance.py --core soc --suite rv32ui
  python phase5/compliance/run_compliance.py --test rv32ui-add -v

Requirements: riscv-none-elf-gcc (or set CROSS=<prefix>), iverilog/vvp,
and a riscv-tests checkout next to riscv_processor_cpu/ (or --riscv-tests).
Results are written to phase5/compliance/results/<core>.txt.
"""
import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CPU = HERE.parent.parent                       # riscv_processor_cpu/
DEFAULT_TESTS = CPU.parent / "riscv-tests"
BUILD = HERE / "build"
RESULTS = HERE / "results"

RTL_RESEARCH = ["alu", "muldiv", "regfile", "imm_gen", "csr_file", "interrupt_unit", "pmp_unit", "branch_predictor",
                "fp_regfile", "fpu_unit", "vector_regfile", "vector_unit", "control_unit", "hazard", "memory",
                "dram_ctrl", "l2_cache", "dcache", "icache", "mmu", "cpu_top"]
RTL_SOC_SHARED = ["alu", "branch_predictor", "control_unit", "csr_file", "fp_regfile", "fpu_unit", "hazard", "pmp_unit",
                  "imm_gen", "interrupt_unit", "regfile", "vector_regfile", "vector_unit", "muldiv"]
RTL_SOC = ["soc_top", "cpu_top_soc", "uart_tx", "uart_rx", "uart", "bram"]

# Tests that need an optional feature this CPU does not implement. They are
# still run and reported, as N/A, and do not count as failures.
NOT_APPLICABLE = {}

CORES = {
    #           suites run by default                 -march for the tests      link base
    "research": (["rv32ui", "rv32um", "rv32mi", "rv32uf"], "rv32imf_zicsr_zifencei", 0x80000000),
    "soc":      (["rv32ui", "rv32um", "rv32mi"],           "rv32im_zicsr_zifencei",  0x0),
    "soc-fpu":  (["rv32uf"],                               "rv32imf_zicsr_zifencei", 0x0),
}


def suite_tests(tests_root, suite):
    text = (tests_root / "isa" / suite / "Makefrag").read_text()
    m = re.search(rf"{suite}_sc_tests\s*=\s*\\?\s*(.*?)\n\s*\n", text, re.S)
    return [t for t in m.group(1).replace("\\", " ").split() if t]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def link_script(base, out):
    """riscv-tests env/p/link.ld with the memory placed at `base`."""
    src = (args.riscv_tests / "env" / "p" / "link.ld").read_text()
    out.write_text(src.replace(". = 0x80000000;", f". = 0x{base:08x};"))
    return out


def build_test(core, suite, test):
    _, march, base = CORES[core]
    out = BUILD / core
    out.mkdir(parents=True, exist_ok=True)
    name = f"{suite}-p-{test}"
    elf, hexf = out / f"{name}.elf", out / f"{name}.hex"
    ld = out / "link.ld"
    isa = args.riscv_tests / "isa"
    r = run([args.cross + "gcc", f"-march={march}", "-mabi=ilp32", "-static", "-mcmodel=medany",
             "-fvisibility=hidden", "-nostdlib", "-nostartfiles",
             "-I", str(args.riscv_tests / "env" / "p"), "-I", str(isa / "macros" / "scalar"),
             "-T", str(ld), str(isa / suite / f"{test}.S"), "-o", str(elf)])
    if r.returncode:
        return None, None, r.stderr.strip().splitlines()[-1:] or ["build failed"]
    r = run([args.cross + "objcopy", "-O", "verilog", "--verilog-data-width=4",
             f"--change-addresses=-0x{base:x}", str(elf), str(hexf)])
    if r.returncode:
        return None, None, [r.stderr.strip()]
    sym = run([args.cross + "nm", str(elf)]).stdout
    tohost = int(re.search(r"^([0-9a-f]+) \S tohost$", sym, re.M).group(1), 16) - base
    return hexf, tohost, None


def compile_tb(core):
    out = BUILD / core
    out.mkdir(parents=True, exist_ok=True)
    vvp = out / "tb.vvp"
    rtl = CPU / "rtl"
    if core == "research":
        files = [rtl / f"{m}.sv" for m in RTL_RESEARCH] + [CPU / "tb" / "tb_riscv_tests.sv"]
        cmd = ["iverilog", "-g2012", "-o", str(vvp)] + [str(f) for f in files]
    else:
        files = ([CPU / "phase8" / "rtl" / f"{m}.sv" for m in RTL_SOC] + [rtl / f"{m}.sv" for m in RTL_SOC_SHARED]
                 + [CPU / "tb" / "tb_riscv_tests_soc.sv"])
        cmd = ["iverilog", "-g2012", "-DSIMULATION",
               f"-Ptb_riscv_tests_soc.HAS_FPU={1 if core == 'soc-fpu' else 0}", "-o", str(vvp)] + [str(f) for f in files]
    r = run(cmd)
    errors = [l for l in r.stderr.splitlines() if "error" in l.lower()]
    if r.returncode or errors:
        sys.exit(f"[{core}] testbench compile failed:\n" + "\n".join(errors or r.stderr.splitlines()[-5:]))
    return vvp


def run_test(core, vvp, suite, test):
    hexf, tohost, err = build_test(core, suite, test)
    if err:
        return suite, test, "BUILD-ERROR", " ".join(err)
    r = run(["vvp", "-n", str(vvp), f"+HEX={hexf.as_posix()}", f"+TOHOST={tohost:x}", f"+TIMEOUT={args.timeout}"],
            cwd=str(BUILD / core), timeout=1800)
    m = re.search(r"RESULT (\w+)(.*)", r.stdout)
    if not m:
        return suite, test, "SIM-ERROR", (r.stdout + r.stderr).strip().splitlines()[-1:]
    status, detail = m.group(1), m.group(2).strip()
    if status != "PASS" and f"{suite}-{test}" in NOT_APPLICABLE:
        return suite, test, "N/A", f"{NOT_APPLICABLE[suite + '-' + test]} ({status.lower()} {detail})"
    return suite, test, status, detail


def main():
    global args
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--core", choices=list(CORES) + ["all"], default="all")
    p.add_argument("--suite", action="append", help="suite(s) to run, e.g. rv32ui (default: the core's suites)")
    p.add_argument("--test", help="single test, e.g. rv32ui-add")
    p.add_argument("--riscv-tests", type=Path, default=Path(os.environ.get("RISCV_TESTS", DEFAULT_TESTS)))
    p.add_argument("--cross", default=os.environ.get("CROSS", "riscv-none-elf-"))
    p.add_argument("--timeout", type=int, default=200000, help="cycles per test")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 2)
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()

    for tool in (args.cross + "gcc", "iverilog", "vvp"):
        if not shutil.which(tool):
            sys.exit(f"missing tool: {tool}")
    if not (args.riscv_tests / "env" / "p" / "riscv_test.h").exists():
        sys.exit(f"riscv-tests (with its env submodule) not found at {args.riscv_tests}")

    cores = list(CORES) if args.core == "all" else [args.core]
    RESULTS.mkdir(exist_ok=True)
    total_fail = 0
    for core in cores:
        suites, _, base = CORES[core]
        if args.test:
            suite, test = args.test.split("-", 1)
            jobs = [(suite, test)]
        else:
            jobs = [(s, t) for s in (args.suite or suites) for t in suite_tests(args.riscv_tests, s)]
        (BUILD / core).mkdir(parents=True, exist_ok=True)
        link_script(base, BUILD / core / "link.ld")
        vvp = compile_tb(core)
        t0 = time.time()
        with concurrent.futures.ThreadPoolExecutor(args.jobs) as ex:
            results = list(ex.map(lambda st: run_test(core, vvp, *st), jobs))
        passed = sum(1 for r in results if r[2] == "PASS")
        na = sum(1 for r in results if r[2] == "N/A")
        lines = [f"# riscv-tests on core '{core}': {passed}/{len(results) - na} applicable tests passed"
                 f" ({na} not applicable), {time.time() - t0:.0f} s", ""]
        for suite, test, status, detail in results:
            lines.append(f"{status:<12} {suite}-p-{test:<20} {detail if status != 'PASS' or args.verbose else ''}".rstrip())
        report = "\n".join(lines) + "\n"
        if not args.test:
            (RESULTS / f"{core}.txt").write_text(report)
        print(report)
        total_fail += len(results) - passed - na
    sys.exit(1 if total_fail else 0)


if __name__ == "__main__":
    main()
