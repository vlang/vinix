#!/usr/bin/env python3
"""Check native kernel frame capture and live-site aggregation in QEMU."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--kernel-dir", type=Path, required=True,
                        help="Kernel built with ALLOC_TRACK=1")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    return subprocess.call([
        sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
        "--arch", args.arch, "--kernel-dir", str(args.kernel_dir),
        "--source", str(ROOT / "tests/alloc-track/guestfixture/core.v"),
        "--state-dir", str(args.state_dir), "--timeout", str(args.timeout),
        "--expect", "ALLOC TRACK GUEST PASS", "--fail", "ALLOC TRACK FAIL:",
    ])


if __name__ == "__main__":
    raise SystemExit(main())
