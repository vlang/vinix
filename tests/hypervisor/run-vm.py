#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Boot the hypervisor guest; require actual VMX execution only when requested."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
parser.add_argument("--state-dir", type=Path)
parser.add_argument("--timeout", type=int, default=600)
parser.add_argument("--require-vmx", action="store_true",
                    help="fail unless IO/HLT guest execution passed (needs nested VT-x)")
args = parser.parse_args()
command = [sys.executable, str(ROOT / "tests/kernel-gaps/run.py"),
           "--source", str(ROOT / "tests/hypervisor/guest.c"), "--arch", args.arch,
           "--kernel-dir", str(args.kernel_dir), "--timeout", str(args.timeout),
           "--expect", "HYPERVISOR GUEST PASS", "--fail", "HYPERVISOR FAIL:"]
if args.state_dir:
    command += ["--state-dir", str(args.state_dir)]
if args.require_vmx:
    command += ["--expect", "HYPERVISOR EXECUTION PASS"]
raise SystemExit(subprocess.call(command))
