#!/usr/bin/env python3
"""Boot the AArch64 machine once and enforce the reboot-persistence result.

Unlike the core regression, this is a single QEMU process: the guest resets
itself with reboot(2), so the kernel's shutdown path -- not a second launch --
is what has to get the pending write to the disk.
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


def reaped(pid: int, seconds: float) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            waited, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return True
        if waited == pid:
            return True
        time.sleep(0.05)
    return False


def stop_child(pid: int, master: int) -> None:
    # Ctrl-A x is QEMU's own quit, and the only stop that lets it release the
    # disk images cleanly. Signals are the fallback for a QEMU that is wedged.
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass
    if reaped(pid, 5):
        return
    for signal_number in (signal.SIGTERM, signal.SIGKILL):
        # The child is run-aarch64.sh, not a process-group leader, so signal
        # the process itself: killpg would need a group this never created.
        try:
            os.kill(pid, signal_number)
        except ProcessLookupError:
            return
        if reaped(pid, 2):
            return


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--init", required=True, type=Path)
    parser.add_argument("--initramfs", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    arguments = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
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

    command = [str(root / "run-aarch64.sh"), "--serial", "--mem=2048",
               f"--guest-init={arguments.init}"]
    if os.environ.get("VINIX_REBOOT_PERSISTENCE_NO_BUILD") == "1":
        command.insert(1, "--no-build")

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
    print("==> AArch64 reboot persistence passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
