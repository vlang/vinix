#!/usr/bin/env python3
"""Check the compatibility preload with immutable native Android fixtures."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]


import builtins as _builtins
import operator as _operator
_bindings_spec = importlib.util.spec_from_file_location('android_runtime_vm_bindings', ROOT / 'build-support/android/_boot_native.py')
_bindings = importlib.util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_process_spec = importlib.util.spec_from_file_location('android_runtime_vm_process', Path(__file__).with_name('_run_native.py'))
_process = importlib.util.module_from_spec(_process_spec)
_process_spec.loader.exec_module(_process)
_controller = _bindings._host.Controller(ROOT / 'build-support/android/runtime-vm-query.v', 'VINIX_ANDROID_RUNTIME_VM_QUERY',
                                        process=lambda *args, **kwargs: _process._Controller(*args, start_new_session=True, **kwargs))


def _query(operation, **values):
    return _bindings.query_call(_controller, {'operation': operation}, globals(), values=values)


def _call_name(name, *args, **kwargs):
    return _builtins.globals().get(name, _builtins.getattr(_builtins, name))(*args, **kwargs)


def _invoke_existing(target, *args, **kwargs):
    try:
        return target(*args, **kwargs)
    except BaseException:
        del target, args, kwargs
        raise


def _iter_project_test(values, name, method):
    return (_operator.truediv(value, name) for value in values
            if _builtins.getattr(_operator.truediv(value, name), method)())


def load(name, path):
    return _query('load', name=name, path=path)


def digest(path):
    return _query('digest', path=path)


_native_load, _native_digest = load, digest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--kernel", type=Path, required=True)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), default="aarch64")
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--native-root", type=Path)
    parser.add_argument("--baseline", type=Path, help="Frozen original C implementation, outside maintained source")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    work = args.work.resolve()
    if work.exists() or args.timeout <= 0:
        parser.error("use a fresh work directory and positive timeout")
    return _query('main', args=args, parser=parser, work=work)


if __name__ == "__main__":
    main()
