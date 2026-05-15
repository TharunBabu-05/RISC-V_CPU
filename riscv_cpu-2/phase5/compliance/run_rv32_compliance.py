#!/usr/bin/env python3
"""Run the Phase 5 RV32 compliance harness.

The runner can execute either the repository's directed regressions or an
external compliance suite checkout. It will auto-discover a sibling checkout
when one exists, or fall back to the local regression targets.
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable

PROFILE_TO_LOCAL_TARGET: Dict[str, str] = {
    "rv32i": "sim",
    "rv32im": "sim_muldiv",
}

PROFILE_TO_DESCRIPTION: Dict[str, str] = {
    "rv32i": "RV32I base integer profile",
    "rv32im": "RV32IM integer + mul/div profile",
}


def parse_profile_file(profile_path: Path) -> Dict[str, str]:
    profile: Dict[str, str] = {}
    for raw_line in profile_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        profile[key.strip().upper()] = value.strip()
    return profile


def iter_selected_profiles(requested: str) -> Iterable[str]:
    if requested == "all":
        return ("rv32i", "rv32im")
    return (requested,)


def discover_suite_root(repo_root: Path) -> Path | None:
    explicit_candidates = [
        repo_root.parent / "riscv-tests",
        repo_root.parent / "riscv-arch-test",
        repo_root.parent / "compliance",
        repo_root.parent / "tests",
    ]
    for candidate in explicit_candidates:
        if candidate.exists():
            return candidate.resolve()
    return None


def default_signature_dir(profile_name: str) -> str:
    return str(Path("phase5") / "compliance" / "signature" / profile_name)


def expand_command_template(template: str, context: Dict[str, str]) -> list[str]:
    return shlex.split(template.format(**context))


def run_command(command: list[str], cwd: Path, dry_run: bool) -> None:
    print(f"[phase5] running: {' '.join(command)} (cwd={cwd})")
    if dry_run:
        return
    subprocess.run(command, cwd=str(cwd), check=True)


def resolve_command(
    profile_name: str,
    profile: Dict[str, str],
    repo_root: Path,
    suite_root: Path | None,
    command_template: str | None,
) -> tuple[list[str], Path]:
    isa = profile.get("ISA", profile_name)
    xlen = profile.get("XLEN", "")
    extensions = profile.get("EXTENSIONS", "")
    suite = profile.get("TEST_SUITE", "riscv-tests")
    signature_dir = profile.get("SIGNATURE_DIR", default_signature_dir(profile_name))
    local_target = PROFILE_TO_LOCAL_TARGET.get(profile_name, "sim")

    context = {
        "repo_root": str(repo_root),
        "profile": profile_name,
        "isa": isa,
        "xlen": xlen,
        "extensions": extensions,
        "test_suite": suite,
        "suite_root": str(suite_root) if suite_root is not None else "",
        "signature_dir": signature_dir,
        "local_target": local_target,
    }

    template = command_template or os.environ.get("PHASE5_COMPLIANCE_COMMAND_TEMPLATE")
    if not template and suite_root is not None:
        template = profile.get("COMMAND_TEMPLATE")
    if template:
        return expand_command_template(template, context), repo_root

    if suite_root is not None:
        makefile = suite_root / "Makefile"
        run_sh = suite_root / "run.sh"
        if makefile.is_file():
            return [
                "make",
                "-C",
                str(suite_root),
                f"ISA={isa}",
                f"XLEN={xlen}",
                f"EXTENSIONS={extensions}",
                f"SIGNATURE_DIR={signature_dir}",
            ], suite_root
        if run_sh.is_file():
            return [str(run_sh), profile_name, signature_dir], suite_root

    return ["make", local_target], repo_root


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent
    profile_dir = script_dir

    parser = argparse.ArgumentParser(description="Run the Phase 5 RV32 compliance harness")
    parser.add_argument(
        "--profile",
        choices=("rv32i", "rv32im", "all"),
        default="all",
        help="Select one RV32 profile or run both",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the commands without executing them",
    )
    parser.add_argument(
        "--suite-root",
        default=os.environ.get("PHASE5_COMPLIANCE_SUITE_ROOT", ""),
        help="Path to an external riscv-tests or riscv-arch-test checkout",
    )
    parser.add_argument(
        "--command-template",
        default=os.environ.get("PHASE5_COMPLIANCE_COMMAND_TEMPLATE", ""),
        help="Command template with placeholders like {isa}, {xlen}, {suite_root}, {local_target}",
    )
    args = parser.parse_args()

    suite_root = Path(args.suite_root).resolve() if args.suite_root else discover_suite_root(repo_root)
    if suite_root is not None and not suite_root.exists():
        print(f"[phase5] suite root does not exist: {suite_root}", file=sys.stderr)
        return 2
    if suite_root is not None:
        print(f"[phase5] discovered suite root: {suite_root}")
    else:
        print("[phase5] no external suite root discovered; using local regression targets")

    for profile_name in iter_selected_profiles(args.profile):
        profile_path = profile_dir / f"{profile_name}.profile"
        if not profile_path.is_file():
            print(f"[phase5] missing profile file: {profile_path}", file=sys.stderr)
            return 2

        profile = parse_profile_file(profile_path)
        isa = profile.get("ISA", profile_name)
        xlen = profile.get("XLEN", "")
        extensions = profile.get("EXTENSIONS", "")
        signature_dir = profile.get("SIGNATURE_DIR", default_signature_dir(profile_name))
        if profile_name not in PROFILE_TO_LOCAL_TARGET:
            print(f"[phase5] unsupported profile: {profile_name}", file=sys.stderr)
            return 2

        print(f"[phase5] profile: {profile_name}")
        print(f"[phase5]  ISA={isa} XLEN={xlen} EXTENSIONS={extensions}")
        print(f"[phase5]  SIGNATURE_DIR={signature_dir}")
        print(f"[phase5]  description={PROFILE_TO_DESCRIPTION.get(profile_name, profile_name)}")
        command, cwd = resolve_command(
            profile_name=profile_name,
            profile=profile,
            repo_root=repo_root,
            suite_root=suite_root,
            command_template=args.command_template or None,
        )
        run_command(command, cwd, args.dry_run)

    print("[phase5] RV32 compliance harness complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
