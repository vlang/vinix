#!/usr/bin/env python3
"""Render in Vinix through VirtIO/VirGL and KekVM's host GPU backend."""

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


SMOKE_PASS_LINE = re.compile(rb"(?:^|\r*\n)VINIX_VIRGL_VM_PASS")
SMOKE_FAIL_LINE = re.compile(rb"(?:^|\r*\n)VINIX_VIRGL_VM_FAIL:[0-9]+")
DESKTOP_PASS_LINE = re.compile(
    rb"(?:^|\r*\n)VINIX_GPU_DESKTOP_VM_PASS\r*(?:\n|$)"
)
DESKTOP_FAIL_LINE = re.compile(
    rb"(?:^|\r*\n)VINIX_GPU_DESKTOP_VM_FAIL:[0-9]+\r*(?:\n|$)"
)
RENDERER = re.compile(rb"GL_RENDERER=[^\r\n]*virgl[^\r\n]*Apple", re.IGNORECASE)
DESKTOP_RENDERER = re.compile(
    rb"vinix-desktop: GPU presentation enabled on [^\r\n]*virgl[^\r\n]*Apple",
    re.IGNORECASE,
)
DESKTOP_STAGE = re.compile(rb"vinix-desktop: GPU init: ([^\r\n]+)")
DESKTOP_REQUIRED_STAGES = (
    b"entered main",
    b"using captured arguments without slicing",
    b"command line parsed",
    b"first frame ready; entering graphics mode",
    b"first canvas presented",
)
DESKTOP_READY = b"vinix-desktop: ready"
PIXELS = b"gl-triangle-agx: hardware frame rendered successfully"
VIRGL_PASS = b"VINIX VIRGL RENDER TEST: PASS"
NETWORK_PASS = b"VINIX_VIRGL_NETWORK_PASS"
M1_HARDWARE_PASS = b"VINIX M1 AGX RENDER TEST: PASS"
FOUR_CPUS_ONLINE = b"smp: 4 CPUs online"


_LITERAL_CACHE = {}
_SLOT_KEYS = {name: sys.intern(name) for name in ('EIO', 'SIGKILL', 'SIGTERM', 'WEXITSTATUS', 'WIFEXITED', 'WIFSIGNALED', 'WNOHANG', 'WTERMSIG', 'X_OK', 'access', 'add', 'append', 'buffer', 'contains', 'copy', 'count', 'decode', 'environ', 'eq', 'errno', 'expanduser', 'extend', 'findall', 'flush', 'get', 'ior', 'is_', 'is_file', 'is_not', 'join', 'kill', 'killpg', 'lt', 'machine', 'monotonic', 'ne', 'parent', 'pop', 'read', 'resolve', 'returncode', 'run', 'search', 'select', 'setdefault', 'setitem', 'sleep', 'stderr', 'stdout', 'system', 'truediv', 'waitpid', 'write')}
_ATTRIBUTE, _TRUTH, _ITER, _REPR = getattr, bool, iter, repr
_namespace = globals
_frame = sys._getframe

import importlib.util as _loader
_spec = _loader.spec_from_file_location("virgl_guest_binding", Path(__file__).with_name("_native.py"))
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



def child_exit_code(status: int) -> int:
    return _native("child_exit_code", status)


def stop_child(pid: int, master: int) -> None:
    return _native("stop_child", pid, master)


def signal_child(pid: int, sig: signal.Signals) -> None:
    return _native("signal_child", pid, sig)


def qemu_path(root: Path) -> Path:
    return _native("qemu_path", root)


def check_host(root: Path) -> tuple[Path, str | None]:
    return _native("check_host", root)


def run_vm(root: Path, timeout: int, desktop_startup: bool) -> int:
    setup = _native("prepare", root, desktop_startup)
    if setup is None:
        return 2
    qemu, source_image, guest_init, pass_line, fail_line, _prepared = setup
    setup = None
    with tempfile.TemporaryDirectory(prefix="vinix-virgl-vm.") as scratch:
        environment, command = _native("command", root, qemu, source_image,
                                       guest_init, desktop_startup, scratch)
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
        state = {"transcript": transcript, "pass_seen": pass_seen,
                 "fail_seen": fail_seen, "shutdown_sent": shutdown_sent,
                 "status": status, "deadline": deadline}
        del deadline
        try:
            _native("capture", state, pid, master, pass_line, fail_line)
        finally:
            status = state["status"]
            if status is None:
                forced_stop = True
                stop_child(pid, master)
            os.close(master)
        result = _native("report", state, forced_stop, desktop_startup)
        if result:
            return result
    _native("success", desktop_startup)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.environ.get("VINIX_VIRGL_VM_TIMEOUT", "900")),
        help="maximum setup, boot and render time in seconds (default: 900)",
    )
    parser.add_argument(
        "--desktop-startup",
        action="store_true",
        help="run the full GPU compositor through its first presented frame",
    )
    arguments = parser.parse_args()
    if arguments.timeout <= 0:
        parser.error("--timeout must be positive")
    return run_vm(
        Path(__file__).resolve().parents[2],
        arguments.timeout,
        arguments.desktop_startup,
    )


if __name__ == "__main__":
    raise SystemExit(main())
