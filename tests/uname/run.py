#!/usr/bin/env python3
"""Check uname output and options in an isolated AArch64 QEMU guest."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sysroot", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("uname_vm", ROOT / "tests/kernel-gaps/run.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    with tempfile.TemporaryDirectory(prefix="vinix-uname-") as directory:
        state = Path(directory).resolve()
        rootfs = state / "rootfs"
        for name in ("bin", "lib", "sbin", "proc", "sys", "dev", "tmp", "root"):
            (rootfs / name).mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.sysroot / "bin/busybox", rootfs / "bin/busybox")
        shutil.copy2(args.sysroot / "lib/ld-musl-aarch64.so.1", rootfs / "lib/ld-musl-aarch64.so.1")
        (rootfs / "bin/sh").symlink_to("busybox")
        # Exercise replacement of Alpine's absolute symlink without touching BusyBox.
        (rootfs / "bin/uname").symlink_to("/bin/busybox")
        original_busybox = (rootfs / "bin/busybox").read_bytes()
        subprocess.run([str(ROOT / "build-support/stage-uname.sh"), str(rootfs)], check=True)
        assert (rootfs / "bin/busybox").read_bytes() == original_busybox
        assert (rootfs / "usr/bin/uname").resolve() == rootfs / "bin/uname"
        shutil.copy2(Path(__file__).with_name("guest-init.sh"), rootfs / "sbin/init")
        with tarfile.open(state / "initramfs.tar", "w", format=tarfile.USTAR_FORMAT) as archive:
            archive.add(rootfs, arcname=".")
        environment = {**os.environ, "VINIX_INITRAMFS": str(state / "initramfs.tar"),
                       "VINIX_BOOT_DISK": str(state / "boot.img"),
                       "VINIX_BOOT_DISK_SIZE_MB": "64", "VINIX_EFIVARS": str(state / "efivars.fd"),
                       "VINIX_QEMU_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
                       "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_NETWORK": "0",
                       "VINIX_QEMU_CLIPBOARD": "0", "VINIX_QEMU_AUDIO": "off", "VINIX_PRUNE_BUILD": "0",
                       "VINIX_QEMU_EXTRA": f"-qmp unix:{state / 'qmp.sock'},server=on,wait=off"}
        return runner.boot([str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--mem=512"],
                           environment, state, ["UNAME PASS"],
                           ["UNAME FAIL", "KERNEL PANIC", "FATAL EXCEPTION"], args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
