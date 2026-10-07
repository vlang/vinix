#!/usr/bin/env python3
"""Boot one machine process and enforce the reboot-persistence result.

Unlike the core regression, this is a single QEMU process: the guest resets
itself with reboot(2), so the kernel's shutdown path -- not a second launch --
is what has to get the pending write to the disk.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import platform
import pty
import runpy
import select
import signal
import shutil
import socket
import subprocess
import sys
import tarfile
import time


START_MARKER = b"VINIX REBOOT PERSISTENCE: START"
WROTE_MARKER = b"VINIX REBOOT PERSISTENCE: WROTE MARKER, REBOOTING"
SYNC_MARKER = b"VINIX REBOOT PERSISTENCE: SYNCING"
PASS_MARKER = b"VINIX REBOOT PERSISTENCE: PASS"
FAIL_MARKERS = (
    b"VINIX REBOOT PERSISTENCE: FAIL",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)


def available_port() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return str(listener.getsockname()[1])


def gone(pid: int, master: int, seconds: float) -> bool:
    # pty.fork made scripts/run-aarch64.sh the leader of a process group of its own,
    # and QEMU is in it. The script exiting is not enough: a QEMU it leaves
    # behind still runs the guest and holds the disk images. The terminal is
    # read meanwhile, as nothing can finish exiting with output to it unread.
    deadline = time.monotonic() + seconds
    while True:
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass
        try:
            os.killpg(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            # What is left of the group is exiting.
            pass
        if time.monotonic() >= deadline:
            return False
        readable, _, _ = select.select([master], [], [], 0.05)
        if readable:
            try:
                os.read(master, 65536)
            except OSError:
                time.sleep(0.05)


def stop_child(pid: int, master: int) -> None:
    # Ctrl-A x is QEMU's own quit, and the only stop that lets it release the
    # disk images cleanly. Signals are the fallback for a QEMU that is wedged.
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass
    if gone(pid, master, 5):
        return
    for signal_number in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, signal_number)
        except ProcessLookupError:
            return
        except PermissionError:
            pass
        if gone(pid, master, 2):
            return


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    parser.add_argument("--init", required=True, type=Path)
    parser.add_argument("--initramfs", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    arguments = parser.parse_args()

    root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", Path(__file__).resolve().parents[2]))
    arguments.state_dir.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment["VINIX_INITRAMFS"] = str(arguments.initramfs)
    environment["VINIX_BOOT_DISK"] = str(arguments.state_dir / "boot.img")
    environment["VINIX_EFIVARS"] = str(arguments.state_dir / "efivars.fd")
    environment["VINIX_QEMU_PACKAGE_STORE"] = str(arguments.state_dir / "packages.tar")
    environment["VINIX_QEMU_PERSIST_DISK"] = str(arguments.state_dir / "root.ext2")
    environment["VINIX_QEMU_PERSIST_SIZE_MB"] = "64"
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    if arguments.arch == "aarch64":
        command = [str(root / "scripts/run-aarch64.sh"), "--serial", "--mem=2048",
                   f"--guest-init={arguments.init}"]
        if os.environ.get("VINIX_REBOOT_PERSISTENCE_NO_BUILD") == "1":
            command.insert(1, "--no-build")
    else:
        # Keep the image attached through a real guest reset. A second QEMU
        # launch or -no-reboot would not exercise the original shutdown path.
        archive = arguments.state_dir / "initramfs.tar"
        shutil.copyfile(arguments.initramfs, archive)
        with tarfile.open(archive, "a", format=tarfile.USTAR_FORMAT) as stream:
            stream.add(arguments.init, "sbin/init")
        isoenv = {**environment, "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(root / "kernel/bin/vinix")),
                  "VINIX_AMD64_INITRAMFS": str(archive), "VINIX_AMD64_ISO": str(arguments.state_dir / "test.iso"),
                  "VINIX_AMD64_ISO_BUILD_DIR": str(arguments.state_dir / "iso")}
        subprocess.run([str(root / "build-support/build-amd64-iso.sh")], env=isoenv, check=True,
                       stdout=subprocess.DEVNULL)
        seed = arguments.state_dir / "seed"
        for name in ("root", "dev", "proc", "tmp", "run"):
            (seed / name).mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive) as stream:
            stream.extractall(seed)
        (seed / ".vinix-image-id").write_text(hashlib.sha256(archive.read_bytes()).hexdigest()[:16] + "\n")
        disk = arguments.state_dir / "root.ext2"
        with disk.open("wb") as stream:
            stream.truncate(64 * 1024 * 1024)
        helper_path = root / "tests/disk-no-sync/run_vm.py"
        debugfs = runpy.run_path(str(helper_path))["find_debugfs"]()
        if not debugfs:
            raise RuntimeError("e2fsprogs is required for the native x86 persistence disk")
        subprocess.run([str(Path(debugfs).with_name("mke2fs")), "-q", "-F", "-t", "ext2", "-b", "4096", "-I", "128",
                        "-O", "filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum",
                        "-d", str(seed), str(disk)], check=True)
        qemu = shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64"))
        if not qemu:
            raise RuntimeError("qemu-system-x86_64 is required")
        firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(Path(qemu).parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        command = [qemu, "-machine", "q35,smm=off", "-accel", os.environ.get("VINIX_QEMU_ACCEL", "tcg"),
                   "-cpu", "max", "-m", "2048", "-smp", "2", "-drive",
                   f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}", "-cdrom", str(arguments.state_dir / "test.iso"),
                   "-drive", f"if=ide,format=raw,file={disk},cache=writeback", "-display", "none", "-monitor", "none",
                   "-serial", "stdio"]

    print("==> Booting; the guest restarts itself with reboot(2)")
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execve(command[0], command, environment)

    transcript = bytearray()
    finished = False
    deadline = time.monotonic() + arguments.timeout
    try:
        while time.monotonic() < deadline:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                break
            readable, _, _ = select.select([master], [], [], 0.25)
            if not readable:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            transcript += chunk
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            recent = bytes(transcript[-8192:])
            if PASS_MARKER in recent or any(m in recent for m in FAIL_MARKERS):
                finished = True
                break
    finally:
        stop_child(pid, master)
        os.close(master)

    text = bytes(transcript)
    (arguments.state_dir / "serial.log").write_bytes(text)
    print()
    if any(marker in text for marker in FAIL_MARKERS):
        print("ERROR: guest reported a failure", file=sys.stderr)
        return 1
    if text.count(START_MARKER) < 2:
        print("ERROR: the guest did not come back up after reboot(2)", file=sys.stderr)
        return 1
    if WROTE_MARKER not in text:
        print("ERROR: the guest never wrote the marker", file=sys.stderr)
        return 1
    # Both boots bracket their sync(2) with this, so a sync that never returns
    # shows up as a missing second half rather than as a mysterious timeout.
    if text.count(SYNC_MARKER) < 2:
        print("ERROR: sync(2) did not return", file=sys.stderr)
        return 1
    if PASS_MARKER not in text:
        print("ERROR: the file written before reboot(2) did not survive it",
              file=sys.stderr)
        return 1
    print(f"==> {arguments.arch} reboot persistence passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
