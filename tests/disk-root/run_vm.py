#!/usr/bin/env python3
"""Boot an AArch64 machine off its own disk and enforce whole-filesystem persistence.

The runner installs the supplied image onto the persistent volume and boots
from it, so the machine has no RAM root to lose a write to. One QEMU process
throughout: the guest restarts itself with reboot(2).
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


START_MARKER = b"VINIX DISK ROOT: START"
VOLUME_MARKER = b"VINIX DISK ROOT: ON VOLUME"
LARGE_MARKER = b"VINIX DISK ROOT: LARGE FILE OK"
WROTE_MARKER = b"VINIX DISK ROOT: WROTE /etc MARKER, REBOOTING"
PASS_MARKER = b"VINIX DISK ROOT: PASS"
FAIL_MARKERS = (
    b"VINIX DISK ROOT: FAIL",
    b"does not carry a bootable system",
    b"using the initramfs root",
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
    environment.setdefault("VINIX_QEMU_PERSIST_SIZE_MB", "64")
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    command = [str(root / "run-aarch64.sh"), "--serial", "--mem=2048",
               "--disk-root"]
    if os.environ.get("VINIX_DISK_ROOT_NO_BUILD") == "1":
        command.insert(1, "--no-build")

    print("==> Installing the system on a volume and booting from it")
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
    if text.count(VOLUME_MARKER) < 2:
        print("ERROR: the guest did not boot from the volume both times",
              file=sys.stderr)
        return 1
    if text.count(LARGE_MARKER) < 2:
        print("ERROR: a host-written file past the direct blocks did not read back",
              file=sys.stderr)
        return 1
    if WROTE_MARKER not in text:
        print("ERROR: the guest never wrote the marker", file=sys.stderr)
        return 1
    if PASS_MARKER not in text:
        print("ERROR: the file written outside /root did not survive the restart",
              file=sys.stderr)
        return 1
    print("==> AArch64 disk-root persistence passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
