# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrowed library transport shared by native Dota guest workflows."""
import importlib.util
from types import FunctionType
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("dota_guest_library_bridge", _HERE / "_game_vm_native.py")
_bridge = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_bridge)
_bridge._controller = _bridge._gap._host.Controller(_HERE / "guest_vm_query.v", "VINIX_GUEST_VM_QUERY", process=_bridge._gap._Process)


def call(operation, namespace, *arguments):
    if operation == "steam-main":
        return _bridge.call("boot", namespace, operation, *arguments, namespace)
    return _bridge.call(operation, namespace, *arguments, namespace)


unpack_pair = _bridge.unpack_pair


def raise_error(error):
    raise error


def method_callable(namespace, owner, name, *arguments):
    def operation():
        return getattr(owner, name)(*arguments)
    template = lambda: operation()
    reader = FunctionType(template.__code__.replace(co_filename=namespace["__file__"]),
                          namespace, "<lambda>", closure=template.__closure__)
    reader.__qualname__ = "digest.<locals>.<lambda>"
    return reader


def mapping_copy(value):
    return {**value}


def tuple_value(value):
    return (*value,)


def truth_value(value):
    return True if value else False


def format_value(value):
    return f"{value}"


def attribute_value(owner, name):
    return getattr(owner, name)


def slice_value(*arguments):
    return slice(*arguments)


def iterate_value(value):
    return iter(value)


def native_iterator(namespace, operation, *arguments):
    def values():
        state = None
        while True:
            packet = call(operation, namespace, *arguments, state)
            state = packet["position"]
            if packet["done"]:
                return
            yield packet["value"]
    generator = values()
    generator.__name__ = "<genexpr>"
    generator.__qualname__ = "runtime_inputs.<locals>.<genexpr>"
    return generator


def set_attribute(owner, name, value):
    setattr(owner, name, value)
