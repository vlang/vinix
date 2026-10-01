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
import struct
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
    b"OPENBSD SECURITY PASS: the program break is random",
    b"OPENBSD SECURITY PASS: minherit and fork-time wiping",
    b"OPENBSD SECURITY PASS: ports, sequence numbers and IP IDs are random",
    b"OPENBSD SECURITY PASS: memory layouts are private",
)
REPORT_MARKER = b': pledge "rpath", syscall '
# The guest's NIC, as both runs give it, and how many connections and
# datagrams test.c's send_to_host() makes to QEMU's host.
GUEST_MAC = bytes.fromhex("525400123456")
WIRE_ROUNDS = 8


def capture_frames(path: Path) -> list[bytes]:
    """The Ethernet frames in a pcap file that QEMU's filter-dump wrote."""
    data = path.read_bytes()
    if len(data) < 24:
        return []
    magic = struct.unpack("<I", data[:4])[0]
    order = "<" if magic in (0xA1B2C3D4, 0xA1B23C4D) else ">"
    frames = []
    at = 24
    while at + 16 <= len(data):
        _, _, included, _ = struct.unpack(order + "IIII", data[at:at + 16])
        frames.append(data[at + 16:at + 16 + included])
        at += 16 + included
    return frames


def close_pairs(values: list[int], modulus: int, within: int) -> int:
    """How many values come within `within` after the one before, mod `modulus`."""
    return sum(1 for a, b in zip(values, values[1:]) if 0 < (b - a) % modulus <= within)


def check_capture(path: Path) -> list[str]:
    """Problems with what the guest sent: sequence numbers, ports or IP IDs
    a counter would have produced."""
    if not path.exists():
        return ["QEMU wrote no packet capture"]
    ids: list[int] = []
    syns: dict[int, int] = {}
    datagram_ports: list[int] = []
    for frame in capture_frames(path):
        if len(frame) < 34 or frame[6:12] != GUEST_MAC or frame[12:14] != b"\x08\x00":
            continue
        ip = frame[14:]
        header = (ip[0] & 0xF) * 4
        ids.append(struct.unpack(">H", ip[4:6])[0])
        transport = ip[header:]
        if ip[16:20] != bytes([10, 0, 2, 2]) or len(transport) < 8:
            continue
        source, destination = struct.unpack(">HH", transport[:4])
        if destination != 9:
            continue
        if ip[9] == 6 and len(transport) >= 14 and transport[13] & 0x12 == 0x02:
            syns.setdefault(source, struct.unpack(">I", transport[4:8])[0])
        elif ip[9] == 17:
            datagram_ports.append(source)
    problems = []
    if len(ids) < 2 * WIRE_ROUNDS:
        return [f"the capture has only {len(ids)} packets from the guest"]
    sequential = close_pairs(ids, 1 << 16, 64)
    if sequential > max(2, len(ids) // 20):
        problems.append(f"{sequential} of {len(ids) - 1} IP IDs follow the one before")
    if len(syns) < WIRE_ROUNDS // 2:
        problems.append(f"only {len(syns)} SYNs reached the capture")
    isns = list(syns.values())
    near = sum(1 for a, b in zip(isns, isns[1:])
               if min((b - a) % (1 << 32), (a - b) % (1 << 32)) < (1 << 24))
    if near > 1:
        problems.append(f"{near} of {len(isns) - 1} initial sequence numbers are near the last")
    for kind, ports in (("TCP", list(syns)), ("UDP", datagram_ports)):
        if any(port < 49152 for port in ports):
            problems.append(f"a {kind} source port is outside the ephemeral range: {ports}")
        if close_pairs(ports, 1 << 16, 1) > 2:
            problems.append(f"{kind} source ports are handed out in sequence: {ports}")
    print(f"==> capture: {len(ids)} guest packets, {sequential} IDs in sequence, "
          f"{len(isns)} SYNs, {near} close ISNs, {len(datagram_ports)} datagrams")
    return problems


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
        dump = f"-object filter-dump,id=vinixdump,netdev=net0,file={arguments.capture}"
        environment["VINIX_QEMU_EXTRA"] = " ".join(
            filter(None, (environment.get("VINIX_QEMU_EXTRA"), dump)))
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
        "-netdev", "user,id=net0",
        "-device", "e1000,netdev=net0,mac=52:54:00:12:34:56",
        "-object", f"filter-dump,id=vinixdump,netdev=net0,file={arguments.capture}",
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
    parser.add_argument("--capture", type=Path, required=True)
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
    if b"OPENBSD SECURITY WIRE: sent" in output:
        failures.extend(check_capture(arguments.capture))
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
