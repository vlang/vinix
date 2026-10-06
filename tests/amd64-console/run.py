#!/usr/bin/env python3
"""Run the independent console regression in an isolated x86_64 guest."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    return subprocess.call([
        sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
        "--arch", "x86_64", "--kernel-dir", str(args.kernel_dir),
        "--source", str(ROOT / "tests/amd64-console/guestfixture/core.v"),
        "--state-dir", str(args.state_dir), "--timeout", str(args.timeout),
        "--expect", "TEST console: zero-length and nonblocking reads passed",
        "--expect", "TEST RESULT: PASS", "--fail", "TEST RESULT: FAIL",
    ])


if __name__ == "__main__":
    raise SystemExit(main())
