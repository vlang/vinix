#!/usr/bin/env python3
"""Boot one machine process and enforce the reboot-persistence result.

Unlike the core regression, this is a single QEMU process: the guest resets
itself with reboot(2), so the kernel's shutdown path -- not a second launch --
is what has to get the pending write to the disk.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import platform
import pty
import runpy
import select
import signal
import shutil
import socket
import subprocess
import sys
import tarfile
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


_LITERAL_CACHE = {}
_SLOT_KEYS = {name: sys.intern(name) for name in ('AF_INET', 'ArgumentParser', 'DEVNULL', 'SIGKILL', 'SIGTERM', 'SOCK_STREAM', 'USTAR_FORMAT', 'WNOHANG', 'add', 'add_argument', 'arch', 'bind', 'buffer', 'chdir', 'close', 'copy', 'copyfile', 'count', 'environ', 'execve', 'extractall', 'f_builtins', 'flush', 'fork', 'get', 'getsockname', 'hexdigest', 'init', 'initramfs', 'insert', 'join', 'killpg', 'mkdir', 'monotonic', 'open', 'parent', 'parents', 'parse_args', 'pop', 'read', 'read_bytes', 'resolve', 'run', 'run_path', 'select', 'setdefault', 'sha256', 'sleep', 'socket', 'state_dir', 'stderr', 'stdout', 'system', 'timeout', 'truncate', 'waitpid', 'which', 'with_name', 'write', 'write_bytes', 'write_text')}
_ATTRIBUTE, _TRUTH, _ITER, _REPR, _SLICE = getattr, bool, iter, repr, slice
_namespace = globals
_frame = sys._getframe

import importlib.util as _loader
_spec = _loader.spec_from_file_location("reboot_guest_binding", Path(__file__).with_name("_native.py"))
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




def _mapping(value):
    try:
        return {**value}
    finally:
        value = None


def _RAISE(error):
    try:
        raise error
    finally:
        error = None


def _failure_cell(state, key, value):
    cells = state.setdefault("_failure_cells", {})
    cell = cells.setdefault(key, [None])
    cell[0] = value
    return cell


def _failure_candidates(cell, markers):
    try:
        return (_native("contains_marker", cell[0], marker) for marker in markers)
    finally:
        markers = None


def available_port() -> str:
    return _native("available_port")


def gone(pid: int, master: int, seconds: float) -> bool:
    return _native("gone", pid, master, seconds)


def stop_child(pid: int, master: int) -> None:
    return _native("stop_child", pid, master)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    parser.add_argument("--init", required=True, type=Path)
    parser.add_argument("--initramfs", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    arguments = parser.parse_args()

    root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", Path(__file__).resolve().parents[2]))
    arguments.state_dir.mkdir(parents=True, exist_ok=True)

    _state = {name: None for name in ('parser', 'arguments', 'root', 'environment', 'command', 'archive', 'stream', 'isoenv', 'seed', 'name', 'disk', 'helper_path', 'debugfs', 'qemu', 'firmware', 'pid', 'master', 'transcript', 'finished', 'deadline', 'waited', '_', 'readable', 'chunk', 'recent', 'text')}
    _state.update({"parser": parser, "arguments": arguments, "root": root})
    _native("prepare", _state)
    environment, command = _state["environment"], _state["command"]

    print("==> Booting; the guest restarts itself with reboot(2)")
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execve(command[0], command, environment)

    transcript = bytearray()
    finished = False
    deadline = time.monotonic() + arguments.timeout
    _state.update({"pid": pid, "master": master, "transcript": transcript,
                   "finished": finished, "deadline": deadline})
    del transcript, finished, deadline
    try:
        _native("capture", _state, pid, master)
    finally:
        stop_child(pid, master)
        os.close(master)

    return _native("report", _state)


if __name__ == "__main__":
    raise SystemExit(main())
