#!/usr/bin/env python3
"""Compare frozen C/V configuration goldens against actual ATL/androidfw objects."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, required=True)
p.add_argument("--kernel-dir", type=Path, required=True)
p.add_argument("--linux-host", help="Optional Lima ARM Linux host for an independent native run")
p.add_argument("--baseline-rev", default="8f7239d1")
a = p.parse_args()
state = a.state_dir.resolve()
state.mkdir(parents=True, exist_ok=False)


import builtins as _builtins
import importlib.util as _import_util
import operator as _operator
_bindings_spec = _import_util.spec_from_file_location('android_atl_bindings', Path(__file__).resolve().parents[2] / 'build-support/android/_boot_native.py')
_bindings = _import_util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_process_spec = _import_util.spec_from_file_location('android_atl_process', Path(__file__).with_name('_run_native.py'))
_process = _import_util.module_from_spec(_process_spec)
_process_spec.loader.exec_module(_process)
_controller = _bindings._host.Controller(Path(__file__).resolve().parents[2] / 'build-support/android/atl-controller-query.v',
                                        'VINIX_ANDROID_ATL_CONTROLLER_QUERY',
                                        process=lambda *args, **kwargs: _process._Controller(*args, start_new_session=True, **kwargs))


def _query(operation, **values):
    return _bindings.query_call(_controller, {'operation': operation, 'debug': __debug__}, _builtins.globals(), values=values)


def _publish(name, value):
    _builtins.globals()[name] = value


def _name_target(name):
    scope = _builtins.globals()
    if name in scope:
        return scope[name]
    try:
        return _builtins.getattr(_builtins, name)
    except _builtins.AttributeError:
        raise _builtins.NameError("name '" + name + "' is not defined") from None


class _Namespace:
    def __getattr__(self, name):
        return _name_target(name)


_namespace = _Namespace()


def _invoke_existing(target, *args, **kwargs):
    try:
        return target(*args, **kwargs)
    except _builtins.BaseException:
        del target, args, kwargs
        raise


def _assert_false():
    assert False


def _assert_message(value):
    assert False, value


def _iter_project_test(values, method):
    return (_operator.truediv(value, _name_target('name')) for value in values
            if _builtins.getattr(_operator.truediv(value, _name_target('name')), method)())


def _native_digest(path):
    return _query('digest', path=path)


_query('main')
