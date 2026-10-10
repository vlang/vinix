# SPDX-License-Identifier: GPL-2.0-or-later
"""Synchronous imported API and exception transport for the native stager."""
import atexit
import builtins as _builtins
import ctypes as _ctypes
import dataclasses
import importlib.util
import json
import os
import operator
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
_LOCK = threading.RLock()
_BINARY = None

_LIBRARY = None
_TAKE = None
_LIBRARY_LOCK = threading.Lock()
_LIBRARY_SUPPORT = (os, Path, subprocess, sys, tempfile, atexit)


def _entry(operation, *arguments):
    global _LIBRARY, _TAKE
    library_os, library_Path, library_process, library_sys, library_temp, library_exit = _LIBRARY_SUPPORT
    with _LIBRARY_LOCK:
        if _LIBRARY is None:
            library_path = library_os.environ.get("VINIX_DOTA_VULKAN_LIBRARY")
            if library_path is None:
                owner = library_temp.TemporaryDirectory(prefix="vinix-vulkan-sdk-")
                try:
                    library_path = _builtins.str(library_Path(owner.name) / ("library.dylib" if library_sys.platform == "darwin" else "library.so"))
                    library_process.run([_builtins.str(ROOT / "build-support/build-v-host-library.sh"),
                                    _builtins.str(ROOT / "build-support/dota2/vulkan_sdk_library.v"), library_path,
                                    "-d", "cpython_vulkan", "-d", "use_bundled_libgc"],
                                   check=True, stdout=library_process.DEVNULL,
                                   env={**library_os.environ, "VINIX_HOST_PYTHON": library_sys.executable})
                    library = _ctypes.PyDLL(library_path)
                except _builtins.BaseException:
                    owner.cleanup()
                    raise
                library_exit.register(owner.cleanup)
            else:
                library = _ctypes.PyDLL(library_path)
            target = library.vinix_vulkan_sdk
            target.argtypes = (_ctypes.c_char_p, _ctypes.py_object, _ctypes.py_object, _ctypes.py_object)
            target.restype = _ctypes.py_object
            take = library.vinix_vulkan_prepare_take
            take.argtypes = (_ctypes.py_object, _ctypes.c_int)
            take.restype = _ctypes.py_object
            _TAKE = take
            _LIBRARY = target
    pins = []
    try:
        return _LIBRARY(operation, _builtins.globals(), arguments, pins)
    finally:
        arguments = None


def _vulkan_invoke(target, values, keywords):
    try:
        return target(*values, **keywords)
    except _builtins.BaseException:
        target = values = keywords = None
        raise


def _vulkan_triplet(value):
    try:
        first, second, third = value
        return first, second, third
    except _builtins.BaseException:
        value = None
        raise


def _vulkan_raise(error):
    try:
        raise error
    finally:
        error = None


class ArgumentError(ValueError):
    pass


def _failure(failure, errors):
    return _entry(b"failure", failure, errors)

