#!/usr/bin/env python3
"""Build and exercise production ACPI gates in an isolated kernel worktree."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-dir", type=Path, required=True)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--v", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    args = parser.parse_args()
    kernel = args.kernel_dir.resolve()
    compiler = args.v.resolve()
    state = args.state_dir.resolve()
    common = Path(subprocess.check_output(
        ["git", "-C", str(kernel.parent), "rev-parse", "--git-common-dir"],
        text=True).strip())
    if not common.is_absolute():
        common = kernel.parent / common
    if kernel.parent == common.resolve().parent:
        parser.error("use an isolated git worktree for the kernel build")
    if not compiler.is_file():
        parser.error(f"V compiler missing: {compiler}")
    state.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["VEXE"] = str(compiler)
    command = ["make", "-C", str(kernel), "-j4", "CC=clang", f"V={compiler}",
               f"ARCH={args.arch}", "ACPI_SYNC_TEST=1", "STACK_GUARD_TEST=0"]
    if env.get("AR"):
        command.append(f"AR={env['AR']}")
    linker = shutil.which("ld.lld")
    if not linker:
        parser.error("ld.lld is required")
    if args.arch == "aarch64":
        command.extend(["LIMINE_MP=1", f"LD_AARCH64={linker}"])
    else:
        command.append(f"LD_X86_64={linker}")
    with (state / "build.log").open("w") as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    command = [sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
               "--kernel-dir", str(kernel), "--arch", args.arch,
               "--source", str(ROOT / "tests/kernel-gaps/smokefixture/core.v"),
               "--state-dir", str(state / "guest"),
               "--expect", "ACPI-SYNC: bootstrap polling PASS",
               "--expect", "ACPI-SYNC: ALL PASS",
               "--expect", "KERNEL GUEST RUNNER: PASS"]
    return subprocess.run(command, env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
