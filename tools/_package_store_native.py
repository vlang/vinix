# SPDX-License-Identifier: GPL-2.0-or-later
"""Owned library calls for the native loopback package-store policy."""
import atexit
import contextlib
import ctypes
import importlib.util
import os
import subprocess
import tempfile
import threading
from pathlib import Path
import sys
from types import FunctionType

_ROOT = Path(__file__).resolve().parents[1]


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_host = _module("package_store_host", _ROOT / "build-support/native_host.py")
_wire = _module("package_store_wire", _ROOT / "build-support/android/_boot_native.py")
_controller = _host.Controller(_ROOT / "tools/package_store_query.v", "VINIX_PACKAGE_STORE_QUERY")


_library = None
_library_lock = threading.Lock()


def _entry(operation, key, first=None, second=None):
    global _library
    with _library_lock:
        if _library is None:
            path = os.environ.get("VINIX_PACKAGE_STORE_LIBRARY")
            if path is None:
                owner = tempfile.TemporaryDirectory(prefix="vinix-package-sdk-")
                try:
                    path = str(Path(owner.name) / ("library.dylib" if sys.platform == "darwin" else "library.so"))
                    subprocess.run([str(_ROOT / "build-support/build-v-host-library.sh"),
                                    str(_ROOT / "tools/package_sdk_library.v"), path,
                                    "-d", "cpython_package", "-d", "use_bundled_libgc"],
                                   check=True, stdout=subprocess.DEVNULL,
                                   env={**os.environ, "VINIX_HOST_PYTHON": sys.executable})
                    library = ctypes.PyDLL(path)
                except BaseException:
                    owner.cleanup()
                    raise
                atexit.register(owner.cleanup)
            else:
                library = ctypes.PyDLL(path)
            target = library.vinix_package_store_sdk
            target.argtypes = (ctypes.c_char_p, ctypes.c_uint64,
                               ctypes.py_object, ctypes.py_object)
            target.restype = ctypes.py_object
            _library = target
    return _library(operation, key, first, second)


def _double_kwargs(target, args, first, second):
    try:
        return target(*args, **first, **second)
    except BaseException:
        target = args = first = second = None
        raise


def _pair(value):
    try:
        first, second = value
        return first, second
    except BaseException:
        value = None
        raise


def _unbound(name):
    def unbound():
        if False:
            value = None
        return value
    return FunctionType(unbound.__code__.replace(co_varnames=(name,)), {})()


def _raise(error):
    try:
        raise error
    finally:
        error = None


def _raise_from(error, cause):
    try:
        raise error from cause
    finally:
        error = cause = None


def _raise_from_handled(error, cause):
    try:
        try:
            raise cause
        except BaseException:
            raise error from cause
    finally:
        error = cause = None


class _Owner:
    def __init__(self, key, owner):
        self.key, self.owner = key, owner

    def __exit__(self, *details):
        return _entry(b"owner_exit", self.key, self.owner, details)


_SYNTAX = {"double_kwargs": _double_kwargs, "pair": _pair, "unbound": _unbound,
           "owner": _Owner, "stack": contextlib.ExitStack, "raise": _raise,
           "raise_from": _raise_from, "raise_from_handled": _raise_from_handled}


def call(operation, arguments, namespace, *, controller=None):
    key, ids, errors = _entry(b"begin", 0, namespace, (tuple(arguments), _SYNTAX))
    try:
        result = (_controller if controller is None else controller).call(
            {"operation": operation, "arguments": ids},
            lambda name, row: _entry(b"primitive", key, name, row),
            pack=_wire._pack, unpack=_wire._unpack, errors=errors,
            cleanup=lambda: _entry(b"cleanup", key, sys.exc_info()),
            error_fields=lambda error: _entry(b"flags", key, error))
        return _entry(b"result", key, result)
    finally:
        _entry(b"finish", key)
