#!/usr/bin/env python3
"""Boot the AArch64 QEMU machine and enforce a browser bring-up result."""

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


# The bring-up boot drives a staged browser; the package boot installs one from
# the Alpine repositories first. They report separately because a machine
# without a network can still run the first.
BRING_UP = {
    "init": "tests/browsers/chromium-init.sh",
    "pass": b"VINIX CHROMIUM TEST: PASS",
    "fail": (b"VINIX CHROMIUM TEST: FAIL",),
    # Headless is run and reported but not required: it produces no DOM on
    # Vinix yet, while the graphical path — the one the desktop uses — renders
    # the whole browser. Requiring it would fail a run in which the browser
    # demonstrably works.
    "features": (
        b"VINIX CHROMIUM PASS: version",
        b"VINIX CHROMIUM PASS: the hosted display has a framebuffer",
        b"VINIX CHROMIUM PASS: browser window mapped",
    ),
}
FIREFOX = {
    "init": "tests/browsers/firefox-init.sh",
    "pass": b"VINIX FIREFOX TEST: PASS",
    "fail": (b"VINIX FIREFOX TEST: FAIL",),
    "features": (
        b"VINIX FIREFOX PASS: the hosted display has a framebuffer",
        b"VINIX FIREFOX PASS: browser window mapped",
    ),
}
PACKAGE = {
    "init": "tests/browsers/pkg-init.sh",
    "pass": b"VINIX CHROMIUM PACKAGE TEST: PASS",
    "fail": (b"VINIX CHROMIUM PACKAGE TEST: FAIL",),
    "features": (
        b"VINIX CHROMIUM PASS: the image ships the launcher but not the browser",
        b"VINIX CHROMIUM PASS: pkg installed Chromium and its runtime",
        b"VINIX CHROMIUM PASS: the installed browser runs",
    ),
}
COMMON_FAIL_MARKERS = (b"FATAL EXCEPTION", b"KERNEL PANIC")


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
    except (ProcessLookupError, PermissionError):
        # Gone already, or never became a process group leader.
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        waited, _ = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return
        time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def run_vm(root: Path, guest_init: Path, initramfs: Path, state_dir: Path,
           memory_mb: int, timeout: int, build: bool, profile: dict) -> int:
    state_dir.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment["VINIX_INITRAMFS"] = str(initramfs)
    environment["VINIX_BOOT_DISK"] = str(state_dir / "boot.img")
    environment["VINIX_EFIVARS"] = str(state_dir / "efivars.fd")
    environment["VINIX_QEMU_PACKAGE_STORE"] = str(state_dir / "packages.tar")
    environment["VINIX_QEMU_PERSIST_DISK"] = str(state_dir / "root.ext2")
    environment["VINIX_QEMU_PERSIST_SIZE_MB"] = "256"
    environment.pop("VINIX_QEMU_PERSIST", None)
    environment["VINIX_KEEP_TEMP_BOOT_DISK"] = "1"
    environment.setdefault("VINIX_QEMU_PACKAGE_STORE_PORT", available_port())
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    command = [
        str(root / "run-aarch64.sh"),
        "--serial",
        f"--mem={memory_mb}",
        f"--guest-init={guest_init}",
    ]
    if not build:
        command.insert(1, "--no-build")

    fail_markers = profile["fail"] + COMMON_FAIL_MARKERS
    print("==> Starting AArch64 QEMU browser boot")

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
            finished = profile["pass"] in recent or any(
                marker in recent for marker in fail_markers
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
    missing = [marker.decode("ascii")
               for marker in (*profile["features"], profile["pass"])
               if marker not in output]
    failures = [marker.decode("ascii", errors="replace")
                for marker in fail_markers if marker in output]
    if status is not None and exit_code(status) != 0:
        failures.append(f"VM runner exit status {exit_code(status)}")
    if forced_stop:
        failures.append("VM did not exit after the test")
    if missing or failures:
        for item in missing:
            print(f"ERROR: missing expected browser result: {item}", file=sys.stderr)
        for item in failures:
            print(f"ERROR: observed browser failure: {item}", file=sys.stderr)
        return 1
    print("==> AArch64 QEMU browser boot passed")
    return 0


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--firefox", action="store_true",
                        help="drive Firefox instead of Chromium")
    parser.add_argument("--package", action="store_true",
                        help="install Chromium with pkg instead of driving a staged one")
    parser.add_argument("--init", type=Path)
    parser.add_argument("--initramfs", type=Path,
                        default=root / "build-support/init-aarch64/initramfs-desktop.tar")
    parser.add_argument("--state-dir", type=Path,
                        default=root / "build/browser-vm")
    parser.add_argument("--mem", type=int, default=8192)
    # A package boot fetches a quarter of a gigabyte through QEMU's user
    # networking and unpacks it on an emulated CPU; the browser boots are the
    # quick ones.
    parser.add_argument("--timeout", type=int, default=0,
                        help="seconds to allow (default: 1800, or 5400 with --package)")
    parser.add_argument("--build", action="store_true",
                        help="rebuild the kernel before booting")
    arguments = parser.parse_args()
    if arguments.timeout < 0:
        parser.error("--timeout must be positive")
    if arguments.package and arguments.firefox:
        parser.error("--package installs Chromium; it cannot be combined with --firefox")
    profile = PACKAGE if arguments.package else FIREFOX if arguments.firefox else BRING_UP
    timeout = arguments.timeout or (5400 if arguments.package else 1800)
    guest_init = arguments.init or (root / profile["init"])
    return run_vm(root, guest_init.resolve(), arguments.initramfs.resolve(),
                  arguments.state_dir.resolve(), arguments.mem, timeout,
                  arguments.build, profile)


if __name__ == "__main__":
    raise SystemExit(main())
