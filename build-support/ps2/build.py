#!/usr/bin/env python3
"""Build the pinned Iris PS2 interpreter and software GS for ARM64 musl."""
# SPDX-License-Identifier: MIT
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import runpy
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
REVISION = "c43cd7e6017656a067acf9a4749480ff35e6fb3a"
SOURCE_URL = f"https://codeload.github.com/allkern/iris/tar.gz/{REVISION}"
SOURCE_SHA256 = "6030d1870917afed3ce60eb2ee374d0c38e18ccc6f6ce60128af270e339b00a6"


_binding = runpy.run_path(str(ROOT / "tools/_package_store_native.py"))
_controller = _binding["_host"].Controller(SUPPORT / "build_query.v", "VINIX_PS2_BUILD_QUERY")

def _call(operation, *arguments):
    return _binding["call"](operation, arguments, globals(), controller=_controller)

def _worker(context):
    def compile_one(path: Path) -> tuple[Path, bytes]:
        return _call("compile_one", path, context)
    compile_one.__qualname__ = "main.<locals>.compile_one"
    return compile_one


def sha256(path: Path) -> str:
    return _call('sha256', path)


def fetch(path: Path) -> None:
    return _call('fetch', path)


def unpack(archive: Path, destination: Path) -> None:
    return _call('unpack', archive, destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ps2")
    parser.add_argument("--sysroot", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--llvm-bin", type=Path, default=Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")))
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 8))
    args = parser.parse_args()
    output, sysroot, llvm = args.output.resolve(), args.sysroot.resolve(), args.llvm_bin.resolve()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    return _call("main", args, parser, output, sysroot, llvm)


if __name__ == "__main__":
    main()
