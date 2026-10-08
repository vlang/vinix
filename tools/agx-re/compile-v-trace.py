#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Generate the allocation-explicit native V AGX tracing core."""
from pathlib import Path
import argparse
import runpy
import tempfile
ROOT = Path(__file__).resolve().parents[2]
_command = runpy.run_path(str(ROOT / "tests/agx-fake-g17/_native.py"))["command"]
def generate(output, arch="arm64"):
    _command("trace_generate", root=ROOT, output=output, arch=arch, temp_dir=tempfile.gettempdir())
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="arm64")
    args = parser.parse_args()
    generate(args.output, args.arch)
