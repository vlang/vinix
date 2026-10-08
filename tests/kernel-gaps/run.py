#!/usr/bin/env python3
"""Compile a static syscall test and check its verdict on an isolated QEMU boot."""

from __future__ import annotations

import argparse
import errno
import os
from pathlib import Path
import platform
import pty
import select
import shutil
import signal
import socket
import subprocess
import tarfile
import tempfile
import time
import runpy


ROOT = Path(__file__).resolve().parents[2]


import importlib.util
_spec = importlib.util.spec_from_file_location("kernel_gap_native", Path(__file__).with_name("_native.py"))
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)


def stop(pid: int, master: int, state: Path, drain) -> None:
    return _native.call("stop", {"pid": pid, "master": master, "state": str(state)},
                        globals(), {"drain": drain})


_native_stop = stop


def boot(command: list[str], env: dict[str, str], state: Path,
         expected: list[str], failures: list[str], timeout: int) -> int:
    return _native.call("boot", {"state": str(state), "native_stop": stop is _native_stop},
                        globals(), {"command": command, "env": env, "state": state,
                        "expected": expected, "failures": failures, "timeout": timeout,
                        "owned": True})


def verdict_policy(expected: list[str], failures: list[str], expect_panic: bool) -> tuple[list[str], list[str]]:
    """Keep negative boot tests opt-in and reject entry into userspace."""
    return tuple(_native.call("policy", {}, globals(),
                              {"expected": expected, "failures": failures, "panic": expect_panic}))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--source", type=Path)
    input_group.add_argument("--prebuilt-init", type=Path,
                             help="Use an already compiled guest init executable")
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--kernel-dir", type=Path, default=ROOT / "kernel")
    parser.add_argument("--expect", action="append", required=True)
    parser.add_argument("--fail", action="append", default=[])
    parser.add_argument("--expect-panic", action="store_true",
                        help="Negative boot test: require a panic and the requested verdicts")
    parser.add_argument("--no-network", action="store_true",
                        help="Disable the guest NIC for deterministic allocation measurements")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--state-dir", type=Path)
    args = parser.parse_args()
    options = {name: str(value) if isinstance(value, Path) else value
               for name, value in vars(args).items()}
    options["root"] = str(ROOT)
    return _native.call("main", options, globals(), {"parser": parser, "timeout": args.timeout, "options": args})


if __name__ == "__main__":
    raise SystemExit(main())
