#!/usr/bin/env python3
"""Cross-compile VOffice Calc and Writer as native Vinix ui2 clients."""

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
from runpy import run_path

from build_cache import _native


APPS = {
    "calc": "cmd/excel",
    "writer": "cmd/word",
}
CACHE_VERSION = 2
CACHE_STATE_NAME = ".vinix-voffice-build-state.json"
EXCLUDED_UI2_SUBDIRS = {"appkit"}
OFFICE_SOURCE_SUFFIXES = (".c", ".h", ".m", ".v")
OFFICE_IMPORT_RE = re.compile(r"\boffice\.([a-zA-Z_][a-zA-Z0-9_]*)")


_binding = run_path(str(Path(__file__).resolve().parents[2] / "tools/_package_store_native.py"))
_Popen = subprocess.Popen
_controller = _binding["_host"].Controller(Path(__file__).with_name("office_query.v"), "VINIX_OFFICE_QUERY",
    process=lambda *args, **kwargs: _Popen(*args, start_new_session=True, **kwargs))


def _office_call(operation, arguments):
    return _binding["call"](operation, arguments, globals(), controller=_controller)


def run(command, quiet=False):
    return _office_call('run', (command, quiet))


def ignored_office_source(path: Path) -> bool:
    return _native.request("ignored_source", path=_native.wire(path), policy="office")


def office_source_files(source: Path):
    return [Path(os.fsdecode(bytes.fromhex(path))) for path in
            _native.request("office_source_files", path=_native.wire(source))]


def imported_office_modules(args, app_name: str):
    APPS[app_name]
    return _native.request("office_modules", office=_native.wire(args.office_source),
                           app=_native.wire(app_name))


def shared_build_key(args, vroot: Path):
    return _native.request("office_shared", repo=_native.wire(args.repo),
                           builder=_native.wire(Path(__file__)),
                           office=_native.wire(args.office_source), ui2=_native.wire(args.ui2_source),
                           v=_native.wire(args.v), vroot=_native.wire(vroot),
                           arch=_native.wire(args.arch), target=_native.wire(args.target),
                           clang=_native.wire(args.clang), strip=_native.wire(args.strip),
                           clang_headers=_native.wire(args.clang_resource_include),
                           sysroot=_native.wire(args.sysroot), gcclib=_native.wire(args.gcclib),
                           cc_shim=_native.wire(args.cc_shim) if args.cc_shim else "",
                           llvm=_native.wire(args.llvm_bin) if args.llvm_bin else "")


def app_build_key(args, shared_key: str, name: str):
    APPS[name]
    return _native.request("office_key", office=_native.wire(args.office_source),
                           shared=_native.wire(shared_key), app=_native.wire(name))


def load_build_state(output: Path):
    return _office_call('load_build_state', (output,))


def write_build_state(output: Path, shared_key: str, apps):
    return _office_call('write_build_state', (output, shared_key, apps))


def output_binary(output: Path, name: str) -> Path:
    return _office_call('output_binary', (output, name))


def usable_cached_binary(output: Path, name: str) -> bool:
    return _office_call('usable_cached_binary', (output, name))


def reset_directory(path: Path, protected):
    return _office_call('reset_directory', (path, protected))


def compiler_root(v: Path):
    return _office_call('compiler_root', (v,))


def cc_base(args, vroot: Path):
    return _office_call('cc_base', (args, vroot))


def mbedtls_sources(vroot: Path):
    return _office_call('mbedtls_sources', (vroot,))


def compile_mbedtls_source(args, vroot: Path, objects: Path, source: Path):
    return _office_call('compile_mbedtls_source', (args, vroot, objects, source))


def build_mbedtls(args, vroot: Path):
    return _office_call('build_mbedtls', (args, vroot))


def compile_app(args, vroot: Path, module_root: Path, tls_objects, name: str):
    return _office_call('compile_app', (args, vroot, module_root, tls_objects, name))


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--office-source", type=Path, required=True)
    parser.add_argument("--ui2-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--v", type=Path, required=True)
    parser.add_argument("--arch", choices=("x64", "arm64"), required=True)
    parser.add_argument("--clang", type=Path, required=True)
    parser.add_argument("--strip", type=Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--sysroot", type=Path, required=True)
    parser.add_argument("--gcclib", type=Path, required=True)
    parser.add_argument("--cc-shim", type=Path)
    parser.add_argument("--llvm-bin", type=Path)
    parser.add_argument(
        "--jobs", type=int, default=int(os.environ.get("VINIX_OFFICE_JOBS", "4"))
    )
    parser.add_argument(
        "--only",
        action="append",
        choices=tuple(APPS),
        default=[],
        help="build only one application (repeatable; for validation)",
    )
    return parser.parse_args()


def validate_inputs(args):
    return _office_call('validate_inputs', (args,))


def main():
    args = parse_args()
    return _office_call('main', (args,))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit("VOffice build failed: %s" % error)
