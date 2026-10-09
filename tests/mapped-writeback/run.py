#!/usr/bin/env python3
"""Kill QEMU with mappings live, then inspect its actual EXT2 image with debugfs."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import platform
import pty
import re
import select
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
STEPS = ("sync", "syncfs", "background", "churn", "private", "pageout", "pressure")


def boot_guest(command, environment, helper, timeout, step):
    pid, master = pty.fork()
    if pid == 0:
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == pid: break
            ready, _, _ = select.select([master], [], [], 0.25)
            if not ready: continue
            try: data = os.read(master, 65536)
            except OSError: break
            if not data: break
            transcript += data
            sys.stdout.buffer.write(data)
            sys.stdout.flush()
            if helper.DONE_RE.search(transcript) or (any(x in transcript for x in helper.FAIL_MARKERS) and transcript.endswith(b"\n")): break
    finally:
        helper.stop_child(pid, master)
        os.close(master)
    done = helper.DONE_RE.search(transcript)
    if done is None: print(f"ERROR: {step} stopped without a completion marker (timeout {timeout}s)", flush=True)
    return (done is not None and done.group(1).decode() == step
            and helper.START_MARKER in transcript
            and not any(x in transcript for x in helper.FAIL_MARKERS))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    parser.add_argument("--steps", default=",".join(step for step in STEPS if step != "pressure"))
    parser.add_argument("--memory", type=int, default=1024, help="guest RAM in MiB; use 256 for pressure")
    args = parser.parse_args()
    steps = args.steps.split(",")
    if any(step not in STEPS for step in steps): parser.error("unknown step")
    if args.memory < 128 or ("pressure" in steps and args.memory > 512): parser.error("pressure needs 128–512 MiB")
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    spec = importlib.util.spec_from_file_location("powercut", runner_root / "tests/disk-no-sync/run_vm.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    helper.START_MARKER = b"MAPPED WRITEBACK START"
    helper.DONE_RE = re.compile(rb"MAPPED WRITEBACK DONE (\w+) ino=(\d+)\r*\n")
    helper.FAIL_MARKERS = (b"FAIL END", b"FATAL EXCEPTION", b"KERNEL PANIC")
    tool = helper.find_debugfs()
    if tool is None: raise RuntimeError("debugfs from e2fsprogs is required")
    timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
    with tempfile.TemporaryDirectory(prefix="vinix-mapped-writeback-") as directory:
        work = Path(directory)
        if args.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            cc = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl", f"--sysroot={sysroot}",
                  f"-L{sysroot / 'lib'}", "-fuse-ld=lld"]
        else: cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
        subprocess.run(cc + ["-static", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-stack-protector",
            str(ROOT / "tests/mapped-writeback/guest.c"), f"-DVINIX_TEST_MEMORY_MIB={args.memory}", "-pthread", "-o", str(work / "init")], check=True)
        disk = work / "root.ext2"
        archive = work / "initramfs.tar"
        preseed = work / "preseed"
        (preseed / "many").mkdir(parents=True)
        for i in range(1200): (preseed / "many" / f"f{i:04}").touch()
        seed_archive = work / "seed.tar"
        with tarfile.open(seed_archive, "w", format=tarfile.USTAR_FORMAT) as f:
            f.add(preseed / "many", "many")
        environment = {**os.environ, "VINIX_INITRAMFS": str(archive), "VINIX_BOOT_DISK": str(work / "boot.img"),
            "VINIX_EFIVARS": str(work / "efivars.fd"), "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
            "VINIX_QEMU_PERSIST_DISK": str(disk), "VINIX_QEMU_PERSIST_SIZE_MB": "64",
            "VINIX_KEEP_TEMP_BOOT_DISK": "1", "VINIX_QEMU_PACKAGE_STORE_PORT": helper.available_port()}
        environment["VINIX_QEMU_PERSIST_SEED"] = str(seed_archive)
        environment.pop("VINIX_QEMU_PERSIST", None)
        if platform.system() != "Darwin": environment.setdefault("USE_TCG", "1")
        for step in steps:
            helper.initramfs(archive, step)
            if args.arch == "aarch64":
                command = [str(runner_root / "scripts/run-aarch64.sh"), "--serial", f"--mem={args.memory}",
                           f"--guest-init={work / 'init'}"]
                if os.environ.get("VINIX_QEMU_RT_NO_BUILD") == "1": command.insert(1, "--no-build")
                finished = boot_guest(command, environment, helper, timeout, step)
            else:
                with tarfile.open(archive, "a", format=tarfile.USTAR_FORMAT) as f: f.add(work / "init", "sbin/init")
                isoenv = {**environment, "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(ROOT / "kernel/bin/vinix")),
                    "VINIX_AMD64_INITRAMFS": str(archive), "VINIX_AMD64_ISO": str(work / "test.iso"),
                    "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso")}
                subprocess.run([str(runner_root / "build-support/build-amd64-iso.sh")], env=isoenv, check=True, stdout=subprocess.DEVNULL)
                # AMD64 discovers EXT2 through the disk-root boot path. Its
                # ordinary mount(2) registry has no generic 'ext2' template.
                # Seed a bootable root matching the exact ISO payload identity.
                seed = work / "disk-seed"
                seed.mkdir(exist_ok=True)
                for name in ("dev", "proc", "tmp", "run"):
                    (seed / name).mkdir(exist_ok=True)
                shutil.copytree(preseed / "many", seed / "root/many", dirs_exist_ok=True)
                with tarfile.open(archive) as f: f.extractall(seed)
                (seed / ".vinix-image-id").write_text(hashlib.sha256(archive.read_bytes()).hexdigest()[:16] + "\n")
                if disk.exists(): disk.unlink()
                with disk.open("wb") as f: f.truncate(64 * 1024 * 1024)
                mke2fs = str(Path(tool).with_name("mke2fs"))
                subprocess.run([mke2fs, "-q", "-F", "-t", "ext2", "-b", "4096", "-I", "128", "-O",
                    "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                    "-d", str(seed), str(disk)], check=True)
                qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
                firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
                command = [qemu, "-machine", "q35,smm=off", "-accel", os.environ.get("VINIX_QEMU_ACCEL", "tcg"),
                    "-cpu", "max", "-m", str(args.memory), "-smp", "2", "-drive",
                    f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-cdrom", str(work / "test.iso"),
                    "-drive", f"if=ide,format=raw,file={disk},cache=writeback", "-display", "none", "-monitor", "none",
                    "-serial", "stdio", "-no-reboot"]
                if os.environ.get("VINIX_TEST_QMP"):
                    command += ["-qmp", f"unix:{os.environ['VINIX_TEST_QMP']},server=on,wait=off"]
                finished = boot_guest(command, environment, helper, timeout, step)
            if not finished: return 1
            if step != "churn":
                observed = work / "observed.bin"
                file_path = f"{'/root' if args.arch == 'amd64' else ''}/mapped-{step}"
                subprocess.run([tool, "-R", f"dump {file_path} {observed}", str(disk)], check=True, capture_output=True)
                size = 8 * 1024 * 1024 if step in ("pressure", "private") else 65536
                expected = bytearray((i * 37 + 11) & 255 for i in range(size))
                expected[17], expected[65536 - 9] = 0x82, 0x93
                if observed.read_bytes() != expected: raise RuntimeError(f"{step}: live mapping was not on disk at power cut")
            print(f"PASS {args.arch} {step}: verified after power cut", flush=True)
    return 0


if __name__ == "__main__": raise SystemExit(main())
