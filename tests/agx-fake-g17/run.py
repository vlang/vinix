#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run independent verifier/encoder fixtures against the production V core."""
import argparse
import os
from pathlib import Path
import platform
import runpy

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--c-encoder-reference", type=Path,
                    help="Compare an immutable original encoder fixture")
parser.add_argument("--c-verifier-reference", type=Path,
                    help="Compare an immutable original verifier fixture")
args = parser.parse_args()
arch = os.environ.get("VINIX_G17_TEST_ARCH", "aarch64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64")
if arch not in ("aarch64", "x86_64"):
    parser.error("unsupported host architecture")
command = runpy.run_path(str(ROOT / "tests/agx-fake-g17/_native.py"))["command"]
command("host", root=ROOT, machine=platform.machine(),
        encoder_reference=args.c_encoder_reference or "",
        verifier_reference=args.c_verifier_reference or "")
