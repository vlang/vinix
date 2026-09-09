#!/usr/bin/env python3
"""Render in Vinix through VirtIO/VirGL and KekVM's macOS GPU backend."""

from __future__ import annotations

import argparse
import errno
import os
from pathlib import Path
import platform
import pty
import re
import select
import signal
import subprocess
import sys
import tempfile
import time


PASS_LINE = re.compile(rb"(?:^|\r*\n)VINIX_VIRGL_VM_PASS\r*(?:\n|$)")
FAIL_LINE = re.compile(rb"(?:^|\r*\n)VINIX_VIRGL_VM_FAIL:[0-9]+\r*(?:\n|$)")
RENDERER = re.compile(rb"GL_RENDERER=[^\r\n]*virgl[^\r\n]*Apple", re.IGNORECASE)
PIXELS = b"gl-triangle-agx: hardware frame rendered successfully"
VIRGL_PASS = b"VINIX VIRGL RENDER TEST: PASS"
M1_HARDWARE_PASS = b"VINIX M1 AGX RENDER TEST: PASS"


def child_exit_code(status: int) -> int:
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
        waited, _status = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return
        time.sleep(0.05)

    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        waited, _status = os.waitpid(pid, os.WNOHANG)
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


def qemu_path(root: Path) -> Path:
    override = os.environ.get("VINIX_VIRGL_QEMU")
    if override:
        return Path(override).expanduser().resolve()
    return root.parent / "kekvm/.tools/qemu-virgl/bin/qemu-system-aarch64"


def check_host(root: Path) -> tuple[Path, str | None]:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        return Path(), "this test requires an Apple-silicon macOS host"

    qemu = qemu_path(root)
    if not qemu.is_file() or not os.access(qemu, os.X_OK):
        return qemu, (
            f"KekVM's VirGL QEMU is missing: {qemu}\n"
            "Run `make setup-gpu` in ~/code/kekvm first."
        )

    devices = subprocess.run(
        [qemu, "-device", "help"], capture_output=True, check=False
    )
    if devices.returncode != 0 or b"virtio-gpu-gl-device" not in devices.stdout:
        return qemu, "KekVM QEMU has no MMIO virtio-gpu-gl-device"

    displays = subprocess.run(
        [qemu, "-display", "help"], capture_output=True, check=False
    )
    display_help = displays.stdout + displays.stderr
    if displays.returncode != 0 or b"cocoa" not in display_help:
        return qemu, "KekVM QEMU has no Cocoa GL display backend"
    return qemu, None


def run_vm(root: Path, timeout: int) -> int:
    qemu, host_error = check_host(root)
    if host_error:
        print(f"ERROR: {host_error}", file=sys.stderr)
        return 2

    kernel = root / "kernel/bin/vinix"
    image = root / "build-support/init-aarch64/initramfs-desktop.tar"
    guest_init = root / "tests/virtio-gpu-virgl/guest-init.sh"
    for label, path in (("kernel", kernel), ("desktop initramfs", image)):
        if not path.is_file():
            print(f"ERROR: Vinix {label} is missing: {path}", file=sys.stderr)
            return 2

    # Leave 256 MiB for the kernel, loader, configuration and FAT metadata.
    image_mb = (image.stat().st_size + 1024 * 1024 - 1) // (1024 * 1024)
    disk_mb = max(2048, image_mb + 256)

    print(f"Host transport: {qemu}")
    print("Path: Vinix VirtIO-GPU -> VirGL -> virglrenderer -> ANGLE/Metal")
    print("Boundary: this does not emulate native AGX RTKit/UAT/firmware")

    with tempfile.TemporaryDirectory(prefix="vinix-virgl-vm.") as scratch:
        environment = os.environ.copy()
        environment["VINIX_VIRGL_QEMU"] = str(qemu)
        environment["VINIX_INITRAMFS"] = str(image)
        environment["VINIX_BOOT_DISK"] = str(Path(scratch) / "boot.img")
        environment["VINIX_BOOT_DISK_SIZE_MB"] = str(disk_mb)
        environment["VINIX_EFIVARS"] = str(Path(scratch) / "efivars.fd")
        environment.setdefault("VINIX_QEMU_MEM", "8192")

        command = [
            str(root / "run-aarch64.sh"),
            "--no-build",
            "--virgl",
            f"--guest-init={guest_init}",
            f"--disk={disk_mb}",
        ]
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(root)
            os.execve(command[0], command, environment)

        transcript = bytearray()
        pass_seen = False
        fail_seen = False
        shutdown_sent = False
        forced_stop = False
        status: int | None = None
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                waited, child_status = os.waitpid(pid, os.WNOHANG)
                if waited == pid:
                    status = child_status
                    break

                readable, _, _ = select.select([master], [], [], 0.25)
                if not readable:
                    continue
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        continue
                    raise
                if not chunk:
                    continue
                transcript.extend(chunk)
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()

                recent = bytes(transcript[-131072:])
                pass_seen = PASS_LINE.search(recent) is not None
                fail_seen = FAIL_LINE.search(recent) is not None
                if (pass_seen or fail_seen) and not shutdown_sent:
                    os.write(master, b"\x01x")
                    shutdown_sent = True
                    deadline = min(deadline, time.monotonic() + 10)

            if status is None:
                waited, child_status = os.waitpid(pid, os.WNOHANG)
                if waited == pid:
                    status = child_status
        finally:
            if status is None:
                forced_stop = True
                stop_child(pid, master)
            os.close(master)

        output = bytes(transcript)
        missing = []
        if not RENDERER.search(output):
            missing.append("VirGL renderer backed by an Apple host GPU")
        if output.count(PIXELS) != 1:
            missing.append("validated rendered pixels")
        if output.count(VIRGL_PASS) != 1:
            missing.append("in-guest VirGL PASS marker")
        if M1_HARDWARE_PASS in output:
            missing.append("VM incorrectly claimed a native M1 AGX pass")
        if not pass_seen:
            missing.append("guest test-init PASS marker")
        if fail_seen:
            missing.append("guest test-init reported failure")
        if forced_stop:
            missing.append("VM did not exit after the result")
        if status is not None and child_exit_code(status) != 0:
            missing.append(f"VM exit status {child_exit_code(status)}")
        if missing:
            print("\nFAIL KekVM VirGL smoke test: " + ", ".join(missing), file=sys.stderr)
            return 1

    print("\nPASS Vinix rendered validated pixels through KekVM and the host Apple GPU")
    print("NOTE native Apple AGX firmware execution remains a physical-hardware test")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.environ.get("VINIX_VIRGL_VM_TIMEOUT", "240")),
        help="maximum setup, boot and render time in seconds (default: 240)",
    )
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("--timeout must be positive")
    return run_vm(Path(__file__).resolve().parents[2], arguments.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
