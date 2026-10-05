#!/usr/bin/env python3
"""Run real iOS-targeted Mach-O instructions in an isolated Vinix ARM64 VM."""
from pathlib import Path
import argparse
import importlib.util
import os
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (
    b"iOS PASS: Mach-O arithmetic and libSystem imports",
    b"iOS PASS: return status and unsupported imports",
    b"iOS PASS: universal executable selects ARM64",
    b"iOS PASS: ARM64e and malformed images rejected",
    b"iOS PASS: UIKit Mach-O 27 button/action cases",
    b"iOS PASS: UIKit resize, keyboard, 1000 updates and ARC teardown",
)


def prepare_images(fixtures: Path, destination: Path) -> None:
    original = (fixtures / "calculator").read_bytes()
    arm64e = bytearray(original)
    struct.pack_into("<I", arm64e, 8, 2)
    (destination / "calculator-arm64e").write_bytes(arm64e)
    (destination / "truncated").write_bytes(original[:31])
    second = (4096 + len(original) + 4095) & ~4095
    fat = bytearray(second + len(original))
    struct.pack_into(">II", fat, 0, 0xCAFEBABE, 2)
    struct.pack_into(">IIIII", fat, 8, 0x100000C, 2, 4096, len(arm64e), 12)
    struct.pack_into(">IIIII", fat, 28, 0x100000C, 0, second, len(original), 12)
    fat[4096:4096 + len(arm64e)] = arm64e
    fat[second:] = original
    (destination / "calculator-fat").write_bytes(fat)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="reuse build/ios/staging/usr/bin/run-ios")
    parser.add_argument("--timeout", type=int, default=180)
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("timeout must be positive")
    build = Path(os.environ.get("VINIX_IOS_BUILD_DIR", ROOT / "build/ios"))
    if not arguments.no_build:
        subprocess.run(["bash", str(ROOT / "build-ios-aarch64.sh")], check=True)
    subprocess.run(["sh", str(ROOT / "tests/ios/build-fixture.sh"), str(build / "fixtures")], check=True)
    subprocess.run(["bash", str(ROOT / "examples/ios-calculator/build.sh")],
        env={**os.environ, "VINIX_IOS_CALCULATOR_BUILD_DIR": str(build / "objc")}, check=True)
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    spec = importlib.util.spec_from_file_location("ios_vm", runner_root / "tests/realtime/run_vm.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"VINIX iOS GUEST: PASS"
    runner.FAIL_MARKERS = (b"iOS FAIL:", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = FEATURES
    with tempfile.TemporaryDirectory(prefix="vinix-ios-vm-") as directory:
        work = Path(directory)
        rootfs = work / "rootfs"
        for name in ("root", "sbin", "proc", "sys", "dev", "tmp", "opt/ios"):
            (rootfs / name).mkdir(parents=True)
        destination = rootfs / "opt/ios"
        shutil.copy2(build / "staging/usr/bin/run-ios", destination / "run-ios")
        for name in ("calculator", "unsupported"):
            shutil.copy2(build / "fixtures" / name, destination / name)
        shutil.copy2(build / "objc/Calculator.app/Calculator", destination / "UIKitCalculator")
        prepare_images(build / "fixtures", destination)
        # Same small static musl sysroot used by the existing syscall tests.
        sysroot = Path(os.environ.get("VINIX_IOS_TEST_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
        subprocess.run([
            os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
            "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
            str(ROOT / "tests/ios/guest.c"), str(ROOT / "tests/ios/uikit-guest.c"), f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
            "-o", str(work / "init"),
        ], check=True)
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "initramfs.tar"),
            "-C", str(rootfs), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        # No kernel changes are needed. Reuse the existing kernel, and keep
        # every boot disk, package store and persistent volume disposable.
        os.environ["VINIX_QEMU_RT_NO_BUILD"] = "1"
        os.environ["VINIX_QEMU_HOST_SOURCE"] = "0"
        os.environ["VINIX_QEMU_CLIPBOARD"] = "0"
        os.environ["VINIX_QEMU_AUDIO"] = "off"
        os.environ["VINIX_QEMU_NETWORK"] = "0"
        return runner.run_vm(runner_root, work / "init", work / "initramfs.tar", work / "vm", arguments.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
