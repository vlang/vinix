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
import importlib.util
_spec = importlib.util.spec_from_file_location("hypervisor_guest_native", ROOT / "tests/kernel-gaps/_native.py")
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)
options = {name: str(value) if isinstance(value, Path) else value for name, value in vars(args).items()}
options.update(root=str(ROOT), python=sys.executable, timeout=str(args.timeout))
raise SystemExit(_native.call("hypervisor", options, globals()))
