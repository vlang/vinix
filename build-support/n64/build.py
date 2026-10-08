#!/usr/bin/env python3
"""Build pinned paraLLEl-N64 with interpreters and synchronous software RDP."""
# SPDX-License-Identifier: MIT
import argparse
from concurrent.futures import ThreadPoolExecutor
import functools
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import runpy
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
REVISION = "ef73c7e6fa356262f88e05f85cdfad092f8f90e0"
SOURCE_URL = f"https://codeload.github.com/libretro/parallel-n64/tar.gz/{REVISION}"
SOURCE_SHA256 = "0be08e52bb9a759253b802a546a699dc5cc8e2799f9234e45e64550b09ffc396"
ZLIB_REVISION = "51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf"
ZLIB_URL = f"https://codeload.github.com/madler/zlib/tar.gz/{ZLIB_REVISION}"
ZLIB_SHA256 = "d9e270d46252734aa49770fbc544125391617956266f220bd63216c834f3a522"
PATCH_VERSION = "vinix-interpreter-5"


_binding = runpy.run_path(str(ROOT / "tools/_package_store_native.py"))
_controller = _binding["_host"].Controller(SUPPORT / "build_query.v", "VINIX_N64_BUILD_QUERY")


def _call(operation, arguments):
    return _binding["call"](operation, arguments, globals(), controller=_controller)


def sha256(path: Path) -> str:
    return _call("sha256", [path])


def fetch(path: Path, url: str = SOURCE_URL, digest: str = SOURCE_SHA256) -> None:
    return _call("fetch", [path, url, digest])


def unpack(archive: Path, destination: Path) -> None:
    return _call("unpack", [archive, destination])


def replace(path: Path, before: str, after: str) -> None:
    return _call("replace", [path, before, after])


def patch(source: Path) -> None:
    return _call("patch", [source])


def _compile_one(item, *, context):
    return _call("compile_one", [item, context])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/n64")
    parser.add_argument("--sysroot", type=Path, default=ROOT / "build-aarch64-userland/staging")
    parser.add_argument("--linux-headers", type=Path,
                        default=Path(os.environ.get("VINIX_AARCH64_LINUX_HEADERS",
                                                    str(ROOT / "build-aarch64-userland/sysroot/include"))))
    parser.add_argument("--llvm-bin", type=Path, default=Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin")))
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 8))
    parser.add_argument("--host", action="store_true", help="build a native host archive for emulator smoke tests")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    return _call("main", [args, parser])


if __name__ == "__main__":
    main()
