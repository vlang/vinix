#!/usr/bin/env python3
"""Replay identical dhewm3 frames on ARM64 Vinix and Debian under QEMU/HVF.

Requires scripts/build-dhewm3-aarch64.sh, the X11/userland layers and a Debian arm64
kernel Image. --record records a shared demo on the selected OS first.
The Debian package root (base-files and busybox-static) is supplied with
--debian-root; the game, libc and Mesa runtime are deliberately shared.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import statistics
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
FPS = re.compile(rb"(\d+) frames rendered in ([\d.]+) seconds = ([\d.]+) fps")


import importlib.util as _import_util
import builtins as _builtins
_bindings_spec = _import_util.spec_from_file_location("dhewm_runner_bindings", ROOT / "build-support/android/_boot_native.py")
_bindings = _import_util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(ROOT / "build-support/dhewm3/runner_query.v", "VINIX_DHEWM_RUN_QUERY",
                                        process=_bindings._build_process)


def _query(operation, **values):
    return _bindings.query_call(_controller, {"operation": operation}, globals(), values=values)


def _call_name(name, *args, **kwargs):
    return _builtins.globals().get(name, _builtins.getattr(_builtins, name))(*args, **kwargs)


def _iter_items(records, key):
    return (row[key] for row in records)


_guest_spec = _import_util.spec_from_file_location("dhewm_guest_bindings", Path(__file__).with_name("_guest_native.py"))
_guest_native = _import_util.module_from_spec(_guest_spec)
_guest_spec.loader.exec_module(_guest_native)
_controller.process = _guest_native.process


def _guest_owner():
    return _guest_native.Owner(globals(), _query)


def _iter_contains(values, container):
    return (value in container for value in values)


def _iter_test(values, method):
    return (value for value in values if _builtins.getattr(value, method)())


def copy_layer(source: Path, dest: Path) -> None:
    return _query("copy_layer", source=source, dest=dest)


def prepare(args, work: Path) -> Path:
    return _query("prepare", args=args, work=work)


def image(root: Path, output: Path, linux: bool) -> None:
    return _query("image", root=root, output=output, linux=linux)


_native_copy_layer = copy_layer

def run_guest(args, work: Path, root: Path, os_name: str) -> dict:
    return _query("guest", args=args, work=work, root=root, os_name=os_name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--build", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--debian-kernel", type=Path)
    parser.add_argument("--debian-root", type=Path)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--os", choices=("vinix", "debian", "both"), default="both")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--record", action="store_true")
    modes.add_argument("--screenshot", action="store_true")
    parser.add_argument("--check-clock", action="store_true")
    modes.add_argument("--clock-only", action="store_true")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    return _query("main", args=args, parser=parser)


if __name__ == "__main__":
    main()
