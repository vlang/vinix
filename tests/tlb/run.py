#!/usr/bin/env python3
"""Run active/inactive context and teardown regressions on four guest CPUs."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
if __name__ == '__main__':
    raise SystemExit(subprocess.call([
        sys.executable, str(ROOT / 'tests/process-smp/run.py'),
        '--source', str(Path(__file__).with_name('guest.c')),
        '--expect', 'TLB: ALL PASS', '--fail', 'FAIL: TLB',
        *sys.argv[1:],
    ]))
