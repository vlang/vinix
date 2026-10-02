#!/usr/bin/env python3
"""Measure repeated exec cohorts with a real grace period and live allocation sites."""
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
    parser.add_argument("--mode", choices=("exec", "slabinfo", "waits", "directories", "pipes", "sampling", "select"), default="exec")
    parser.add_argument("--runner-root", type=Path,
                        default=Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT)))
    parser.add_argument("--kernel", type=Path,
                        default=Path(os.environ.get("VINIX_KERNEL_DIR", ROOT / "kernel")))
    parser.add_argument("--image", type=Path)
    parser.add_argument("--module-iso", type=Path)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    repo = args.runner_root.resolve()
    image = (args.image or repo / "build-support/init-aarch64/initramfs-desktop.tar").resolve()
    if args.mode == "exec" and args.arch != "aarch64":
        parser.error("exec cohorts use the prepared ARM desktop image")
    if args.mode == "directories" and args.arch != "aarch64":
        parser.error("directory cohorts require the ARM runner's persistent ext2 /root")
    if args.mode == "exec" and (not image.is_file() or args.module_iso is None
                                or not args.module_iso.is_file()):
        parser.error("exec cohorts require a populated desktop image and its module ISO")
    driver = ROOT / ("tests/realtime/run_vm.py" if args.arch == "aarch64"
                     else "tests/openbsd-security/run_vm.py")
    spec = importlib.util.spec_from_file_location("process_churn_vm", driver)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.GUEST_MEMORY_MB = 12288 if args.mode == "exec" else 2048
    runner.PASS_MARKER = b"PROCESS CHURN: DONE failures=0"
    runner.FAIL_MARKERS = (b"PROCESS CHURN: FAIL", b"FATAL EXCEPTION", b"KERNEL PANIC")
    names = {"exec": ("true", "sleep", "curl", "awk"), "slabinfo": ("slabinfo",),
             "waits": ("idle_control", "nanosleep", "clock_nanosleep", "fork_reap"),
             "directories": ("mkdir_tmpfs", "mkdir_ext2"), "pipes": ("pipe",),
             "sampling": ("sampling",), "select": ("select_ready", "pselect_ready")}[args.mode]
    count = 200 if args.mode == "directories" else 300
    runner.FEATURE_MARKERS = tuple(f"CHURN MEASURE program={name} cohort=3 runs={count}".encode()
                                   for name in names)
    os.environ.update({
        "VINIX_KERNEL_DIR": str(args.kernel.resolve()), "VINIX_QEMU_RT_NO_BUILD": "1",
        "VINIX_QEMU_BASE_ARCHIVE": "", "VINIX_QEMU_MODULE_MANIFEST": "",
        "VINIX_QEMU_EXTRA_MODULES": "", "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_QEMU_AUDIO": "off",
    })
    if args.mode == "exec":
        os.environ["VINIX_QEMU_MODULE_ISO"] = str(args.module_iso.resolve())
        os.environ["VINIX_INITRAMFS_COMPRESSED"] = "0"
    else:
        os.environ.pop("VINIX_QEMU_MODULE_ISO", None)
        os.environ.pop("VINIX_INITRAMFS_COMPRESSED", None)
    sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", repo / "build-aarch64-userland/sysroot"))
    with tempfile.TemporaryDirectory(prefix="vinix-process-churn-") as directory:
        work = Path(directory)
        command = (["clang", "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                    f"-L{sysroot / 'lib'}", "-fuse-ld=lld"] if args.arch == "aarch64"
                   else [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")])
        if args.mode != "exec": command.append(f"-DCHURN_{args.mode.upper()}_ONLY")
        subprocess.run(command + ["-static", "-O2", "-Wall", "-Wextra", "-Werror",
            "-fno-stack-protector", str(ROOT / "tests/process-churn/guest.c"),
            "-o", str(work / "init")], check=True)
        # The module carries the ordinary desktop programs and libraries. Only
        # the measured kernel and replacement PID 1 come from this worktree.
        if args.mode != "exec":
            for name in ("root", "sbin", "proc", "dev", "tmp"):
                (work / "rootfs" / name).mkdir(parents=True)
            if args.arch == "amd64": shutil.copy2(work / "init", work / "rootfs/sbin/init")
            image = work / "initramfs.tar"
            subprocess.run(["tar", "--format=ustar", "-cf", str(image), "-C",
                str(work / "rootfs"), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        if args.arch == "aarch64":
            return runner.run_vm(repo, work / "init", image, work / "vm", args.timeout)
        kernel = args.kernel.resolve()
        if kernel.is_dir(): kernel /= "bin/vinix"
        environment = {**os.environ, "VINIX_AMD64_KERNEL": str(kernel),
            "VINIX_AMD64_INITRAMFS": str(image), "VINIX_AMD64_ISO": str(work / "test.iso"),
            "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso")}
        subprocess.run([str(repo / "build-support/build-amd64-iso.sh")], env=environment, check=True)
        qemu = Path(shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64")))
        firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        runner.REPORT_MARKER = b""
        sys.argv = [str(driver), "--arch", "amd64", "--iso", str(work / "test.iso"),
            "--qemu", str(qemu), "--firmware", firmware, "--capture", str(work / "unused.pcap"),
            "--timeout", str(args.timeout)]
        return runner.main()


if __name__ == "__main__":
    raise SystemExit(main())
