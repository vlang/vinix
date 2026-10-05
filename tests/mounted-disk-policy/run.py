#!/usr/bin/env python3
"""Verify mounted-disk policy on a disposable, physically backed EXT2 guest root."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import struct
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    args = parser.parse_args()
    runner = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    helper = load("securedisk_powercut", runner / "tests/disk-no-sync/run_vm.py")
    mapped = load("securedisk_amd64", ROOT / "tests/mapped-writeback/run.py")
    helper.START_MARKER = b"SECUREDISK START"
    helper.DONE_RE = re.compile(rb"SECUREDISK DONE (\w+) ino=(\d+)\r*\n")
    helper.FAIL_MARKERS = (b"FAIL END", b"FATAL EXCEPTION", b"KERNEL PANIC")
    tool = helper.find_debugfs()
    if not tool:
        raise RuntimeError("e2fsprogs is required")
    timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
    with tempfile.TemporaryDirectory(prefix="vinix-securedisk-") as directory:
        work = Path(directory)
        if args.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            cc = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                  f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
        else:
            cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        subprocess.run(cc + ["-static", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-stack-protector", "-pthread",
            str(ROOT / "tests/mounted-disk-policy/guest.c"), "-o", str(work / "init")], check=True)
        archive, disk = work / "initramfs.tar", work / "root.ext2"
        spare = work / "spare.raw"
        with spare.open("wb") as output:
            output.truncate(16 * 1024 * 1024)
        mbr = bytearray(512)
        struct.pack_into("<B3sB3sII", mbr, 446, 0, b"\0" * 3, 0x83, b"\0" * 3, 2048, 16384)
        mbr[510:512] = b"\x55\xaa"
        with spare.open("r+b") as output:
            output.write(mbr)
        helper.initramfs(archive, "pass")
        environment = {**os.environ, "VINIX_INITRAMFS": str(archive), "VINIX_BOOT_DISK": str(work / "boot.img"),
            "VINIX_EFIVARS": str(work / "efivars.fd"), "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
            "VINIX_QEMU_PERSIST_DISK": str(disk), "VINIX_QEMU_PERSIST_SIZE_MB": "64",
            "VINIX_KEEP_TEMP_BOOT_DISK": "1", "VINIX_QEMU_PACKAGE_STORE_PORT": helper.available_port()}
        environment.pop("VINIX_QEMU_PERSIST", None)
        environment.pop("VINIX_QEMU_PERSIST_SEED", None)
        if platform.system() != "Darwin":
            environment.setdefault("USE_TCG", "1")
        if args.arch == "aarch64":
            environment["VINIX_QEMU_EXTRA"] = f"-drive if=none,format=raw,file={spare},id=policy-spare -device virtio-blk-device,drive=policy-spare"
            passed, _ = helper.boot(runner, SimpleNamespace(init=work / "init", timeout=timeout), environment,
                os.environ.get("VINIX_QEMU_RT_NO_BUILD") != "1", "pass")
        else:
            with tarfile.open(archive, "a", format=tarfile.USTAR_FORMAT) as f:
                f.add(work / "init", "sbin/init")
            isoenv = {**environment, "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(ROOT / "kernel/bin/vinix")),
                "VINIX_AMD64_INITRAMFS": str(archive), "VINIX_AMD64_ISO": str(work / "test.iso"),
                "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso")}
            subprocess.run([str(runner / "build-support/build-amd64-iso.sh")], env=isoenv, check=True,
                           stdout=subprocess.DEVNULL)
            seed = work / "seed"
            for name in ("root", "dev", "proc", "tmp", "run"):
                (seed / name).mkdir(parents=True, exist_ok=True)
            with tarfile.open(archive) as f:
                f.extractall(seed)
            (seed / ".vinix-image-id").write_text(hashlib.sha256(archive.read_bytes()).hexdigest()[:16] + "\n")
            with disk.open("wb") as f:
                f.truncate(64 * 1024 * 1024)
            subprocess.run([str(Path(tool).with_name("mke2fs")), "-q", "-F", "-t", "ext2", "-b", "4096", "-I", "128",
                "-O", "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                "-d", str(seed), str(disk)], check=True)
            # EXT2 stays on the whole disk; a real MBR partition resource
            # aliases the same extent to exercise physical parent identity.
            root_mbr = bytearray(512)
            struct.pack_into("<B3sB3sII", root_mbr, 446, 0, b"\0" * 3, 0x83, b"\0" * 3, 0, 64 * 1024 * 1024 // 512)
            root_mbr[510:512] = b"\x55\xaa"
            with disk.open("r+b") as output:
                output.write(root_mbr)
            qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
            firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
            command = [qemu, "-machine", "q35,smm=off", "-accel", os.environ.get("VINIX_QEMU_ACCEL", "tcg"),
                "-cpu", "max", "-m", "1024", "-smp", "2", "-drive",
                f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-cdrom", str(work / "test.iso"),
                "-drive", f"if=ide,format=raw,file={disk},cache=writeback", "-drive",
                f"if=none,format=raw,file={spare},id=policy-spare,cache=writeback", "-device",
                "ide-hd,drive=policy-spare,bus=ide.5", "-display", "none", "-monitor", "none",
                "-serial", "stdio", "-no-reboot"]
            passed = mapped.amd64_boot(command, environment, helper, timeout, "pass")
        if not passed:
            return 1
        check = subprocess.run([str(Path(tool).with_name("e2fsck")), "-f", "-n", str(disk)], capture_output=True, text=True)
        if check.returncode:
            raise RuntimeError(f"EXT2 check after guest:\n{check.stdout}\n{check.stderr}")
        payload = work / "writeback.bin"
        guest_path = "/policy-writeback" if args.arch == "aarch64" else "/root/policy-writeback"
        subprocess.run([str(tool), "-R", f"dump {guest_path} {payload}", str(disk)],
                       check=True, capture_output=True, text=True)
        if not payload.exists() or payload.read_bytes() != bytes([0x59]) * (128 * 512):
            raise RuntimeError("filesystem writeback did not persist its complete payload")
        print(f"PASS {args.arch}: mounted-disk capabilities, denial retention, persisted writeback and EXT2 consistency", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
