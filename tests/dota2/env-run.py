#!/usr/bin/env python3
"""Compare concurrent getenv/setenv under old and fixed glibc on Vinix.

Only libc and its loader are copied from each supplied root. Both processes
run the same x86-64 test ELF, native translator and kernel, without preloads.
The old control must terminate with its original SIGSEGV; the new runtime must
finish every round with successful concurrent checks and native wait status 0.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from runpy import run_path
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile

_native_request = run_path(str(Path(__file__).with_name("_native.py")))["request"]

_spec = importlib.util.spec_from_file_location("dota_guest_vm", Path(__file__).with_name("_guest_vm_native.py"))
_vm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_vm)

REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIBC_LIMIT = 4 * 1024 * 1024
ROUNDS = 32
VARIABLES = 1000


def digest(path: Path) -> str:
    return _vm.call("env-digest", globals(), path)


def elf_input(path: Path, machine: int, limit: int = LIBC_LIMIT) -> dict:
    return _vm.call("env-elf_input", globals(), path, machine, limit)


def runtime_inputs(root: Path) -> dict:
    return _vm.call("env-runtime_inputs", globals(), root)


def install_pin(record: dict, destination: Path) -> None:
    return _vm.call("env-install_pin", globals(), record, destination)


def verdict(transcript: str, harness_status: int) -> dict:
    return _native_request("environment", transcript.encode("utf-8", "surrogatepass"),
                           harness_zero=harness_status == 0)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True, help="Fresh fixture directory")
    parser.add_argument("--old-glibc-root", type=Path, required=True,
                        help="Unfixed glibc root containing libc and its matching loader")
    parser.add_argument("--new-glibc-root", type=Path, required=True,
                        help="Fixed glibc root containing libc and its matching loader")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--translator", type=Path,
                        default=REPO / "build/dota2-qemu/staging/usr/bin/qemu-x86_64")
    parser.add_argument("--native-cc", default=str(REPO / "build/dota2-qemu/aarch64-cc"))
    parser.add_argument("--cc", default="clang", help="Existing Linux x86-64 cross compiler")
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    if work.exists():
        parser.error("Use a fresh work directory to preserve previous evidence")
    return _vm.call("env-main", globals(), args, parser, work)


if __name__ == "__main__":
    main()
