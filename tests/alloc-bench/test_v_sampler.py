#!/usr/bin/env python3
"""Run the independent V ownership fixture against the production V sampler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
VERDICT = "Shared kernel allocator sampler: success, three-phase OOM/zeroing rollback, TSC failure and kext ABI passed"


import builtins as _builtins
import operator as _operator
import importlib.util as _import_util
_spec = _import_util.spec_from_file_location('sampler_bindings', ROOT / 'build-support/android/_boot_native.py')
_bindings = _import_util.module_from_spec(_spec)
_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(HERE / 'sampler-query.v', 'VINIX_SAMPLER_TEST_QUERY', process=_bindings._build_process)


def _query(operation, **values):
    return _bindings.query_call(_controller, {'operation': operation, 'debug': __debug__}, _builtins.globals(), values=values)


def _target(name):
    scope = _builtins.globals()
    if name in scope:
        return scope[name]
    try:
        return _builtins.getattr(_builtins, name)
    except _builtins.AttributeError:
        raise _builtins.NameError(f"name '{name}' is not defined") from None


def _invoke_actual(target, *args, **kwargs):
    try:
        return target(*args, **kwargs)
    except _builtins.BaseException:
        del target, args, kwargs
        raise


def _truth(value):
    return True if value else False


def _filter_prefixes():
    return ('-L', '-l', '-Wl,', '-fuse-ld=')


def _sysroot(value):
    return f'--sysroot={value}'


def _library(value):
    return f'-L{value}/lib'


def _assert_false():
    assert False


def _assert_message(value):
    assert False, value

def _varargs(arch):
    return f'varargs-{arch}.S'


def _none():
    return None


def build(work, arch, flags, original=None, guest=False):
    return _query('build', work=work, arch=arch, flags=flags, original=original, guest=guest)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
    p.add_argument("--arch", choices=("aarch64", "x86_64"), help="run the entire fixture in a native guest")
    p.add_argument("--state-dir", type=Path)
    p.add_argument("--original-reference", type=Path, help="materialized original C fixture for comparison")
    p.add_argument("--kernel-dir", type=Path)
    p.add_argument("--guest-state-dir", type=Path)
    a = p.parse_args()
    if a.arch and (not a.kernel_dir or not a.guest_state_dir):
        p.error("--arch requires --kernel-dir and --guest-state-dir")
    return _query('main', args=a)


if __name__ == "__main__":
    main()
