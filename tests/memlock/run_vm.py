#!/usr/bin/env python3
"""Reuse the security runner's isolated VM and strict serial-result checks."""
import importlib.util
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "openbsd-security" / "run_vm.py"
spec = importlib.util.spec_from_file_location("vinix_security_vm", path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
runner.TEST_LABEL = "memlock"
runner.PASS_MARKER = b"VINIX MEMLOCK: PASS"
runner.FAIL_MARKERS = (b"VINIX MEMLOCK: FAIL", b"KERNEL PANIC", b"FATAL EXCEPTION")
runner.FEATURE_MARKERS = (
    b"MEMLOCK PASS: range population and limits",
    b"MEMLOCK PASS: file and guard mappings",
    b"MEMLOCK PASS: fork, remap, replacement and exec",
    b"MEMLOCK PASS: current, future and heap locking",
    b"MEMLOCK PASS: capability and unsupported flags",
    b"MEMLOCK PASS: concurrent file replacement and remap",
    b"MEMLOCK PASS: repeated lock and unlock stay flat",
)
# These tests exercise memory locking and never trigger a pledge violation.
runner.REPORT_MARKER = b""

if __name__ == "__main__":
    raise SystemExit(runner.main())
