#!/usr/bin/env python3
"""Test production x86 tag ownership and direct-map splitting with host adapters."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

# Keep the original disposable owner and compiler launch. V owns extraction,
# fixture modules and assembly; existing V assertions stay independent fixtures.
with tempfile.TemporaryDirectory(prefix="vinix-address-space-") as work:
    generator = os.environ.get("VINIX_TLB_POLICY_GENERATOR")
    command = ([generator] if generator else [str(ROOT / "build-support/run-v-tool.sh"),
                                             str(Path(__file__).with_suffix(".v"))])
    subprocess.run([*command, str(ROOT), work], check=True)
    subprocess.run([os.environ.get("V", "v"), "-enable-globals", "run", work], check=True)
