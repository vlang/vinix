#!/usr/bin/env python3
"""Compare explicit old/new translators' native WAKE_OP writes on Vinix."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from runpy import run_path
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import tarfile
import time

_native_request = run_path(str(Path(__file__).with_name("_native.py")))["request"]

REPO = Path(__file__).resolve().parents[2]


_wake = run_path(str(Path(__file__).with_name("_wake_native.py")))


def _wake_host(operation, *arguments):
    return _wake["host"](operation, globals(), *arguments)


def _wake_guest(operation, *arguments):
    return _wake["guest"](operation, globals(), *arguments)


def _wake_merge(left, right):
    return {**left, **right}


def _wake_copy(value):
    return {**value}


def _wake_capture(transcript, reaped, last, log, deadline, pid, master):
    return transcript, reaped, last, log, deadline, pid, master


def digest(path: Path) -> str:
    return _wake_host('digest', path)


def stop_guest(pid: int, master: int) -> bool:
    return _wake_guest('stop_guest', pid, master)


def verdict(transcript: bytes, reaped: bool) -> dict:
    return _native_request("wake", transcript, reaped=reaped)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-dir", required=True, type=Path)
    parser.add_argument("--old-translator", required=True, type=Path)
    parser.add_argument("--new-translator", required=True, type=Path)
    parser.add_argument("--base-root", type=Path, default=REPO / "build/dota2-vulkan/test/root")
    parser.add_argument("--runtime-root", type=Path)
    parser.add_argument("--boot-repo", type=Path, default=REPO)
    parser.add_argument("--signal-probe", type=Path, help="optional diagnostic-only fault observer")
    parser.add_argument("--cc", default="clang", help="host compiler with an x86-64 Linux target")
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--run", action="store_true", help="boot the prepared regression VM")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    if os.environ.get("VINIX_PRUNE_BUILD") != "0":
        parser.error("set VINIX_PRUNE_BUILD=0")
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    return _wake_host('main', args, parser)


if __name__ == "__main__":
    main()
