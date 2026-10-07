#!/usr/bin/env python3
"""Compile the terminal-jobs ABI test and boot it through an isolated existing VM driver."""
from pathlib import Path
import argparse
import importlib.util
import os
import runpy
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (b'TERMINAL JOBS PASS: permissions and sessions', b'TERMINAL JOBS PASS: stop and foreground signals',
            b'TERMINAL OWNED OPEN rounds=100 errors=0')


def compile_guest(work, arch):
    if arch == "aarch64":
        sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        command = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl",
            f"--sysroot={sysroot}", "-static", "-O2", "-pthread", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
            f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
    else:
        command = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"), "-static", "-O2", "-pthread",
            "-Wall", "-Wextra", "-Werror"]
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    object_path = compile_module(ROOT / "tests/terminal-jobs/guestfixture", work / "guest.o",
                                 "aarch64" if arch == "aarch64" else "x86_64", command)
    subprocess.run(command + [str(object_path), "-o", str(work / "init")], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    arguments = parser.parse_args()
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    runner_path = runner_root / ("tests/realtime/run_vm.py" if arguments.arch == "aarch64"
                                 else "tests/openbsd-security/run_vm.py")
    spec = importlib.util.spec_from_file_location("terminal-jobs_vm", runner_path)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"TERMINAL JOBS GUEST: PASS"
    runner.FAIL_MARKERS = (b"TERMINAL JOBS FAIL", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = FEATURES
    with tempfile.TemporaryDirectory(prefix="vinix-terminal-jobs-vm-") as directory:
        work = Path(directory)
        compile_guest(work, arguments.arch)
        for name in ("root", "sbin", "proc", "sys", "dev"):
            (work / "rootfs" / name).mkdir(parents=True)
        if arguments.arch == "amd64":
            shutil.copy2(work / "init", work / "rootfs/sbin/init")
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "initramfs.tar"),
            "-C", str(work / "rootfs"), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
        if arguments.arch == "aarch64":
            os.environ["VINIX_QEMU_SMP"] = "4"
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
        runner.REPORT_MARKER = b""  # This test does not provoke pledge violations.
        original_command_for = runner.command_for

        def command_four_cpus(arguments, root):
            command, environment = original_command_for(arguments, root)
            assert command[command.index("-smp") + 1] == "2"
            command[command.index("-smp") + 1] = "4"
            return command, environment

        runner.command_for = command_four_cpus
        sys.argv = [str(runner_path), "--arch", "amd64", "--iso", str(work / "test.iso"),
            "--qemu", str(qemu), "--firmware", firmware, "--capture", str(work / "unused.pcap"),
            "--timeout", str(timeout)]
        return runner.main()


if __name__ == "__main__":
    raise SystemExit(main())
