#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Cross-build and run all Wi-Fi control scenarios in a native model guest."""
import argparse
from pathlib import Path
import subprocess
import sys
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
p.add_argument("--kernel-dir", type=Path, required=True)
p.add_argument("--state-dir", type=Path, required=True)
p.add_argument("--timeout", type=int, default=300)
a = p.parse_args()
state = a.state_dir.resolve()
raise SystemExit(subprocess.call([sys.executable, str(Path(__file__).with_name("run-control.py")),
    "--arch", a.arch, "--kernel-dir", str(a.kernel_dir.resolve()),
    "--state-dir", str(state), "--guest-state-dir", str(state / "guest"),
    "--timeout", str(a.timeout)]))
