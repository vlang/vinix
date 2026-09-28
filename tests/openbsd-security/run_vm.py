#!/usr/bin/env python3
"""Boot Vinix with the OpenBSD security test as PID 1 and check its result."""

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


PASS_MARKER = b"VINIX OPENBSD SECURITY: PASS"
FAIL_MARKERS = (
    b"VINIX OPENBSD SECURITY: FAIL",
    b"OPENBSD SECURITY FAIL line",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)
# Every group of cases prints one of these, and the kernel reports each
# violation it kills a process for.
FEATURE_MARKERS = (
    b"OPENBSD SECURITY PASS: pledge promises and violations",
    b"OPENBSD SECURITY PASS: pledge proc, prot_exec and tmppath",
    b"OPENBSD SECURITY PASS: pledge sockets and descriptor passing",
    b"OPENBSD SECURITY PASS: pledge execpromises",
    b"OPENBSD SECURITY PASS: unveil hides and limits paths",
    b"OPENBSD SECURITY PASS: unveil across exec and pledge",
    b"OPENBSD SECURITY PASS: signal frames are signed",
    b"OPENBSD SECURITY PASS: process ids are random",
)
REPORT_MARKER = b': pledge "rpath", syscall '


def available_port() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return str(listener.getsockname()[1])


def reaped(pid: int, seconds: float) -> bool:
    deadline = time.monotonic() + seconds
    while True:
        try:
            waited, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return True
        if waited == pid:
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.05)


def stop(pid: int, master: int) -> None:
    # QEMU's serial console quits on Ctrl-A X; the runner exits with it.
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass
    if reaped(pid, 5):
        return
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
        if reaped(pid, 3):
            return


def command_for(arguments: argparse.Namespace, root: Path) -> tuple[list[str], dict[str, str]]:
    environment = os.environ.copy()
    if arguments.arch == "aarch64":
        state = arguments.state_dir
        environment["VINIX_INITRAMFS"] = str(arguments.initramfs)
        environment["VINIX_BOOT_DISK"] = str(state / "boot.img")
        environment["VINIX_EFIVARS"] = str(state / "efivars.fd")
        environment["VINIX_QEMU_PACKAGE_STORE"] = str(state / "packages.tar")
        environment["VINIX_QEMU_PERSIST_DISK"] = str(state / "root.ext2")
        environment["VINIX_QEMU_PERSIST_SIZE_MB"] = "64"
        environment.pop("VINIX_QEMU_PERSIST", None)
        environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
        if platform.system() != "Darwin":
            environment.setdefault("USE_TCG", "1")
        return [
            str(root / "run-aarch64.sh"),
            "--no-build",
            "--serial",
            "--mem=2048",
            f"--guest-init={arguments.init}",
        ], environment
    firmware = arguments.firmware
    return [
        arguments.qemu,
        "-machine", "q35,smm=off",
        "-accel", os.environ.get("VINIX_QEMU_ACCEL", "tcg"),
        "-cpu", "max",
        "-m", "1024",
        "-smp", "2",
        "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={firmware}",
        "-cdrom", str(arguments.iso),
        "-display", "none",
        "-monitor", "none",
        "-serial", "stdio",
        "-no-reboot",
    ], environment


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), required=True)
    parser.add_argument("--init", type=Path)
    parser.add_argument("--initramfs", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--iso", type=Path)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if arguments.state_dir is not None:
        arguments.state_dir.mkdir(parents=True, exist_ok=True)
    command, environment = command_for(arguments, root)

    print(f"==> Booting the {arguments.arch} OpenBSD security test")
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execvpe(command[0], command, environment)

    transcript = bytearray()
    deadline = time.monotonic() + arguments.timeout
    finished_at: float | None = None
    try:
        while time.monotonic() < deadline:
            if reaped(pid, 0):
                break
            readable, _, _ = select.select([master], [], [], 0.25)
            if readable:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        continue
                    raise
                transcript.extend(chunk)
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
            recent = bytes(transcript[-131072:])
            if finished_at is None and (PASS_MARKER in recent
                                        or any(marker in recent for marker in FAIL_MARKERS)):
                finished_at = time.monotonic()
            # Give the console a moment to drain, then stop the VM.
            if finished_at is not None and time.monotonic() - finished_at > 2:
                break
    finally:
        stop(pid, master)
        os.close(master)

    output = bytes(transcript)
    missing = [marker.decode() for marker in (*FEATURE_MARKERS, PASS_MARKER)
               if output.count(marker) != 1]
    # amd64 production kernels print to the framebuffer only.
    if arguments.arch == "aarch64" and REPORT_MARKER not in output:
        missing.append(REPORT_MARKER.decode())
    failures = [marker.decode() for marker in FAIL_MARKERS if marker in output]
    if finished_at is None:
        failures.append("the test did not finish before the timeout")
    for item in missing:
        print(f"ERROR: missing expected result: {item}", file=sys.stderr)
    for item in failures:
        print(f"ERROR: observed failure: {item}", file=sys.stderr)
    if missing or failures:
        return 1
    print(f"==> {arguments.arch} OpenBSD security test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
