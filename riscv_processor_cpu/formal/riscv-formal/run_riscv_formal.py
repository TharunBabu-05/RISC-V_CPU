#!/usr/bin/env python3
"""
run_riscv_formal.py - Run riscv-formal (YosysHQ) on the FPGA SoC core.

riscv-formal checks every retired instruction against a formal ISA model
(insn_* checks), plus register-file consistency, PC continuity, causality,
uniqueness of the retirement order and illegal-instruction trapping, all
over unconstrained instruction and data memory. See checks.cfg.

Usage:
    python formal/riscv-formal/run_riscv_formal.py               # all checks
    python formal/riscv-formal/run_riscv_formal.py -k insn_add   # checks matching a regex
    python formal/riscv-formal/run_riscv_formal.py --riscv-formal <checkout>

Needs: git, yosys / sby / boolector (oss-cad-suite; ../oss-cad-suite is used
automatically if present). riscv-formal is cloned at a pinned commit into
formal/riscv-formal/.riscv-formal/ unless --riscv-formal is given.
Results: formal/riscv-formal/results.txt
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
CPU = HERE.parent.parent                    # riscv_processor_cpu/
REPO = "https://github.com/YosysHQ/riscv-formal.git"
PINNED = "c992aa61fdfe0846c5ed90324c596202a1c69b76"
CORE = "rv32soc"


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--riscv-formal", type=Path, help="existing riscv-formal checkout")
    p.add_argument("-k", "--filter", default=".", help="regex selecting check names")
    p.add_argument("-j", "--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    p.add_argument("--timeout", type=int, default=7200, help="seconds per check")
    p.add_argument("--rtl", type=Path, default=CPU, help="riscv_processor_cpu tree to verify (default: this one)")
    args = p.parse_args()

    oss = CPU.parent / "oss-cad-suite"
    if (oss / "bin").exists():
        os.environ["PATH"] = os.pathsep.join([str(oss / "bin"), str(oss / "lib"), os.environ["PATH"]])
    for tool in ("yosys", "sby", "boolector"):
        if not shutil.which(tool):
            sys.exit(f"missing tool: {tool} (install oss-cad-suite)")

    rf = args.riscv_formal or HERE / ".riscv-formal"
    if not (rf / "checks" / "genchecks.py").exists():
        print(f"cloning riscv-formal {PINNED[:7]} into {rf}")
        r = sh(["git", "clone", "-q", REPO, str(rf)])
        if r.returncode:
            sys.exit(r.stderr)
        sh(["git", "-C", str(rf), "checkout", "-q", PINNED])

    core_dir = rf / "cores" / CORE
    if core_dir.exists():
        shutil.rmtree(core_dir)
    core_dir.mkdir(parents=True)
    shutil.copy(HERE / "wrapper.sv", core_dir / "wrapper.sv")
    cfg = (HERE / "checks.cfg").read_text().replace("@rtl@", args.rtl.resolve().as_posix())
    cfg = cfg.replace("@wrapper@", (core_dir / "wrapper.sv").as_posix())
    (core_dir / "checks.cfg").write_text(cfg)

    r = sh([sys.executable, str(rf / "checks" / "genchecks.py")], cwd=str(core_dir))
    if r.returncode:
        sys.exit("genchecks failed:\n" + r.stdout + r.stderr)
    checks_dir = core_dir / "checks"
    pattern = re.compile(args.filter)
    checks = sorted(f.stem for f in checks_dir.glob("*.sby") if pattern.search(f.stem))
    print(f"running {len(checks)} checks with {args.jobs} jobs")

    def run_check(name):
        t0 = time.time()
        try:
            r = sh(["sby", "-f", f"{name}.sby"], cwd=str(checks_dir), timeout=args.timeout)
            out = r.stdout
        except subprocess.TimeoutExpired:
            return name, "TIMEOUT", time.time() - t0
        m = re.findall(r"DONE \((\w+), rc=", out)
        status = m[-1] if m else "ERROR"
        print(f"{status:<8} {name}  ({time.time() - t0:.0f} s)", flush=True)
        return name, status, time.time() - t0

    t0 = time.time()
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as ex:
        results = list(ex.map(run_check, checks))

    passed = sum(1 for _, s, _ in results if s == "PASS")
    lines = [f"# riscv-formal on cpu_top_soc (RV32IM, ALTOPS, aligned memory): "
             f"{passed}/{len(results)} checks passed, {time.time() - t0:.0f} s", ""]
    lines += [f"{s:<8} {n:<28} {t:6.0f} s" for n, s, t in results]
    report = "\n".join(lines) + "\n"
    if args.filter == "." and args.rtl.resolve() == CPU:
        (HERE / "results.txt").write_text(report)
    print(report)
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
