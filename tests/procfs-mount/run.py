#!/usr/bin/env python3
"""Compile the procfs-mount ABI test and boot it through an isolated existing VM driver."""
from pathlib import Path
import argparse
import contextlib
import importlib.util
import os
import runpy
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (b"PROC MOUNT PASS: self mounts fail without damaging proc paths or mountinfo",
            b"PROC MOUNT PASS: independent aliases and remounts remain usable",
            b"PROC MOUNT PASS: inactive view reuse rejects self edges before retarget, concurrently",
            b"PROC MOUNT PASS: fresh PID namespace views remain mountable and reject cycles",
            b"PROC MOUNT PASS: cached roots cannot cover their own descendants")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    parser.add_argument("--case", choices=("full", "reuse"), default="full")
    parser.add_argument("--work", type=Path)
    parser.add_argument("--prebuilt-init", type=Path)
    arguments = parser.parse_args()
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    runner_path = runner_root / ("tests/realtime/run_vm.py" if arguments.arch == "aarch64"
                                 else "tests/openbsd-security/run_vm.py")
    spec = importlib.util.spec_from_file_location("procfs-mount_vm", runner_path)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"PROC MOUNT GUEST: PASS"
    runner.FAIL_MARKERS = (b"PROC MOUNT FAIL", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = (FEATURES[2],) if arguments.case == "reuse" else FEATURES
    workspace = (contextlib.nullcontext(str(arguments.work.resolve())) if arguments.work
                 else tempfile.TemporaryDirectory(prefix="vinix-procfs-mount-vm-"))
    with workspace as directory:
        work = Path(directory)
        if arguments.work:
            work.mkdir(parents=True, exist_ok=False)
        if arguments.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", runner_root / "build-aarch64-userland/sysroot"))
            compiler = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}"]
            gcc_root = runner_root / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl"
            if gcc_root.exists(): compiler.append(f"--gcc-install-dir={sorted(gcc_root.iterdir())[-1]}")
            linker = [f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
        else:
            compiler = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
            linker = []
        if arguments.prebuilt_init:
            shutil.copy2(arguments.prebuilt_init, work / "init")
        else:
            generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
            defines = ("nofloat",) + (("proc_mount_reuse_only",) if arguments.case == "reuse" else ())
            generate(ROOT / "tests/procfs-mount/mountfixture", work / "fixture.c",
                     "arm64" if arguments.arch == "aarch64" else "amd64", defines)
            flags = ["-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                     "-D_GNU_SOURCE", "-fno-strict-aliasing", "-Wno-unused-function", "-Wno-unused-parameter",
                     "-I", str(ROOT / "tests/procfs-mount/mountfixture")]
            subprocess.run(compiler + flags + ["-c", str(work / "fixture.c"), "-o", str(work / "fixture.o")], check=True)
            subprocess.run(compiler + ["-static", str(work / "fixture.o")] + linker + ["-o", str(work / "init")], check=True)
        for name in ("root", "sbin", "proc", "sys", "dev", "tmp"):
            (work / "rootfs" / name).mkdir(parents=True)
        if arguments.arch == "amd64":
            shutil.copy2(work / "init", work / "rootfs/sbin/init")
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "initramfs.tar"),
            "-C", str(work / "rootfs"), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
        if arguments.arch == "aarch64":
            return runner.run_vm(runner_root, work / "init", work / "initramfs.tar", work / "vm", timeout)
        environment = {**os.environ,
            "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(ROOT / "build-amd64-kernel/bin/vinix")),
            "VINIX_AMD64_INITRAMFS": str(work / "initramfs.tar"),
            "VINIX_AMD64_ISO": str(work / "test.iso"),
            "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso"),
        }
        limine = Path(os.environ.get("VINIX_LIMINE_CACHE", runner_root / "build-amd64-iso/limine")).resolve()
        if "VINIX_LIMINE_CACHE" in os.environ: limine.mkdir(parents=True, exist_ok=True)
        if limine.is_dir():
            (work / "iso").mkdir()
            (work / "iso/limine").symlink_to(limine, target_is_directory=True)
        subprocess.run([str(runner_root / "build-support/build-amd64-iso.sh")], env=environment, check=True)
        qemu = Path(shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64")))
        firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        runner.REPORT_MARKER = b""  # This test does not provoke pledge violations.
        sys.argv = [str(runner_path), "--arch", "amd64", "--iso", str(work / "test.iso"),
            "--qemu", str(qemu), "--firmware", firmware, "--capture", str(work / "unused.pcap"),
            "--timeout", str(timeout)]
        return runner.main()


if __name__ == "__main__":
    raise SystemExit(main())
