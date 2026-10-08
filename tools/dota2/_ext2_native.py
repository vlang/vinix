# SPDX-License-Identifier: GPL-2.0-or-later
"""Retained Python objects and library calls for native ext2 construction."""
import builtins
import contextlib
import importlib.util
import itertools
import operator
from pathlib import Path
import subprocess
import sys
import types

_ROOT = Path(__file__).resolve().parents[2]
_Popen = subprocess.Popen


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_host = _module("ext2_builder_host", _ROOT / "build-support/native_host.py")
_wire = _module("ext2_builder_wire", _ROOT / "build-support/android/_boot_native.py")
_controller = _host.Controller(_ROOT / "tools/dota2/ext2_query.v", "VINIX_EXT2_BUILD_QUERY",
    process=lambda *args, **kwargs: _Popen(*args, start_new_session=True, **kwargs))
_defaults, _methods = {}, {}


def bind(namespace):
    _defaults.update((name, namespace[name]) for name in
        ("rounded", "scan", "flatten", "directory_data", "pointer_count", "backup_group", "build"))
    _methods.update((name, getattr(namespace["Builder"], name)) for name in
        ("allocate", "write", "address_tree", "add_node", "finish"))


def call(operation, arguments, namespace):
    objects, errors, owners = {}, [], {}
    stack = contextlib.ExitStack()

    class Owner:
        def __init__(self, value, function=None):
            self.value, self.function, self.active = value, function, True
        def __exit__(self, *error):
            if not self.active:
                return False
            self.active = False
            if self.function is not None:
                self.function(self.value)
                return False
            return self.value.__exit__(*error)

    def retain(value):
        key = str(len(objects))
        objects[key] = value
        return key

    def resolve(name):
        if name == "close_builder_fd":
            return lambda builder: namespace["os"].close(builder.fd)
        parts = name.split(".")
        value = {"builtins": builtins, "operator": operator, "itertools": itertools}.get(parts[0],
            namespace.get(parts[0], getattr(builtins, parts[0], None)))
        for part in parts[1:]:
            value = getattr(value, part)
        return value

    def value(row):
        kind, data = row
        return objects[data] if kind == "owner" else bytes.fromhex(data) if kind == "bytes" else data

    def retire(owner, record):
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

    def primitive(method, row):
        if method == "dispatch":
            arguments = [value(item) for item in row["args"]]
            if "owner" in row:
                receiver = objects[row["owner"]]
                target = getattr(receiver, row["name"])
                native = (isinstance(target, types.MethodType) and target.__self__ is receiver
                          and target.__func__ is _methods.get(row["name"]))
                native_arguments = [receiver, *arguments]
            else:
                target = resolve(row["name"])
                native = target is _defaults.get(row["name"])
                native_arguments = arguments
            return {"native": native, "target": retain(target),
                    "arguments": [retain(item) for item in native_arguments]}
        if method == "function":
            target = getattr(objects[row["owner"]], row["name"]) if "owner" in row else resolve(row["name"])
            result = target(*[value(item) for item in row.get("args", [])],
                **{key: value(item) for key, item in row.get("kwargs", {}).items()}) if callable(target) else target
            return result if row.get("data") else retain(result)
        if method == "attribute":
            return retain(getattr(objects[row["owner"]], row["name"]))
        if method == "set_attribute":
            setattr(objects[row["owner"]], row["name"], value(row["value"]))
            return None
        if method == "literal":
            return retain(value(row["value"]))
        if method == "collection":
            return retain({"list": list, "tuple": tuple, "dict": dict}[row["kind"]](
                objects[key] for key in row["values"]))
        if method == "next":
            try:
                return {"done": False, "value": retain(next(objects[row["owner"]]))}
            except StopIteration:
                return {"done": True}
        if method == "unpack2":
            left, right = objects[row["owner"]]
            return [retain(left), retain(right)]
        if method == "enter":
            manager = objects[row["owner"]]
            result = manager.__enter__()
            owner = Owner(manager)
            owners[row["owner"]] = owner
            stack.push(owner)
            return retain(result)
        if method == "own":
            owner = Owner(objects[row["owner"]], resolve(row["function"]))
            owners[row["owner"]] = owner
            stack.push(owner)
            return None
        if method == "exit":
            return retire(owners.pop(row["owner"]), row["error"])
        if method == "raise":
            raise resolve(row["kind"])(*[value(item) for item in row["args"]])
        raise RuntimeError("unknown ext2 construction binding: " + method)

    result = _controller.call({"operation": operation, "arguments": [retain(item) for item in arguments]},
        primitive, pack=_wire._pack, unpack=_wire._unpack, errors=errors,
        cleanup=lambda: stack.__exit__(*sys.exc_info()))
    return objects[result] if result is not None else None
