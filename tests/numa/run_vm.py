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


# Native policy borrows live operands; Python owns PTY fork/exec and finally.
import importlib.util as _import_util
from sys import _getframe as _frame
_spec = _import_util.spec_from_file_location("_numa_binding", Path(__file__).with_name("_native.py"))
_binding = _import_util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)
_LITERAL_CACHE = {}
_ATTRIBUTE = getattr
_TRUTH = bool
_FORMAT = lambda value: f"{value}"
_REPR = repr
_ITER = iter
_SLICE = slice
_tuple = lambda *values: values
_list = lambda *values: list(values)
_triple = lambda value: tuple(value)
_named = lambda *pairs: dict(pairs)


def _policy(operation, *arguments):
    return _binding.call(operation, globals(), _frame(1).f_builtins, *arguments)


def _missing_features(output):
    return [marker.decode("ascii") for marker in (*FEATURE_MARKERS, PASS_MARKER) if output.count(marker) != 1]


def _missing_kernel(output):
    return [marker.decode("ascii") for marker in KERNEL_MARKERS if marker not in output]


def _failures(output):
    return [marker.decode("ascii", errors="replace") for marker in FAIL_MARKERS if marker in output]


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
    b"QEMU NUMA PASS: getcpu reports the node of the CPU a thread is pinned to",
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

# Two nodes of one gigabyte, two CPUs each, one hop apart. scripts/run-aarch64.sh boots
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
    return _policy("exit_code", status)



def stop_child(pid: int, master: int) -> None:
    _policy("stop", pid, master)



def run_vm(
    root: Path,
    guest_init: Path,
    initramfs: Path,
    state_dir: Path,
    timeout: int,
) -> int:
    state_dir.mkdir(parents=True, exist_ok=True)
    state = {"root": root, "guest_init": guest_init, "initramfs": initramfs,
             "state_dir": state_dir, "timeout": timeout}
    environment, command = _policy("prepare", state)
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execve(command[0], command, environment)

    state.update(pid=pid, master=master)
    del environment, command, pid, master
    state["transcript"] = bytearray()
    state["status"] = None
    state["forced_stop"] = False
    state["shutdown_deadline"] = None
    state["deadline"] = time.monotonic() + timeout
    recent: bytes
    def snapshot(value):
        nonlocal recent
        recent = value
    def candidates():
        return (marker in recent for marker in FAIL_MARKERS)
    try:
        _policy("capture", state, state["pid"], state["master"], snapshot, candidates)
    finally:
        if state["status"] is None:
            state["forced_stop"] = True
            stop_child(state["pid"], state["master"])
        os.close(state["master"])
    return _policy("report", state)



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
