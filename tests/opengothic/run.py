#!/usr/bin/env python3
"""Play OpenGothic in a Vinix desktop window under QEMU/HVF.

Requires scripts/build-opengothic-aarch64.sh with --demo or --game, a desktop from
scripts/build-desktop-aarch64.sh --no-initramfs, and the X11 and userland layers. The
test starts a new game from the keyboard, lets the world render and fails if
the engine crashes or exits. It leaves a screenshot.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import pty
import re
import statistics
import json
import select
import shutil
import signal
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
MENU = b"Shader compilation took"
LOADING = b"Parsing object [MeshAndBsp"
# A new game plays the intro once its world is loaded. The test's copy of the
# game has none, so this line is the engine going on to the world itself.
WORLD = b"unable to locate video file"
FAILURES = (b"---crashlog(", b"KERNEL PANIC", b"OPENGOTHIC-GONE", b"VENUS-ABI-FAIL", b"VENUS-SMOKE-FAIL")
TOOLS = ("sh", "cat", "mkdir", "chmod", "sleep", "uname", "grep", "ps", "tail")


import runpy
_vm = runpy.run_path(str(Path(__file__).with_name("_native.py")))


def copy_layer(source: Path, dest: Path) -> None:
    return _vm['host']('copy_layer', globals(), source, dest)


def prepare(args, work: Path) -> Path:
    return _vm['host']('prepare', globals(), args, work)


def press(socket_path: Path, key: str, seconds: float = 0.12) -> None:
    return _vm['host']('press', globals(), socket_path, key, seconds)


def stop(pid: int, master: int) -> None:
    return _vm['guest']('stop', globals(), pid, master)


def run_guest(args, work: Path, root: Path) -> Path:
    return _vm['guest']('run_guest', globals(), args, work, root)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT, help="checkout holding the layers and scripts/run-aarch64.sh")
    parser.add_argument("--build", type=Path, help="OpenGothic build directory (default: REPO/build/opengothic)")
    parser.add_argument("--desktop", type=Path, help="cross-built desktop (default: build/vinix-desktop here)")
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--seconds", type=int, default=60, help="how long the world must render")
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--cpus", type=int, default=4)
    parser.add_argument("--venus", action="store_true", help="require native GPU acceleration in KekVM")
    parser.add_argument("--venus-runtime", type=Path, help="Venus staging tree (default: REPO/build-aarch64-venus/staging)")
    parser.add_argument("--warmup", type=int, default=10, help="discard initial gameplay frames")
    parser.add_argument("--min-fps", type=float, default=55, help="required median gameplay FPS with --venus")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    if not 1 <= args.cpus <= 8:
        parser.error("--cpus must be between 1 and 8")
    if args.seconds < 1 or args.warmup < 0 or args.min_fps <= 0 or args.timeout < 1:
        parser.error("durations and --min-fps must be positive; --warmup can be zero")
    return _vm["host"]("main", globals(), args, parser)


if __name__ == "__main__":
    main()