def query(operation, arguments, namespace):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_DOTA_VULKAN_QUERY")
            if override:
                _BINARY = override
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-vulkan-controller-"))
                try:
                    binary = directory / "query"
                    with tempfile.TemporaryDirectory(prefix="vinix-vulkan-compiler-", dir="/tmp") as scratch:
                        subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                        str(ROOT / "build-support/dota2/vulkan_query.v"),
                                        "--install-query", str(binary)], check=True,
                                       stdout=subprocess.DEVNULL, env={**os.environ, "TMPDIR": scratch})
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = str(binary)
        objects, errors, owners = [], [], {}

        def encode(value):
            if isinstance(value, Path):
                return {"path_hex": os.fsencode(value).hex()}
            if isinstance(value, str) and any(0xd800 <= ord(ch) <= 0xdfff for ch in value):
                return {"surrogate_text": value.encode("utf-8", "surrogatepass").hex()}
            if isinstance(value, bool):
                return value
            if isinstance(value, int):
                return {"integer": str(value)}
            if isinstance(value, float):
                return {"float": repr(value)}
            if dataclasses.is_dataclass(value):
                objects.append(value)
                return {"object": len(objects) - 1, "fields": encode(vars(value))}
            if isinstance(value, (tuple, list)):
                return [encode(item) for item in value]
            if isinstance(value, dict):
                if set(value) in ({"path_hex"}, {"object"}, {"object", "fields"}, {"integer"},
                                  {"float"}, {"tuple"}, {"set"}, {"mapping"}, {"dictionary"},
                                  {"filesystem_text"}, {"filesystem_map"}, {"surrogate_text"}):
                    return {"dictionary": {key: encode(item) for key, item in value.items()}}
                if any(not isinstance(key, str) or any(0xd800 <= ord(ch) <= 0xdfff for ch in key) for key in value):
                    return {"mapping": [[encode(key), encode(item)] for key, item in value.items()]}
                return {key: encode(item) for key, item in value.items()}
            if value is None or isinstance(value, (str, bool, int, float)):
                return value
            objects.append(value)
            return {"object": len(objects) - 1}

        def decode(value, borrowed=True):
            if isinstance(value, list):
                return [decode(item, borrowed) for item in value]
            if isinstance(value, dict):
                if set(value) == {"filesystem_text"}:
                    return os.fsdecode(bytes.fromhex(value["filesystem_text"]))
                if set(value) == {"surrogate_text"}:
                    return bytes.fromhex(value["surrogate_text"]).decode("utf-8", "surrogatepass")
                if set(value) == {"filesystem_map"}:
                    return {os.fsdecode(bytes.fromhex(key)): decode(item, borrowed) for key, item in value["filesystem_map"]}
                if set(value) == {"dictionary"}:
                    return {key: decode(item, borrowed) for key, item in value["dictionary"].items()}
                if set(value) == {"integer"}:
                    return int(value["integer"])
                if set(value) == {"float"}:
                    return float(value["float"])
                if set(value) == {"mapping"}:
                    return {decode(key, borrowed): decode(item, borrowed) for key, item in value["mapping"]}
                if set(value) == {"tuple"}:
                    return tuple(decode(item, borrowed) for item in value["tuple"])
                if set(value) == {"set"}:
                    return set(decode(item, borrowed) for item in value["set"])
                if borrowed and set(value) == {"path_hex"}:
                    return Path(os.fsdecode(bytes.fromhex(value["path_hex"])))
                if borrowed and set(value) in ({"object"}, {"object", "fields"}):
                    return objects[value["object"]]
                return {key: decode(item, borrowed) for key, item in value.items()}
            return value


        def primitive(row):
            kind = row["kind"]
            values = decode(row.get("arguments", []))
            keywords = decode(row.get("keywords", {}))
            if kind == "public":
                return namespace[row["name"]](*values, **keywords)
            if kind == "global":
                if "key" in row:
                    return namespace[row["name"]][row["key"]]
                if row["name"] not in namespace:
                    return namespace["__getattr__"](row["name"])
                return namespace[row["name"]]
            if kind == "method":
                return getattr(decode(row["target"]), row["name"])(*values, **keywords)
            if kind == "call":
                return decode(row["target"])(*values, **keywords)
            if kind == "attribute":
                return getattr(decode(row["target"]), row["name"])
            if kind == "keys":
                return list(decode(row["target"]))
            selected = _entry(b"select", kind)
            if selected == "retire":
                owner = owners.pop(id(values[0]))
                context = row.get("context")
                if context is None:
                    return bool(owner.__exit__(None, None, None))
                error = _failure(context, errors)
                traceback = error.__traceback__
                try:
                    raise error.with_traceback(traceback)
                except BaseException:
                    replay = error.__traceback__
                    error.__traceback__ = traceback
                    try:
                        return bool(owner.__exit__(type(error), error, traceback))
                    finally:
                        if error.__traceback__ is replay:
                            error.__traceback__ = traceback
            if selected == "context_exit":
                manager = decode(row["target"])
                context = row.get("context")
                if context is None:
                    manager.__exit__(None, None, None)
                    return False
                error = _failure(context, errors)
                traceback = error.__traceback__
                try:
                    raise error.with_traceback(traceback)
                except BaseException:
                    replay = error.__traceback__
                    error.__traceback__ = traceback
                    try:
                        return bool(manager.__exit__(type(error), error, traceback))
                    finally:
                        if error.__traceback__ is replay:
                            error.__traceback__ = traceback
            return _entry(b"primitive", kind, row, namespace, values, keywords, decode,
                          _vulkan_invoke, _vulkan_raise, owners, selected)


        child = subprocess.Popen([_BINARY], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 text=True, env=os.environ, restore_signals=False)
        try:
            metadata = {"operation": operation, "arguments": encode(arguments),
                        "repo_hex": os.fsencode(namespace["REPO"]).hex(),
                        "builder_hex": os.fsencode(namespace["__file__"]).hex(),
                        "python_hex": os.fsencode(sys.executable).hex(),
                        "platform": namespace["sys"].platform, "pid": os.getpid()}
            _entry(b"send", child, metadata)
            while True:
                line = child.stdout.readline()
                row = _entry(b"received", line, child, _vulkan_raise)
                if not _entry(b"contains", row, "callback"):
                    if _entry(b"contains", row, "error"):
                        failure = row["error"]
                        raise _failure(failure, errors)
                    # Public results contain data; only synchronous callbacks
                    # may borrow importer-owned Paths or API objects.
                    return decode(row["value"], borrowed=False)
                try:
                    reply = _entry(b"value", encode(primitive(row["callback"])))
                except BaseException as error:
                    reply = _entry(b"failed", errors, error)
                _entry(b"send", child, reply)
        finally:
            main_thread = threading.current_thread() is threading.main_thread()
            previous = signal.signal(signal.SIGINT, signal.SIG_IGN) if main_thread else None
            try:
                try:
                    try:
                        child.stdin.close()
                    finally:
                        try:
                            child.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            child.kill(); child.wait()
                        except BaseException:
                            child.kill(); child.wait(); raise
                finally:
                    try:
                        child.stdout.close()
                    finally:
                        for owner in owners.values():
                            owner.__exit__(*sys.exc_info())
            finally:
                if main_thread:
                    signal.signal(signal.SIGINT, previous)
