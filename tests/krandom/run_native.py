#!/usr/bin/env python3
"""Measure production random reseeding and partial reads on an isolated kernel."""
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
        ["git", "-C", str(kernel.parent), "rev-parse", "--git-common-dir"], text=True).strip())
    if not common.is_absolute():
        common = kernel.parent / common
    if kernel.parent == common.resolve().parent:
        parser.error("use an isolated git worktree for the kernel build")
    if not compiler.is_file():
        parser.error(f"V compiler missing: {compiler}")
    state.mkdir(parents=True, exist_ok=False)
    # Test defines are not part of the ordinary object stamp. Never use a
    # generated-C object built without the requested native test.
    for file in ("obj/blob.c", "obj/blob.c.o", "obj/blob.c.d"):
        (kernel / file).unlink(missing_ok=True)
    env = os.environ.copy()
    env["VEXE"] = str(compiler)
    command = ["make", "-C", str(kernel), "-j4", "CC=clang", f"V={compiler}",
               f"ARCH={args.arch}", "PROD=false", "VFLAGS=-d krandom_selftest"]
    if args.arch == "x86_64":
        linker = shutil.which("ld.lld")
        if not linker:
            parser.error("ld.lld is required")
        command.append(f"LD_X86_64={linker}")
    with (state / "build.log").open("w") as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    return subprocess.run([
        sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
        "--kernel-dir", str(kernel), "--arch", args.arch,
        "--source", str(ROOT / "tests/kernel-gaps/smokefixture/core.v"),
        "--state-dir", str(state / "guest"), "--timeout", "240",
        "--expect", "RANDOM-RESEED: 10000 reseeds and partial reads PASS",
        "--expect", "KERNEL GUEST RUNNER: PASS"], env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
