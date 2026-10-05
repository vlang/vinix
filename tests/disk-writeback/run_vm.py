#!/usr/bin/env python3
"""Boot an AArch64 machine off its own disk and time the disk while it is written.

The runner installs the supplied image onto the persistent volume and boots
from it, so /tmp, and the stream the guest writes there, are on the volume and
go through its block cache. The guest powers itself off.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import platform
import pty
import select
import signal
import socket
import sys
import time


START_MARKER = b"VINIX WRITEBACK: START"
PASS_MARKER = b"VINIX WRITEBACK: PASS"
FAIL_MARKERS = (
    b"VINIX WRITEBACK: FAIL",
    b"does not carry a bootable system",
    b"using the initramfs root",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)


def available_port() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return str(listener.getsockname()[1])


def gone(pid: int, master: int, seconds: float) -> bool:
    # pty.fork made run-aarch64.sh the leader of a process group of its own,
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
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    arguments = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    arguments.state_dir.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    # The same tiny image is both what gets installed and the fallback payload,
    # so a boot that quietly used the initramfs still reaches the test -- which
    # then fails it on the missing volume marker rather than passing blind.
    environment["VINIX_QEMU_ROOT_IMAGE"] = str(arguments.image)
    environment["VINIX_INITRAMFS"] = str(arguments.image)
    # Keep the image as the fallback payload rather than a recovery shell, so a
    # boot that quietly used the initramfs still runs this test -- which then
    # fails it on the missing volume marker instead of timing out mutely.
    environment["VINIX_QEMU_ROOT_FALLBACK"] = "image"
    environment["VINIX_BOOT_DISK"] = str(arguments.state_dir / "boot.img")
    environment["VINIX_EFIVARS"] = str(arguments.state_dir / "efivars.fd")
    environment["VINIX_QEMU_PACKAGE_STORE"] = str(arguments.state_dir / "packages.tar")
    environment["VINIX_QEMU_PERSIST_DISK"] = str(arguments.state_dir / "root.ext2")
    # The installer takes the larger of this and what the image needs, so a
    # caller can widen the volume to reproduce a size-dependent problem.
    environment.setdefault("VINIX_QEMU_PERSIST_SIZE_MB", "8192")
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    command = [str(root / "run-aarch64.sh"), "--serial", "--mem=2048",
               "--disk-root"]
    if os.environ.get("VINIX_DISK_ROOT_NO_BUILD") == "1":
        command.insert(1, "--no-build")

    print("==> Installing the system on a volume and streaming to it")
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
    print()
    if any(marker in text for marker in FAIL_MARKERS):
        print("ERROR: guest reported a failure", file=sys.stderr)
        return 1
    if START_MARKER not in text:
        print("ERROR: the guest never started the test", file=sys.stderr)
        return 1
    if PASS_MARKER not in text:
        print("ERROR: the guest did not finish; a wait that never ended looks like this",
              file=sys.stderr)
        return 1
    print("==> AArch64 disk writeback kept the machine responsive")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
