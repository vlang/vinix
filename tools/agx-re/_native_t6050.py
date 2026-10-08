"""Import marshalling for the native V T6050 instruction-contract proofs.

Code bytes become explicit native-owned request data. The shared boundary is
synchronous; its owned JSON is copied and released before this call returns.
"""
from __future__ import annotations
import json
import struct
from _native_extract import query


def _encode(value):
    if isinstance(value, (bytes, bytearray)):
        return {"$bytes": bytes(value).hex()}
    if isinstance(value, dict):
        return {str(key): _encode(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [_encode(item) for item in value]
    return value


def contract(name, functions, **parameters):
    return _contract(b"", name, functions, parameters)


def image_contract(name, image, functions, **parameters):
    """Borrow image bytes only for the synchronous native reader call."""
    return _contract(image, name, functions, parameters)



def _node(value):
    return {"properties": {name: {"data": _encode(prop.data), "flags": prop.flags}
                           for name, prop in value.properties.items()},
            "children": [_node(child) for child in value.children]}


def tree_contract(name, root, **parameters):
    if "pmp_wrappers" in parameters:
        parameters["pmp_wrappers"] = {
            role: [path, _node(node)]
            for role, (path, node) in parameters["pmp_wrappers"].items()
        }
    return _contract(b"", name, {}, {"root": _node(root), **parameters})


def _contract(image, name, functions, parameters):
    try:
        return query(image, "t6050:" + name,
                     functions=_encode(functions), **_encode(parameters))
    except ValueError as error:
        message = str(error)
        if message.startswith("KeyError: "):
            raise KeyError(message.removeprefix("KeyError: ")) from None
        if message.startswith("TypeError: "):
            raise TypeError(message.removeprefix("TypeError: ")) from None
        if message.startswith("struct.error: "):
            raise struct.error(message.removeprefix("struct.error: ")) from None
        if message.startswith("OverflowError: "):
            raise OverflowError(message.removeprefix("OverflowError: ")) from None
        if message.startswith("UnicodeDecodeError: "):
            fields = json.loads(message.removeprefix("UnicodeDecodeError: "))
            raise UnicodeDecodeError(fields["encoding"], bytes.fromhex(fields["object"]),
                                     fields["start"], fields["end"], fields["reason"]) from None
        raise
