#!/usr/bin/env python3
"""Boot the AArch64 QEMU machine and enforce the core guest-test result."""

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


PASS_MARKER = b"VINIX QEMU CORE: PASS"
PERSIST_MARKER = b"VINIX QEMU CORE PERSIST: PASS"
FAIL_MARKERS = (
    b"VINIX QEMU CORE: FAIL",
    b"QEMU CORE FAIL line",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)
FEATURE_MARKERS = (
    b"QEMU CORE PASS: secure getrandom",
    b"QEMU CORE PASS: copy-on-write fork",
    b"QEMU CORE PASS: ext2 cache, mmap, sync, namespace, timestamps",
    b"QEMU CORE PASS: a shared mapping is visible to every reader",
    b"QEMU CORE PASS: fcntl and flock exclusion",
    b"QEMU CORE PASS: permissions, umask, and resource limits",
    b"QEMU CORE PASS: inotify events",
    b"QEMU CORE PASS: priority, affinity, and accounting",
    b"QEMU CORE PASS: POSIX SIGEV_THREAD timer notification",
    b"QEMU CORE PASS: anonymous descriptors are open both ways",
    b"QEMU CORE PASS: abstract socket names are released",
    b"QEMU CORE PASS: persistence markers synchronized",
)


def available_port() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return str(listener.getsockname()[1])


def exit_code(status: int) -> int:
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 1


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

    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        waited, _ = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return
        time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def run_phase(
    root: Path,
    guest_init: Path,
    initramfs: Path,
    state_dir: Path,
    timeout: int,
    verification_boot: bool,
) -> int:
    environment = os.environ.copy()
    environment["VINIX_INITRAMFS"] = str(initramfs)
    environment["VINIX_BOOT_DISK"] = str(state_dir / "boot.img")
    environment["VINIX_EFIVARS"] = str(state_dir / "efivars.fd")
    environment["VINIX_QEMU_PACKAGE_STORE"] = str(state_dir / "packages.tar")
    environment["VINIX_QEMU_PERSIST_DISK"] = str(state_dir / "root.ext2")
    environment["VINIX_QEMU_PERSIST_SIZE_MB"] = "64"
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    command = [
        str(root / "run-aarch64.sh"),
        "--serial",
        "--mem=2048",
        f"--guest-init={guest_init}",
    ]
    if verification_boot or os.environ.get("VINIX_QEMU_CORE_NO_BUILD") == "1":
        command.insert(1, "--no-build")

    phase = "persistence verification" if verification_boot else "core feature"
    print(f"==> Starting AArch64 QEMU {phase} boot")

    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execve(command[0], command, environment)

    transcript = bytearray()
    status: int | None = None
    forced_stop = False
    shutdown_deadline: float | None = None
    deadline = time.monotonic() + timeout
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

            recent = bytes(transcript[-131072:])
            expected_final = PERSIST_MARKER if verification_boot else PASS_MARKER
            finished = expected_final in recent or any(
                marker in recent for marker in FAIL_MARKERS
            )
            if finished and shutdown_deadline is None:
                try:
                    os.write(master, b"\x01x")
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                shutdown_deadline = time.monotonic() + 10
            if shutdown_deadline is not None and time.monotonic() >= shutdown_deadline:
                break
    finally:
        if status is None:
            forced_stop = True
            stop_child(pid, master)
        os.close(master)

    output = bytes(transcript)
    expected_markers = (PERSIST_MARKER,) if verification_boot else (
        *FEATURE_MARKERS,
        PASS_MARKER,
    )
    missing = [marker.decode("ascii") for marker in expected_markers
               if output.count(marker) != 1]
    failures = [
        marker.decode("ascii", errors="replace")
        for marker in FAIL_MARKERS
        if marker in output
    ]
    if status is not None and exit_code(status) != 0:
        failures.append(f"VM runner exit status {exit_code(status)}")
    if forced_stop:
        failures.append("VM did not exit after the test")
    if missing or failures:
        for item in missing:
            print(f"ERROR: missing expected QEMU result: {item}", file=sys.stderr)
        for item in failures:
            print(f"ERROR: observed QEMU failure: {item}", file=sys.stderr)
        return 1
    print(f"==> AArch64 QEMU {phase} boot passed")
    return 0


def run_vm(
    root: Path,
    guest_init: Path,
    initramfs: Path,
    state_dir: Path,
    timeout: int,
) -> int:
    state_dir.mkdir(parents=True, exist_ok=True)
    result = run_phase(root, guest_init, initramfs, state_dir, timeout, False)
    if result != 0:
        return result
    result = run_phase(root, guest_init, initramfs, state_dir, timeout, True)
    if result == 0:
        print("==> AArch64 QEMU core regression passed across reboot")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--init", type=Path, required=True)
    parser.add_argument("--initramfs", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=300)
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("--timeout must be positive")
    root = Path(__file__).resolve().parents[2]
    return run_vm(root, arguments.init.resolve(), arguments.initramfs.resolve(),
                  arguments.state_dir.resolve(), arguments.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
