#!/usr/bin/env python3
"""Run scheduler and PI regressions in a disposable four-CPU guest."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
if __name__ == "__main__":
    raise SystemExit(subprocess.call([
        sys.executable, str(ROOT / "tests/process-smp/run.py"),
        "--source", str(Path(__file__).with_name("guest.c")),
        "--expect", "SCHED-QOS PASS", "--fail", "SCHED-QOS FAIL", "--smp", "4", "--memory", "8192",
        *sys.argv[1:],
    ]))
