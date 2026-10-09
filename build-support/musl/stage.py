#!/usr/bin/env python3
"""Build and stage Vinix's ABI-compatible Alpine musl with bounded heap reuse."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
RELEASES = {
    "1.2.5": ("a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4", "musl-1.2.5-r11", "alpine"),
    "1.2.6": ("d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a", "musl-1.2.6-r2", "alpine-1.2.6"),
}


from runpy import run_path as _run_path

_musl_binding = _run_path(str(ROOT / "tools/_package_store_native.py"))
_musl_Popen = subprocess.Popen
_musl_controller = _musl_binding["_host"].Controller(Path(__file__).with_name("stage_query.v"), "VINIX_MUSL_QUERY",
    process=lambda *args, **kwargs: _musl_Popen(*args, start_new_session=True, **kwargs))


def _musl_call(operation, arguments):
    return _musl_binding["call"](operation, arguments, globals(), controller=_musl_controller)


def sha256(path: Path) -> str:
    return _musl_call('sha256', (path,))


def install(source: Path, target: Path, mode: int) -> None:
    return _musl_call('install', (source, target, mode))


def replace_link(target: Path, destination: str) -> None:
    return _musl_call('replace_link', (target, destination))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", required=True, choices=["x86_64", "aarch64"])
    parser.add_argument("--staging", required=True, type=Path)
    parser.add_argument("--build-dir", type=Path,
                        default=Path(os.environ.get("VINIX_MUSL_BUILD_DIR", ROOT / "build/musl")))
    parser.add_argument("--cc", help="target Linux C compiler command")
    parser.add_argument("--extra-patch", type=Path, action="append", default=[],
                        help="additional source patch for a private runtime, recorded in the build receipt")
    parser.add_argument("--max-page-size", type=int,
                        help="minimum ELF load-segment alignment for a private runtime")
    parser.add_argument("--require-export", action="append", default=[],
                        help="fail if a private runtime API is absent from the rebuilt libc")
    parser.add_argument("--jobs", type=int,
                        default=int(os.environ.get("NPROC", "8")))
    args = parser.parse_args()
    stage = args.staging.resolve()
    if stage == Path("/") or not (stage / f"lib/ld-musl-{args.arch}.so.1").is_file():
        parser.error("staging must be an existing Alpine root for the requested architecture")
    if args.jobs < 1:
        parser.error("jobs must be positive")
    if args.max_page_size is not None and (args.max_page_size < 4096 or
                                          args.max_page_size & (args.max_page_size - 1)):
        parser.error("max-page-size must be a power of two of at least 4096")
    if os.environ.get("VINIX_OPTIMIZED_MUSL", "1") == "0":
        print("    keeping Alpine's packaged musl (VINIX_OPTIMIZED_MUSL=0)")
        return 0
    retain = os.environ.get("VINIX_MUSL_RETAIN", "1")
    if retain not in ("0", "1"):
        parser.error("VINIX_MUSL_RETAIN must be 0 or 1")
    loader = stage / f"lib/ld-musl-{args.arch}.so.1"
    loader_bytes = loader.read_bytes()
    expected_machine = 62 if args.arch == "x86_64" else 183
    if loader_bytes[:6] != b"\x7fELF\x02\x01" or int.from_bytes(loader_bytes[18:20], "little") != expected_machine:
        parser.error("staged loader architecture does not match --arch")
    versions = re.findall(rb"\x00(1\.2\.[56])\x00", loader_bytes)
    if len(set(versions)) != 1:
        parser.error("only the pinned musl 1.2.5 and 1.2.6 loaders are supported")
    VERSION = versions[0].decode()
    # Newer Alpine 1.2.5 packages backport interfaces from 1.2.6. Preserve
    # those interfaces with the compatible 1.2.6 recipe rather than downgrade.
    if VERSION == "1.2.5" and b"posix_getdents\x00" in loader_bytes:
        VERSION = "1.2.6"
    SOURCE_SHA256, package, patch_directory = RELEASES[VERSION]
    (SOURCE_URL, cc, executable, machine, compiler_version, ar, ranlib, alpine_manifest, patches, patch_inputs, cflags, ldflags, optimization, manifest, key, cache) = _musl_call(
        "plan", (args, parser, VERSION, retain, SOURCE_SHA256, package, patch_directory))
    return _musl_call("publish", (args, stage, retain, loader, VERSION, SOURCE_SHA256, SOURCE_URL, cc, ar, ranlib, patch_inputs, cflags, ldflags, optimization, manifest, key, cache))


if __name__ == "__main__":
    raise SystemExit(main())
