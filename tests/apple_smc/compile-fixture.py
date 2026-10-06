#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Generate the independent SMC mailbox fixture from maintained V."""
import argparse
from pathlib import Path
import platform
import runpy
ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("output", type=Path)
p.add_argument("--arch", choices=("arm64", "amd64"), default="arm64" if platform.machine() in ("arm64", "aarch64") else "amd64")
p.add_argument("--guest", action="store_true", help="keep the native fixture alive as PID 1")
a = p.parse_args()
runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"](
    Path(__file__).parent / "fixture", a.output.resolve(), a.arch,
    ("nofloat", "smc_guest") if a.guest else ("nofloat",))
