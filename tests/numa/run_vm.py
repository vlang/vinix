#!/usr/bin/env python3
"""Boot the AArch64 machine with two NUMA nodes and enforce the guest verdict."""

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


PASS_MARKER = b"VINIX QEMU NUMA: PASS"
FAIL_MARKERS = (
    b"VINIX QEMU NUMA: FAIL",
    b"QEMU NUMA FAIL:",
    b"FATAL EXCEPTION",
    b"KERNEL PANIC",
)
# What the guest program checks, one line each. All of them must appear exactly
# once: a missing line is a check that never ran, which is not a pass.
FEATURE_MARKERS = (
    b"QEMU NUMA PASS: sysfs reports two nodes, two CPUs each, 1 GiB each",
    b"QEMU NUMA PASS: getcpu names the node whose CPU list holds the running CPU",
    b"QEMU NUMA PASS: mempolicy reports and validates what it is given",
    b"QEMU NUMA PASS: a bound process takes its pages from the node it asked for",
    b"QEMU NUMA PASS: mbind places the pages of the range it named",
    b"QEMU NUMA PASS: first touch takes pages from the node that faulted them",
)
# The kernel's own account of the machine, so a guest that agreed with itself
# about the wrong topology cannot pass.
KERNEL_MARKERS = (
    b"numa: 2 memory nodes from acpi",
    b"numa: node 0 holds cpus 0x3",
    b"numa: node 1 holds cpus 0xc",
    b"numa:   node 0 distances 10 20",
    b"numa:   node 1 distances 20 10",
)

# Two nodes of one gigabyte, two CPUs each, one hop apart. run-aarch64.sh boots
# with -smp 4 and -m as given, and QEMU requires the memory backends to add up
# to that total.
NUMA_TOPOLOGY = " ".join(
    (
        "-object memory-backend-ram,id=vinix-numa0,size=1024M",
        "-object memory-backend-ram,id=vinix-numa1,size=1024M",
        "-numa node,nodeid=0,cpus=0-1,memdev=vinix-numa0",
        "-numa node,nodeid=1,cpus=2-3,memdev=vinix-numa1",
        "-numa dist,src=0,dst=1,val=20",
    )
)
GUEST_MEMORY_MB = 2048


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


def run_vm(
    root: Path,
    guest_init: Path,
    initramfs: Path,
    state_dir: Path,
    timeout: int,
) -> int:
    state_dir.mkdir(parents=True, exist_ok=True)

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
    extra = environment.get("VINIX_QEMU_EXTRA", "")
    environment["VINIX_QEMU_EXTRA"] = f"{extra} {NUMA_TOPOLOGY}".strip()
    if platform.system() != "Darwin":
        environment.setdefault("USE_TCG", "1")

    command = [
        str(root / "run-aarch64.sh"),
        "--serial",
        f"--mem={GUEST_MEMORY_MB}",
        f"--guest-init={guest_init}",
    ]
    if os.environ.get("VINIX_QEMU_NUMA_NO_BUILD") == "1":
        command.insert(1, "--no-build")

    print("==> Starting AArch64 QEMU boot with two NUMA nodes")

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

            recent = bytes(transcript)
            finished = PASS_MARKER in recent or any(
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
    missing = [
        marker.decode("ascii")
        for marker in (*FEATURE_MARKERS, PASS_MARKER)
        if output.count(marker) != 1
    ]
    missing += [
        marker.decode("ascii") for marker in KERNEL_MARKERS if marker not in output
    ]
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
    print("==> AArch64 QEMU NUMA regression passed")
    return 0


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
    return run_vm(
        root,
        arguments.init.resolve(),
        arguments.initramfs.resolve(),
        arguments.state_dir.resolve(),
        arguments.timeout,
    )


if __name__ == "__main__":
    raise SystemExit(main())
