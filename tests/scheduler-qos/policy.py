#!/usr/bin/env python3
"""Exercise production capacity selection, donation graphs and timer deadlines."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="vinix-scheduler-qos-") as directory:
    generator = os.environ.get("VINIX_SCHEDULER_QOS_GENERATOR")
    command = ([generator] if generator else [str(ROOT / "build-support/run-v-tool.sh"),
                                             str(Path(__file__).with_suffix(".v"))])
    subprocess.run([*command, str(ROOT), directory], check=True)
    subprocess.run([os.environ.get("VEXE", os.environ.get("V", "v")),
                    "-enable-globals", "run", directory], check=True)
