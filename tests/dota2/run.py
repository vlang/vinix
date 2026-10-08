#!/usr/bin/env python3
"""Capture an actual Dota 2 launch on ARM64 Vinix; rendering needs visual review.

Uses an existing Vulkan probe root and a metadata-only, read-only game export.
No account data is copied. A live process or a desktop window is not a pass.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import pty
import re
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import threading
import time

REPO = Path(__file__).resolve().parents[2]
SOFTWARE_GL_DRIVERS = ("swrast_dri.so", "kms_swrast_dri.so")

_spec = importlib.util.spec_from_file_location("dota2_game_vm_native", Path(__file__).with_name("_game_vm_native.py"))
_vm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_vm)


def module(name: str, path: Path):
    return _vm.call('module', globals(), name, path)


_PREPARATION = None


def _preparation():
    global _PREPARATION
    if _PREPARATION is None:
        spec = importlib.util.spec_from_file_location("dota2_prepare_binding", Path(__file__).with_name("_prepare_native.py"))
        _PREPARATION = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_PREPARATION)
    return _PREPARATION


def sha256(path: Path) -> str:
    return _preparation().call("sha256", path)


def game_start_observed(transcript: bytes) -> bool:
    # Kernel messages from another CPU can split the launcher's first echo.
    # PID 1 emits ALIVE only after reading the saved game PID and kill -0
    # succeeds, so that later heartbeat also proves the process was launched.
    return _vm.call('game_start_observed', globals(), transcript)


class ExportReads:
    """Record actual disk read failures without changing the NBD response."""

    def __init__(self, export):
        return _vm.call('reads_init', globals(), self, export)

    def observe(self, offset: int, count: int) -> bytes:
        return _vm.call('reads_observe', globals(), self, offset, count)

    def report(self) -> dict:
        return _vm.call('reads_report', globals(), self)


def install(source: Path, target: Path) -> None:
    _preparation().call("install", source, target)


def stage_vulkan_query(gldriverquery: Path, root: Path) -> None:
    """Copy the actual optional Linux64 helper beside the supplied GL query."""
    _preparation().call("stage_vulkan_query", gldriverquery, root)


def probe_preloads(paths: list[Path]) -> tuple[list[dict], list[bytes]]:
    records, contents = _preparation().call("probe_preloads", iterable=paths)
    return ([{"source": _preparation()._untext(row["source"]), "sha256": row["sha256"],
              "guest_path": _preparation()._untext(row["guest_path"])} for row in records],
            [bytes.fromhex(value) for value in contents])


def trim_runtime(root: Path) -> None:
    _preparation().call("trim_runtime", root)


def refresh_runtime(args, root: Path) -> None:
    _preparation().call("refresh_runtime", root, namespace=args)


def complete_native_closure(root: Path, binaries: list[Path]) -> None:
    _preparation().call("complete_native_closure", root, sequence=binaries, repo=REPO)


def verify_sdk_closure(root: Path) -> None:
    _preparation().call("verify_sdk_closure", root)


def overlay_translator(source: Path, root: Path) -> None:
    _preparation().call("overlay_translator", source, root, repo=REPO)


def prepare(args, work: Path) -> tuple[Path, Path]:
    paths = _preparation().call("prepare", work, namespace=args, repo=REPO)
    return tuple(Path(_preparation()._untext(value)) for value in paths)


def screenshot(socket: Path, target: Path) -> bool:
    return _vm.call('screenshot', globals(), socket, target)


def stop_vm(pid: int, master: int) -> None:
    return _vm.call('stop_vm', globals(), pid, master)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-root", type=Path, default=REPO / "build/dota2-vulkan/test/root")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2/game-test")
    parser.add_argument("--desktop", type=Path, default=REPO / "build/vinix-desktop")
    parser.add_argument("--host-source", type=Path,
                        default=REPO / "build-support/xorg-server/winehost/core.v")
    parser.add_argument("--steamclient", type=Path,
                        default=REPO / "build-aarch64-steam/preseed-home/.local/share/Steam/steamrt64")
    parser.add_argument("--gldriverquery", type=Path,
                        default=REPO / "build-aarch64-steam/preseed-home/.local/share/Steam/ubuntu12_64/gldriverquery")
    parser.add_argument("--translator-staging", type=Path,
                        help="Overlay a native translator and its libraries at the standard guest paths")
    parser.add_argument("--export-state", type=Path, default=REPO / "build/dota2/linux-export")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--game-env", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--extra-preload", type=Path, action="append", default=[],
                        help="Copy a measured x86-64 loader probe into the guest preloads; repeatable")
    parser.add_argument("--extra-game-arg", action="append", default=[])
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--memory-mib", type=int, default=8192,
                        help="Guest RAM in MiB; translated software rendering can need more than 8 GiB")
    parser.add_argument("--capture-interval", type=int, default=60)
    parser.add_argument("--venus", action="store_true",
                        help="boot on KekVM's GPU so the game can render with the x86-64 Venus driver")
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if args.timeout <= 0 or args.capture_interval <= 0 or args.memory_mib <= 0:
        parser.error("Timeout, capture interval and memory must be positive")
    return _vm.call("boot", globals(), args)


if __name__ == "__main__":
    main()
