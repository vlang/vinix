#!/usr/bin/env python3
"""Qualify filesystem retirement and repeated-path retention in an SMP guest."""
from pathlib import Path
import runpy
import sys

root = Path(__file__).resolve().parents[2]
sys.argv = [str(root / "tests/process-smp/run.py"), *sys.argv[1:],
            "--source", str(Path(__file__).with_name("guest.c")),
            "--expect", "RETENTION PASS", "--fail", "RETENTION FAIL"]
runpy.run_path(sys.argv[0], run_name="__main__")
