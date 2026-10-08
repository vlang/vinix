"""Import marshalling for the native V T6050 instruction-contract proofs.

Code bytes become explicit native-owned request data. The shared boundary is
synchronous; its owned JSON is copied and released before this call returns.
"""
from __future__ import annotations
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
        raise
