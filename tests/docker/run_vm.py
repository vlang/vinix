#!/usr/bin/env python3
"""Boot the AArch64 QEMU machine with a test init and wait for its verdict."""

from __future__ import annotations

import argparse
import errno
import os
from pathlib import Path
import platform
import pty
import select
import signal
import socket
import sys
import time

FAIL_MARKERS = (
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)


def available_port() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return str(listener.getsockname()[1])


def stop_child(pid: int, master: int) -> None:
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        waited, _ = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return
        time.sleep(0.05)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except ProcessLookupError:
            return
        time.sleep(1)
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--init", type=Path, required=True)
    parser.add_argument("--initramfs", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--mem", default="4096")
    parser.add_argument("--pass-marker", required=True)
    parser.add_argument("--fail-marker", action="append", default=[])
    parser.add_argument("--log", type=Path)
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=True)
    pass_marker = args.pass_marker.encode()
    fail_markers = FAIL_MARKERS + tuple(m.encode() for m in args.fail_marker)

    environment = os.environ.copy()
    environment["VINIX_INITRAMFS"] = str(args.initramfs.resolve())
    environment["VINIX_BOOT_DISK"] = str(state / "boot.img")
    environment["VINIX_EFIVARS"] = str(state / "efivars.fd")
    environment["VINIX_QEMU_PACKAGE_STORE"] = str(state / "packages.tar")
    environment["VINIX_QEMU_PACKAGE_PERSIST"] = "0"
    environment["VINIX_QEMU_HOST_SOURCE"] = "0"
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    command = [str(root / "run-aarch64.sh"), "--serial", "--no-persist",
               f"--mem={args.mem}", f"--guest-init={args.init.resolve()}"]
    if args.no_build:
        command.insert(1, "--no-build")

    log = open(args.log, "wb") if args.log else None
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execve(command[0], command, environment)

    transcript = bytearray()
    status = None
    verdict = None
    shutdown_deadline = None
    deadline = time.monotonic() + args.timeout
    try:
        while time.monotonic() < deadline:
            waited, child_status = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                status = child_status
                break
            readable, _, _ = select.select([master], [], [], 0.25)
            if readable:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        continue
                    raise
                if chunk:
                    transcript.extend(chunk)
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
                    if log:
                        log.write(chunk)
                        log.flush()
            if verdict is None:
                recent = bytes(transcript[-262144:])
                if pass_marker in recent:
                    verdict = "pass"
                else:
                    for marker in fail_markers:
                        if marker in recent:
                            verdict = f"failure marker {marker.decode()!r}"
                            break
                if verdict is not None:
                    shutdown_deadline = time.monotonic() + 5
            if shutdown_deadline is not None and time.monotonic() >= shutdown_deadline:
                break
    finally:
        if status is None:
            stop_child(pid, master)
        os.close(master)
        if log:
            log.close()

    if verdict == "pass":
        print(f"\n==> {args.pass_marker}")
        return 0
    if verdict is None:
        verdict = "timeout" if status is None else "VM exited without a verdict"
    print(f"\nERROR: {verdict}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
