#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compile the production display-hotplug policy and its independent V oracle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


import importlib.util as _import_util
from sys import _getframe as _frame
_literal_cache = {}
_ATTRIBUTE = getattr
_TRUTH = bool
_ITER = iter
_FORMAT = lambda value: f"{value}"
_list_literal = lambda *values: [*values]
_dictionary = lambda *pairs: {key: value for key, value in pairs}
_tuple = lambda *values: values
_spec = _import_util.spec_from_file_location('_hotplug_binding', HERE / '_native.py')
_binding = _import_util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)

def _policy(operation, state):
    return _binding.call(operation, globals(), _frame(1).f_builtins, state)

def _compile_flags(flags):
    return [f for f in flags if not f.startswith(("-L", "-l", "-fuse-ld="))]

def _object_paths(objects):
    return list(map(str, objects))

def _no_allocators(imports):
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|aligned_alloc|posix_memalign|memdup|new_array\w*|v_malloc)\b", imports), imports

def build(work, arch, flags, original=None, guest=False):
    state = {name: None for name in ('work', 'arch', 'flags', 'original', 'guest', 'helper', 'sources', 'objects', 'hashes', 'module', 'source', 'staged', 'text', 'fixture_flags', 'fixture', 'compile_flags', 'imports', 'entry', 'executable', 'manifest')}
    state.update(work=work, arch=arch, flags=flags, original=original, guest=guest)
    del work, arch, flags, original, guest
    return _policy("build", state)


def _environment(leaks):
    return {**os.environ, "ASAN_OPTIONS": f"detect_leaks={leaks}:halt_on_error=1", "UBSAN_OPTIONS": "halt_on_error=1"}

def _validate(v):
    assert v.returncode == 0 and b"apple display hotplug state tests passed" in v.stdout, (v.returncode, v.stdout, v.stderr)
    assert not re.search(rb"runtime error|AddressSanitizer|LeakSanitizer", v.stderr)

def _same_result(c, v):
    assert (v.returncode, v.stdout, v.stderr) == (c.returncode, c.stdout, c.stderr), (c, v)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"))
    parser.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--original-reference", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--guest-state-dir", type=Path)
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    if args.arch and (not args.state_dir or (not args.build_only and (not args.kernel_dir or not args.guest_state_dir))):
        parser.error("native run needs --state-dir, --kernel-dir and --guest-state-dir")
    with tempfile.TemporaryDirectory(prefix="vinix-hotplug-") as directory:
        state = {name: None for name in ('parser', 'args', 'directory', 'work', 'arch', 'sdk', 'cc', 'flags', 'sanitizer', 'binary', 'translated', 'leaks', 'environment', 'v', 'original', 'c')}
        state.update(parser=parser, args=args, directory=directory)
        del parser, args, directory
        return _policy("main", state)



if __name__ == "__main__":
    raise SystemExit(main())
