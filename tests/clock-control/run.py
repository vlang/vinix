#!/usr/bin/env python3
"""Compile the independent V clock ABI fixture and run its isolated VM."""
from pathlib import Path
import importlib.util
import os
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    spec = importlib.util.spec_from_file_location("clock_vm", runner_root / "tests/realtime/run_vm.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"VINIX CLOCK CONTROL: PASS"
    runner.FAIL_MARKERS = (b"VINIX CLOCK CONTROL: FAIL", b"CLOCK CONTROL FAIL", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = (
        b"CLOCK CONTROL PASS: wall steps preserve uptime",
        b"CLOCK CONTROL PASS: discipline ABI validates modes and bounds",
        b"CLOCK CONTROL PASS: privilege and securelevel guard changes",
        b"CLOCK CONTROL PASS: realtime steps adjust sleeps and absolute timers",
    )
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
    with tempfile.TemporaryDirectory(prefix="vinix-clock-vm-") as directory:
        work = Path(directory)
        flags = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl",
            f"--sysroot={sysroot}", "-static", "-O2", "-fno-stack-protector",
            "-fno-strict-aliasing", "-D_GNU_SOURCE", "-Wall", "-Wextra", "-Werror"]
        helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
        fixture = helper["compile_module"](ROOT / "tests/clock-control/clockfixture",
                                           work / "fixture.o", "aarch64", flags)
        subprocess.run(flags + [str(fixture), f"-L{sysroot / 'lib'}",
            "-fuse-ld=lld", "-o", str(work / "init")], check=True)
        for name in ("root", "sbin", "proc", "sys"):
            (work / "rootfs" / name).mkdir(parents=True)
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "initramfs.tar"),
            "-C", str(work / "rootfs"), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        raise SystemExit(runner.run_vm(runner_root, work / "init", work / "initramfs.tar",
            work / "vm", int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))))

if __name__ == "__main__":
    main()
