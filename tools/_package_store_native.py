# SPDX-License-Identifier: GPL-2.0-or-later
"""Owned library calls for the native loopback package-store policy."""
import builtins
import contextlib
import importlib.util
import operator
from pathlib import Path
import sys

_ROOT = Path(__file__).resolve().parents[1]


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_host = _module("package_store_host", _ROOT / "build-support/native_host.py")
_wire = _module("package_store_wire", _ROOT / "build-support/android/_boot_native.py")
_controller = _host.Controller(_ROOT / "tools/package_store_query.v", "VINIX_PACKAGE_STORE_QUERY")


def call(operation, arguments, namespace, *, controller=None):
    objects, errors, entered, closers = {}, [], {}, {}
    stack = contextlib.ExitStack()
    active = None

    class Owner:
        def __init__(self, manager, method=None):
            self.manager, self.method, self.active = manager, method, True
        def __exit__(self, *error):
            if not self.active:
                return False
            self.active = False
            if self.method:
                self.method(self.manager) if callable(self.method) else getattr(self.manager, self.method)()
                return False
            return self.manager.__exit__(*error)

    def retain(value):
        key = str(len(objects))
        objects[key] = value
        return key

    def resolve(name):
        components = name.split(".")
        value = {"builtins": builtins, "operator": operator}.get(components[0], namespace.get(components[0], getattr(builtins, components[0], None)))
        for part in components[1:]:
            value = getattr(value, part)
        return value

    def value(record):
        kind, data = record
        return objects[data] if kind == "owner" else bytes.fromhex(data) if kind == "bytes" else data

    def exit_owner(owner, record):
        if record is None:
            owner.__exit__(None, None, None)
            return False
        error = errors[record["binding_error"]]
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

    def library_primitive(method, row):
        if method == "function":
            target = getattr(objects[row["owner"]], row["name"]) if "owner" in row else resolve(row["name"])
            result = target(*[value(item) for item in row.get("args", [])], **{key: value(item) for key, item in row.get("kwargs", {}).items()}) if callable(target) else target
            return result if row.get("data") else retain(result)
        if method == "resolve":
            return retain(resolve(row["name"]))
        if method == "error_attribute":
            return retain(getattr(errors[row["error"]["binding_error"]], row["name"]))
        if method == "attribute":
            return retain(getattr(objects[row["owner"]], row["name"]))
        if method == "set_attribute":
            setattr(objects[row["owner"]], row["name"], value(row["value"]))
            return None
        if method == "literal":
            return retain(value(row["value"]))
        if method == "collection":
            entries = [objects[key] for key in row["values"]]
            return retain({"list": list, "tuple": tuple, "set": set}[row["kind"]](entries))
        if method == "next":
            try:
                return {"done": False, "value": retain(next(objects[row["owner"]]))}
            except StopIteration:
                return {"done": True}
        if method == "enter":
            manager = objects[row["owner"]]
            result = manager.__enter__()
            owner = Owner(manager)
            entered[row["owner"]] = owner
            stack.push(owner)
            return retain(result)
        if method == "exit":
            return exit_owner(entered.pop(row["owner"]), row["error"])
        if method == "own":
            owner = Owner(objects[row["owner"]], resolve(row["function"]) if "function" in row else row["method"])
            closers[row["owner"]] = owner
            stack.push(owner)
            return None
        if method == "close":
            return exit_owner(closers.pop(row["owner"]), row["error"])
        if method == "transfer":
            closers.pop(row["owner"]).active = False
            return None
        if method == "raise":
            error = namespace[row["kind"]](row["message"])
            if row.get("cause") is None:
                raise error
            cause = errors[row["cause"]["binding_error"]]
            try:
                raise cause
            except BaseException:
                raise error from cause
        raise RuntimeError("unknown package-store library call: " + method)

    def primitive(method, row):
        nonlocal active
        if method == "active_error":
            active = None if row["error"] is None else errors[row["error"]["binding_error"]]
            return None
        if active is None:
            return library_primitive(method, row)
        error, traceback = active, active.__traceback__
        try:
            raise error.with_traceback(traceback)
        except BaseException:
            replay = error.__traceback__
            error.__traceback__ = traceback
            try:
                return library_primitive(method, row)
            finally:
                if error.__traceback__ is replay:
                    error.__traceback__ = traceback

    keys = [retain(item) for item in arguments]
    result = (_controller if controller is None else controller).call({"operation": operation, "arguments": keys}, primitive,
        pack=_wire._pack, unpack=_wire._unpack, errors=errors,
        cleanup=lambda: stack.__exit__(*sys.exc_info()),
        error_fields=lambda error: {
            "os_error": isinstance(error, OSError), "missing": isinstance(error, FileNotFoundError),
            "tar_error": isinstance(error, namespace["tarfile"].TarError),
            "overlay": isinstance(error, namespace.get("OverlayError", ())),
            "source": isinstance(error, namespace.get("SourceSnapshotError", ())),
            "value_error": isinstance(error, ValueError),
            "called_process": isinstance(error, namespace["subprocess"].CalledProcessError),
            "shutil_error": isinstance(error, namespace["shutil"].Error),
            "clipboard": isinstance(error, namespace.get("ClipboardError", ())),
            "interrupt": isinstance(error, KeyboardInterrupt)})
    return objects[result] if result is not None else None
