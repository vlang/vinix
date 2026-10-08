#!/usr/bin/env python3
"""Run independent G17 oracles and unchanged V policy in QEMU."""
import argparse
from pathlib import Path
import runpy
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--kernel-dir", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--c-reference", type=Path)
    parser.add_argument("--fixture", choices=("encoder", "verifier"), default="encoder")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    command = runpy.run_path(str(ROOT / "tests/agx-fake-g17/_native.py"))["command"]
    inherited = subprocess.check_output(["/usr/bin/env", "-0"]).hex()
    return command("native_fixture", root=ROOT, arch=args.arch,
                   kernel=args.kernel_dir, state=args.state_dir,
                   reference=args.c_reference or "", fixture=args.fixture,
                   timeout_text=str(args.timeout), python=sys.executable,
                   inherited_environment_hex=inherited)


if __name__ == "__main__":
    raise SystemExit(main())
