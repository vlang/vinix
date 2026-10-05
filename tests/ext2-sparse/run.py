#!/usr/bin/env python3
"""Exercise large sparse EXT2 files across three hard-stop/restart cycles."""
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
    parser.add_argument("--blocks", default="1024,4096")
    args = parser.parse_args()
    blocks = [int(x) for x in args.blocks.split(",")]
    if any(x not in (1024, 4096) for x in blocks): parser.error("use 1024 or 4096 byte blocks")
    runner = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    helper = load("powercut", runner / "tests/disk-no-sync/run_vm.py")
    mapped = load("mapped", ROOT / "tests/mapped-writeback/run.py")
    helper.START_MARKER = b"EXT2 SPARSE START"
    helper.DONE_RE = re.compile(rb"EXT2 SPARSE DONE (\w+) ino=(\d+)\r*\n")
    helper.FAIL_MARKERS = (b"FAIL END", b"FATAL EXCEPTION", b"KERNEL PANIC")
    debugfs = helper.find_debugfs()
    if not debugfs: raise RuntimeError("e2fsprogs debugfs is required")
    mke2fs = str(Path(debugfs).with_name("mke2fs"))
    e2fsck = str(Path(debugfs).with_name("e2fsck"))
    timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
    with tempfile.TemporaryDirectory(prefix="vinix-ext2-sparse-") as directory:
        work = Path(directory)
        if args.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            cc = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                  f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
        else: cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        subprocess.run(cc + ["-static", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-stack-protector",
            str(ROOT / "tests/ext2-sparse/guest.c"), "-o", str(work / "init")], check=True)
        archive = work / "initramfs.tar"
        helper.initramfs(archive, "run")
        environment = {**os.environ, "VINIX_INITRAMFS": str(archive), "VINIX_BOOT_DISK": str(work / "boot.img"),
            "VINIX_EFIVARS": str(work / "efivars.fd"), "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
            "VINIX_KEEP_TEMP_BOOT_DISK": "1", "VINIX_QEMU_PACKAGE_STORE_PORT": helper.available_port()}
        environment.pop("VINIX_QEMU_PERSIST", None)
        environment.pop("VINIX_QEMU_PERSIST_SEED", None)
        if platform.system() != "Darwin": environment.setdefault("USE_TCG", "1")
        command = None
        seed = work / "seed"
        seed.mkdir()
        if args.arch == "amd64":
            with tarfile.open(archive, "a", format=tarfile.USTAR_FORMAT) as f: f.add(work / "init", "sbin/init")
            isoenv = {**environment, "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(ROOT / "kernel/bin/vinix")),
                "VINIX_AMD64_INITRAMFS": str(archive), "VINIX_AMD64_ISO": str(work / "test.iso"),
                "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso")}
            subprocess.run([str(runner / "build-support/build-amd64-iso.sh")], env=isoenv, check=True, stdout=subprocess.DEVNULL)
            for name in ("dev", "proc", "tmp", "run", "root"): (seed / name).mkdir(exist_ok=True)
            with tarfile.open(archive) as f: f.extractall(seed)
            (seed / ".vinix-image-id").write_text(hashlib.sha256(archive.read_bytes()).hexdigest()[:16] + "\n")
            qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
            firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
            command = [qemu, "-machine", "q35,smm=off", "-accel", os.environ.get("VINIX_QEMU_ACCEL", "tcg"),
                "-cpu", "max", "-m", "1024", "-smp", "2", "-drive",
                f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-cdrom", str(work / "test.iso"),
                "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot"]
        for block_size in blocks:
            disk = work / f"root-{block_size}.ext2"
            with disk.open("wb") as f: f.truncate(64 * 1024 * 1024)
            subprocess.run([mke2fs, "-q", "-F", "-t", "ext2", "-b", str(block_size), "-I", "128", "-O",
                "filetype,sparse_super,^large_file,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                "-d", str(seed), str(disk)], check=True)
            environment["VINIX_QEMU_PERSIST_DISK"] = str(disk)
            for step in ("create", "shrink", "cleanup"):
                print(f"==> {args.arch} EXT2 block={block_size} {step}", flush=True)
                if command is None:
                    finished, _ = helper.boot(runner, SimpleNamespace(init=work / "init", timeout=timeout), environment,
                        os.environ.get("VINIX_QEMU_RT_NO_BUILD") != "1", step)
                else:
                    finished = mapped.amd64_boot(command + ["-drive", f"if=ide,format=raw,file={disk},cache=writeback"],
                        environment, helper, timeout, step)
                if not finished: return 1
                path = "/root/sparse-persist" if args.arch == "amd64" else "/sparse-persist"
                if step == "create":
                    text = helper.debugfs(debugfs, disk, f"stat {path}")
                    p = block_size // 4
                    capacity = (12 + p + p*p + p*p*p) * block_size
                    if f"Size: {capacity}" not in text: raise RuntimeError(f"wrong persisted high size: {text}")
                    blocks_match = re.search(r"Blockcount:\s+(\d+)", text)
                    if not blocks_match or int(blocks_match.group(1)) >= 64 * (block_size // 512):
                        raise RuntimeError(f"file is not sparse: {text}")
                    header = helper.debugfs(debugfs, disk, "stats")
                    if "large_file" not in header: raise RuntimeError("LARGE_FILE feature did not persist")
                check = subprocess.run([e2fsck, "-f", "-n", str(disk)], capture_output=True, text=True)
                if check.returncode != 0:
                    raise RuntimeError(f"EXT2 consistency after {step}:\n{check.stdout}\n{check.stderr}")
                print(f"PASS {args.arch} block={block_size} {step}: actual disk and e2fsck after power cut", flush=True)
    return 0


if __name__ == "__main__": raise SystemExit(main())
