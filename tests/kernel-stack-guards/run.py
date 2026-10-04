#!/usr/bin/env python3
"""Boot opt-in stack-guard checks and verify runtime thread retirement."""
from pathlib import Path
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--kernel", type=Path, required=True)
    parser.add_argument("--expect-overflow", action="store_true")
    parser.add_argument("--runtime-only", action="store_true",
                        help="test normal kernels without opt-in boot self-tests")
    args = parser.parse_args()
    repo = args.repo.resolve()
    driver = repo / ("tests/realtime/run_vm.py" if args.arch == "aarch64"
                     else "tests/openbsd-security/run_vm.py")
    spec = importlib.util.spec_from_file_location("stack_guard_vm", driver)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"STACK-GUARD GUEST: PASS"
    runner.FAIL_MARKERS = (b"STACK-GUARD GUEST: FAIL", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = (
        b"STACK-GUARD PASS actual read/write faults, stack exhaustion",
        b"STACK-GUARD PASS 32 unpublished thread allocation/rollback/retirement cycles",
    )
    if args.runtime_only:
        runner.FEATURE_MARKERS = ()
    if args.expect_overflow:
        runner.PASS_MARKER = (b"STACK-GUARD FATAL emergency-stack exhaustion" if args.arch == "aarch64"
                              else b"STACK-GUARD FATAL kernel-stack exhaustion")
        runner.FEATURE_MARKERS = (b"STACK-GUARD state sp=0x",)
        runner.FAIL_MARKERS = (b"STACK-GUARD GUEST: PASS", b"STACK-GUARD GUEST: FAIL")
    with tempfile.TemporaryDirectory(prefix="vinix-stack-guards-") as directory:
        work = Path(directory)
        if args.arch == "aarch64":
            sysroot = repo / "build-aarch64-userland/sysroot"
            command = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl",
                f"--sysroot={sysroot}", "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                str(ROOT / "tests/kernel-stack-guards/guest.c"), f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
                "-o", str(work / "init")]
        else:
            command = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"), "-static", "-O2",
                "-Wall", "-Wextra", "-Werror", str(ROOT / "tests/kernel-stack-guards/guest.c"),
                "-o", str(work / "init")]
        subprocess.run(command, check=True)
        for name in ("root", "sbin", "proc", "sys", "dev"):
            (work / "rootfs" / name).mkdir(parents=True)
        shutil.copy2(work / "init", work / "rootfs/sbin/init")
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "initramfs.tar"),
            "-C", str(work / "rootfs"), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
        if args.arch == "aarch64":
            os.environ["VINIX_KERNEL_DIR"] = str(args.kernel.resolve())
            os.environ["VINIX_QEMU_RT_NO_BUILD"] = "1"
            return runner.run_vm(repo, work / "init", work / "initramfs.tar", work / "vm", timeout)
        environment = {**os.environ,
            "VINIX_AMD64_KERNEL": str(args.kernel.resolve()),
            "VINIX_AMD64_INITRAMFS": str(work / "initramfs.tar"),
            "VINIX_AMD64_ISO": str(work / "test.iso"),
            "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso"),
        }
        subprocess.run([str(repo / "build-support/build-amd64-iso.sh")], env=environment, check=True)
        qemu = Path(shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64")))
        firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        runner.REPORT_MARKER = b""
        sys.argv = [str(driver), "--arch", "amd64", "--iso", str(work / "test.iso"),
            "--qemu", str(qemu), "--firmware", firmware, "--capture", str(work / "unused.pcap"),
            "--timeout", str(timeout)]
        return runner.main()

if __name__ == "__main__":
    raise SystemExit(main())
