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


TEST_LABEL = "OpenBSD security"
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
    b"OPENBSD SECURITY PASS: read-only files stay read-only",
    b"OPENBSD SECURITY PASS: immutable and append-only files",
    b"OPENBSD SECURITY PASS: bad user pointers fault rather than panic",
    b"OPENBSD SECURITY PASS: a process's buffers are never taken for the kernel's",
)
REPORT_MARKER = b': pledge "rpath", syscall '
# The guest's NIC, as both runs give it, and how many connections and
# datagrams test.c's send_to_host() makes to QEMU's host.
GUEST_MAC = bytes.fromhex("525400123456")
WIRE_ROUNDS = 8


_LITERAL_CACHE = {}
_SLOT_KEYS = {name: sys.intern(name) for name in ('AF_INET', 'EIO', 'SIGKILL', 'SIGTERM', 'SOCK_STREAM', 'WNOHANG', 'append', 'arch', 'bind', 'buffer', 'capture', 'copy', 'count', 'decode', 'environ', 'errno', 'exists', 'extend', 'firmware', 'flush', 'get', 'getsockname', 'init', 'initramfs', 'iso', 'join', 'killpg', 'monotonic', 'pop', 'qemu', 'read', 'read_bytes', 'select', 'setdefault', 'sleep', 'socket', 'state_dir', 'stderr', 'stdout', 'system', 'unpack', 'values', 'waitpid', 'write')}
_ATTRIBUTE, _TRUTH, _ITER, _REPR, _SLICE = getattr, bool, iter, repr, slice
_namespace = globals
_frame = sys._getframe

import importlib.util as _loader
_spec = _loader.spec_from_file_location("security_guest_binding", Path(__file__).with_name("_native.py"))
_library = _loader.module_from_spec(_spec)
_spec.loader.exec_module(_library)


def _native(operation, *arguments):
    try:
        return _library.call(operation, _namespace(), _frame(1).f_builtins, *arguments)
    finally:
        arguments = None


def _list(*items):
    return [*items]


def _tuple(*items):
    return (*items,)


def _named(*pairs):
    return {key: value for key, value in pairs}


def _triple(value):
    try:
        first, second, third = value
        return first, second, third
    except:
        value = None
        raise


def _FORMAT(value):
    try:
        return f"{value}"
    finally:
        value = None




def _close_candidates(iterator, modulus, within):
    try:
        return (1 for a, b in iterator if _native("close_candidate", a, b, modulus, within))
    finally:
        iterator = None


def _near_candidates(iterator):
    try:
        return (1 for a, b in iterator if _native("near_candidate", a, b))
    finally:
        iterator = None


def _failure_candidates(recent, markers):
    try:
        return (_native("contains_marker", recent, marker) for marker in markers)
    finally:
        markers = None



def _quad(value):
    try:
        first, second, third, fourth = value
        return first, second, third, fourth
    finally:
        value = None


def _dict():
    return {}


def _feature_markers():
    return (*FEATURE_MARKERS, PASS_MARKER)


def _missing(output, markers):
    try:
        return [marker.decode() for marker in markers if _native("missing_marker", output, marker)]
    finally:
        markers = None


def _failures(output, markers):
    try:
        return [marker.decode() for marker in markers if _native("contains_marker", output, marker)]
    finally:
        markers = None


def _ephemeral(ports):
    return (port < 49152 for port in ports)


def capture_frames(path: Path) -> list[bytes]:
    """The Ethernet frames in a pcap file that QEMU's filter-dump wrote."""
    return _native('capture_frames', path)


def close_pairs(values: list[int], modulus: int, within: int) -> int:
    """How many values come within `within` after the one before, mod `modulus`."""
    return _native('close_pairs', values, modulus, within)


def check_capture(path: Path) -> list[str]:
    """Problems with what the guest sent: sequence numbers, ports or IP IDs
    a counter would have produced."""
    return _native('check_capture', path)


def available_port() -> str:
    return _native('available_port')


def reaped(pid: int, seconds: float) -> bool:
    return _native('reaped', pid, seconds)


def stop(pid: int, master: int) -> None:
    # QEMU's serial console quits on Ctrl-A X; the runner exits with it.
    return _native('stop', pid, master)


def command_for(arguments: argparse.Namespace, root: Path) -> tuple[list[str], dict[str, str]]:
    return _native('command_for', arguments, root)


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

    _native('boot_message', arguments)
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execvpe(command[0], command, environment)

    transcript = bytearray()
    deadline = time.monotonic() + arguments.timeout
    finished_at: float | None = None
    state = {'transcript': transcript, 'deadline': deadline, 'finished_at': finished_at}
    try:
        _native('capture', state, pid, master)
    finally:
        stop(pid, master)
        os.close(master)

    return _native('report', state, arguments)


if __name__ == "__main__":
    raise SystemExit(main())

