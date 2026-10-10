#!/usr/bin/env python3
"""Exercise production enqueue target selection with synthetic CPU snapshots."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
generator = os.environ.get("VINIX_SCHEDULER_PREEMPTION_GENERATOR")
command = ([generator] if generator else [str(root / "build-support/run-v-tool.sh"),
                                         str(Path(__file__).with_suffix(".v"))])
# Assemble before creating the original fixture owner, preserving read failures.
program = subprocess.check_output([*command, "--assemble", str(root)], text=True)
with tempfile.TemporaryDirectory(prefix="vinix-enqueue-policy-") as directory:
    path = Path(directory)
    (path / "v.mod").write_text("Module { name: 'preemption_test' }\n")
    (path / "main.v").write_text(program)
    subprocess.run([*command, "--modules", directory], check=True)
    subprocess.run([os.environ.get("V", "v"), "-enable-globals", "run", directory], check=True)
