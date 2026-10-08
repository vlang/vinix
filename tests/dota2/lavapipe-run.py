#!/usr/bin/env python3
"""Compare unfixed and fixed Lavapipe null descriptor-set binding on Vinix.

Every driver runs the same x86-64 probe, Vulkan loader, glibc, translator and
kernel. Each control must bind ordinary sets correctly and terminate with
SIGSEGV in all three null-set modes, as Dota's local map did. The fixed driver
must store through the right descriptor slot in every mode.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MODES = ("bound", "null-set", "absent-layout", "absent-first-set")
LIBRARY_DIRECTORIES = ("usr/lib/x86_64-linux-gnu", "lib/x86_64-linux-gnu")
LIBRARY_LIMIT = 256 * 1024 * 1024

_spec = importlib.util.spec_from_file_location("dota2_lavapipe_native", Path(__file__).with_name("_lavapipe_native.py"))
_lava = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_lava)


def digest(path: Path) -> str:
    return _lava.call('digest', globals(), path)


def elf_input(path: Path, machine: int, limit: int = LIBRARY_LIMIT) -> dict:
    return _lava.call('elf_input', globals(), path, machine, limit)


def install_pin(record: dict, destination: Path) -> None:
    return _lava.call('install_pin', globals(), record, destination)


def needed(readelf: str, path: Path) -> list[str]:
    return _lava.call('needed', globals(), readelf, path)


def runtime_closure(readelf: str, runtime: Path, roots: list[Path]) -> dict:
    """Pin every library the loader and drivers need from the private runtime."""
    return _lava.call('runtime_closure', globals(), readelf, runtime, roots)


def verdict(transcript: str, harness_status: int, drivers: list[str]) -> dict:
    return _lava.call('verdict', globals(), transcript, harness_status, drivers)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True, help="Fresh fixture directory")
    parser.add_argument("--fixed", type=Path, required=True, help="Patched libvulkan_lvp.so")
    parser.add_argument("--control", type=Path, action="append", required=True,
                        help="Unfixed libvulkan_lvp.so; repeat for several controls")
    parser.add_argument("--runtime-root", type=Path,
                        default=REPO / "build/dota2-runtime/staging/usr/libexec/vinix-dota2/root",
                        help="Private x86-64 runtime with glibc, its loader and libvulkan.so.1")
    parser.add_argument("--vulkan-include", type=Path,
                        default=REPO / "build/dota2-runtime/mesa/source/include",
                        help="Vulkan headers, normally from the prepared Mesa source")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--translator", type=Path,
                        default=REPO / "build/dota2-qemu/staging/usr/bin/qemu-x86_64")
    parser.add_argument("--native-cc", default=str(REPO / "build/dota2-qemu/aarch64-cc"))
    parser.add_argument("--cc", default="clang", help="Existing Linux x86-64 cross compiler")
    parser.add_argument("--readelf", default=shutil.which("llvm-readelf") or
                        "/opt/homebrew/opt/llvm/bin/llvm-readelf")
    parser.add_argument("--memory-mib", type=int, default=4096)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    return _lava.call("main", globals(), args, parser)


if __name__ == "__main__":
    main()
