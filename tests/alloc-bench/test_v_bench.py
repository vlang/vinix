#!/usr/bin/env python3
"""Compare portable benchmark semantics with immutable C, including rollback."""
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
ALIASES = {name: "vab_fixture_" + name for name in (
    "malloc", "free", "mmap", "munmap", "pipe", "close", "clock_gettime",
    "clock_getres", "uname", "sysconf")}
ALIASES["clock_gettime"] = "vab_fixture_clock_gettime"
ALIASES["clock_getres"] = "vab_fixture_clock_getres"


import builtins as _builtins
import operator as _operator
import importlib.util as _import_util
_spec = _import_util.spec_from_file_location('benchmark_bindings', ROOT / 'build-support/android/_boot_native.py')
_bindings = _import_util.module_from_spec(_spec)
_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(HERE / 'test-query.v', 'VINIX_BENCH_TEST_QUERY', process=_bindings._build_process)


def _query(operation, _values=None, **values):
    values = values if _values is None else _values
    class Borrowed:
        def call(self, request, primitive, **options):
            def binding(method, row):
                if method == 'consume_argument':
                    del values[row['name']]
                    return None
                return primitive(method, row)
            return _controller.call(request, binding, **options)
    return _bindings.query_call(Borrowed(), {'operation': operation, 'debug': __debug__}, _builtins.globals(), values=values)


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


def _fstring(value):
    return f'{value}'


def _filter_prefixes():
    return ('-L', '-l', '-fuse-ld=')


def _define(key, value):
    return f'-D{key}={value}'


def _sysroot(value):
    return f'--sysroot={value}'


def _library(value):
    return f'-L{value}/lib'


def _assert_false():
    assert False


def _assert_message(value):
    assert False, value


def build(work, flags, arch, original=None, model=False, guest=False):
    return _query('build', work=work, flags=flags, arch=arch, original=original, model=model, guest=guest)


def invoke(exe, args, mode="none", index=1):
    return _query('invoke', exe=exe, args=args, mode=mode, index=index)


def normalize(contents, help_text=False):
    values = {'contents': contents, 'help_text': help_text}
    del contents, help_text
    return _query('normalize', _values=values)


def compare(v_exe, c_exe, work):
    return _query('compare', v_exe=v_exe, c_exe=c_exe, work=work)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host-arch", choices=("arm64", "amd64"), default="arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")
    p.add_argument("--arch", choices=("aarch64", "x86_64"))
    p.add_argument("--state-dir", type=Path)
    p.add_argument("--original-reference", type=Path)
    p.add_argument("--kernel-dir", type=Path)
    p.add_argument("--guest-state-dir", type=Path)
    p.add_argument("--model", action="store_true", help="controlled clock and fault provider; no timing claim")
    a = p.parse_args()
    if a.arch and (not a.kernel_dir or not a.guest_state_dir):
        p.error("--arch requires --kernel-dir and --guest-state-dir")
    return _query('main', args=a)


if __name__ == "__main__":
    main()
