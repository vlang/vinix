"""Compatibility fixture helper for recovery tests; DER encoding lives in V."""
from _native_extract import query

def der(tag: int, value: bytes) -> bytes:
    return query(value, "der_encode", tag=tag)["data"]
