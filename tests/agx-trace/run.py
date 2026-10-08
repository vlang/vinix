#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare native V tracing against frozen C using an independent driver model."""
from pathlib import Path
import argparse
import runpy
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "823aeb116eb3b3ab20463ccb9b1c3fba6f0c41ae"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-rev", default=BASELINE)
    args = parser.parse_args()
    command = runpy.run_path(str(ROOT / "tests/agx-fake-g17/_native.py"))["command"]
    command("trace_test", root=ROOT, baseline=args.baseline_rev,
            temp_dir=tempfile.gettempdir())


if __name__ == "__main__":
    main()
