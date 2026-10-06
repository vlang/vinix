#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run independent native V protocol/MMIO fixtures against production cores."""
from pathlib import Path
import subprocess
HERE = Path(__file__).resolve().parent
for suite in ("run-protocol.py", "run-platform.py"):
    subprocess.run(["python3", str(HERE / suite)], check=True)
print("PASS V Wi-Fi C ABI, ASan/UBSan and explicit allocator sites", flush=True)
