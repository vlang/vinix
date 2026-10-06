#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Run all independent native V Wi-Fi control scenarios with sanitizers."""
from pathlib import Path
import subprocess
import sys
raise SystemExit(subprocess.call([sys.executable, str(Path(__file__).with_name("run-control.py")), *sys.argv[1:]]))
