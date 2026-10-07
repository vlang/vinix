#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Temporary import bridge to the native V declaration/ABI metadata generator.

Retained for Python callers of generate(); metadata algorithms live in V.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
COMMAND = [str(ROOT / "build-support/run-v-tool.sh"),
           str(ROOT / "tests/linuxkpi/generate_abi.v")]


def generate(schema_path, source_root, output):
    subprocess.run(COMMAND + [str(schema_path), str(output), "--source-root",
                              str(source_root)], check=True)


if __name__ == "__main__":
    raise SystemExit(subprocess.call(COMMAND + sys.argv[1:]))
