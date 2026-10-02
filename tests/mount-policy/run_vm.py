#!/usr/bin/env python3
"""Reuse the security runner's isolated VM and strict serial-result checks."""
import importlib.util
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "openbsd-security" / "run_vm.py"
spec = importlib.util.spec_from_file_location("vinix_security_vm", path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
runner.TEST_LABEL = "mount-policy"
runner.PASS_MARKER = b"VINIX MOUNT POLICY: PASS"
runner.FAIL_MARKERS = (
    b"VINIX MOUNT POLICY: FAIL", b"MOUNT POLICY FAIL line",
    b"FATAL EXCEPTION", b"KERNEL PANIC",
)
runner.FEATURE_MARKERS = (
    b"MOUNT POLICY PASS: noexec images, scripts, symlinks and ELF interpreters",
    b"MOUNT POLICY PASS: noexec mmap and protection ceilings survive split, fork and remap",
    b"MOUNT POLICY PASS: bind aliases retain independent policy through cwd, fds and proc links",
    b"MOUNT POLICY PASS: nodev blocks character and block devices, with O_PATH and ordinary files usable",
    b"MOUNT POLICY PASS: namespace remounts and self binds preserve mount identity",
    b"MOUNT POLICY PASS: W^X exceptions require administrator launch or executable mount policy",
    b"MOUNT POLICY PASS: nested shared mounts retain the alias used to enter them",
    b"MOUNT POLICY PASS: bounded mount context overflow fails closed with ELOOP",
    b"MOUNT POLICY PASS: shared cwd, root and mount moves keep node and policy snapshots consistent",
)
# These tests exercise mount policy and never trigger a pledge violation.
runner.REPORT_MARKER = b""

if __name__ == "__main__":
    raise SystemExit(runner.main())
