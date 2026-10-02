#!/usr/bin/env python3
"""Compile the cpu-mitigations ABI test and boot it through an isolated existing VM driver."""
from pathlib import Path
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (b'CPU MITIGATION PASS: syscall register preservation', b'CPU MITIGATION PASS: faulting DS and ES syscall restores recover', b'CPU MITIGATION PASS: timer interrupts and signed signal returns', b'CPU MITIGATION PASS: threads, CPU migration and process switches')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="amd64")
    parser.add_argument("--segments", action="store_true")
    parser.add_argument("--cpu", default="max")
    parser.add_argument("--smp", type=int, default=2)
    arguments = parser.parse_args()
    if arguments.arch != "amd64": parser.error("The executable CPU instruction guest is x86-64 only.")
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    runner_path = runner_root / ("tests/realtime/run_vm.py" if arguments.arch == "aarch64"
                                 else "tests/openbsd-security/run_vm.py")
    spec = importlib.util.spec_from_file_location("cpu-mitigations_vm", runner_path)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"CPU MITIGATION GUEST: PASS"
    runner.FAIL_MARKERS = (b"CPU MITIGATION FAIL", b"QEMU CORE FAIL", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = (b"QEMU CORE PASS: x86-64 TLS descriptors, LDT and 32-bit code",) if arguments.segments else FEATURES
    source = ROOT / "tests/cpu-mitigations" / ("segments.c" if arguments.segments else "guest.c")
    with tempfile.TemporaryDirectory(prefix="vinix-cpu-mitigations-vm-") as directory:
        work = Path(directory)
        if arguments.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            command = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl",
                f"--sysroot={sysroot}", "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                str(source), str(ROOT / "tests/cpu-mitigations/probe.S"), f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
                "-o", str(work / "init")]
        else:
            command = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"), "-static", "-O2",
                "-Wall", "-Wextra", "-Werror", "-pthread", str(source), str(ROOT / "tests/cpu-mitigations/probe.S"),
                "-o", str(work / "init")]
        subprocess.run(command, check=True)
        for name in ("root", "sbin", "proc", "sys", "dev"):
            (work / "rootfs" / name).mkdir(parents=True)
        if arguments.arch == "amd64":
            shutil.copy2(work / "init", work / "rootfs/sbin/init")
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "initramfs.tar"),
            "-C", str(work / "rootfs"), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
        if arguments.arch == "aarch64":
            return runner.run_vm(runner_root, work / "init", work / "initramfs.tar", work / "vm", timeout)
        environment = {**os.environ,
            "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(ROOT / "kernel/bin/vinix")),
            "VINIX_AMD64_INITRAMFS": str(work / "initramfs.tar"),
            "VINIX_AMD64_ISO": str(work / "test.iso"),
            "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso"),
        }
        subprocess.run([str(runner_root / "build-support/build-amd64-iso.sh")], env=environment, check=True)
        qemu = Path(shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64")))
        firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        original_command = runner.command_for
        def configured_command(arguments_, root_):
            command_, environment_ = original_command(arguments_, root_)
            command_[command_.index("-cpu")+1] = arguments.cpu
            command_[command_.index("-smp")+1] = str(arguments.smp)
            return command_, environment_
        runner.command_for = configured_command
        runner.REPORT_MARKER = b""  # This test does not provoke pledge violations.
        sys.argv = [str(runner_path), "--arch", "amd64", "--iso", str(work / "test.iso"),
            "--qemu", str(qemu), "--firmware", firmware, "--capture", str(work / "unused.pcap"),
            "--timeout", str(timeout)]
        return runner.main()


if __name__ == "__main__":
    raise SystemExit(main())
