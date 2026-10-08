"""Narrow import adapter for the native V G17 decoding and Mach-O core."""
import struct
import json
from _native_extract import query as _native_query


def _query(data, operation, **options):
    try:
        return _native_query(data, "g17:" + operation, **options)
    except ValueError as error:
        message = str(error)
        if message.startswith("struct.error: "):
            raise struct.error(message.removeprefix("struct.error: ")) from None
        if message.startswith("IndexError: "):
            raise IndexError(message.removeprefix("IndexError: ")) from None
        if message.startswith("KeyError: "):
            raise KeyError(message.removeprefix("KeyError: ")) from None
        if message.startswith("TypeError: "):
            raise TypeError(message.removeprefix("TypeError: ")) from None
        if message.startswith("AttributeError: "):
            raise AttributeError(message.removeprefix("AttributeError: ")) from None
        if message.startswith("OverflowError: "):
            raise OverflowError(message.removeprefix("OverflowError: ")) from None
        if message.startswith("UnicodeDecodeError: "):
            record = json.loads(message.removeprefix("UnicodeDecodeError: "))
            raise UnicodeDecodeError("utf-8", bytes.fromhex(record["bytes"]),
                                     record["start"], record["end"], record["reason"]) from None
        raise


def decode(name, word, address=0):
    result = _query(b"", name, word=word, address=address)
    return tuple(result) if isinstance(result, list) else result


def macho_uuid(image):
    return _query(image, "macho_uuid")


def macho_symbols(image):
    return _query(image, "macho_symbols")


def virtual_to_file(image, address):
    return _query(image, "virtual_to_file", address=address)


def symbol_code(image, name):
    address, start, end = _query(image, "symbol_code", name=name)
    return address, image[start:end]


def words(code):
    return (tuple(item) for item in _query(code, "words"))


def find_materialized_constant(code, target):
    return [tuple(item) for item in _query(code, "find_materialized_constant", target=target)]


def resolve_static_w_register(instructions, before, register, depth=0):
    return _query(b"", "resolve_static_w_register", instructions=instructions,
                  before=before, register=register, depth=depth)


def resolve_static_x_register(instructions, before, register, depth=0):
    return _query(b"", "resolve_static_x_register", instructions=instructions,
                  before=before, register=register, depth=depth)


def g17_register_is_written(word, register):
    return _query(b"", "g17_register_is_written", word=word, register=register)


def stores_covering(code, base, target):
    return _query(code, "stores_covering", base=base, target=target)


def stores_covering_any(code, targets):
    return {int(key): [tuple(item) for item in items]
            for key, items in _query(code, "stores_covering_any", targets=list(targets)).items()}


def read_adrp_add_address(function_address, code, adrp_offset, add_offset):
    return _query(code, "read_adrp_add_address", function_address=function_address,
                  adrp_offset=adrp_offset, add_offset=add_offset)


def read_adrp_add_cstring(image, function_address, code, adrp_offset, add_offset):
    return _query(image, "read_adrp_add_cstring", function_address=function_address,
                  code=code.hex(), adrp_offset=adrp_offset, add_offset=add_offset)


def read_virtual_u32_table(image, address, count):
    return tuple(_query(image, "read_virtual_u32_table", address=address, count=count))


def read_adrp_load(image, function_address, code, adrp_offset, load_offset, expected_width):
    start, end = _query(image, "read_adrp_load", function_address=function_address,
                        code=code.hex(), adrp_offset=adrp_offset,
                        load_offset=load_offset, expected_width=expected_width)
    return image[start:end]


def decode_kernel_auth_rebase(raw):
    return _query(b"", "decode_kernel_auth_rebase", raw=raw)


def recover_vtable_target(image, vtable_name, slot):
    return _query(image, "recover_vtable_target", vtable_name=vtable_name, slot=slot)


def require_instruction_sequence(code, label, sequence):
    return _query(code, "require_instruction_sequence", label=label, sequence=sequence)


def require_instruction_words_at(code, label, expected):
    return _query(code, "require_instruction_words_at", label=label, expected=list(expected.items()))


def find_authenticated_target_references(image, target):
    return _query(image, "find_authenticated_target_references", target=target)


def _integer_keys(value):
    """Restore integer map keys in native config results after JSON transport."""
    if isinstance(value, dict):
        return {int(key) if key.isdecimal() else key: _integer_keys(item)
                for key, item in value.items()}
    if isinstance(value, list):
        return [_integer_keys(item) for item in value]
    return value


_public_constants = None


def _constant_value(node):
    kind, value = node
    if kind == "dict":
        return {_constant_value(key): _constant_value(item) for key, item in value}
    if kind == "tuple":
        return tuple(_constant_value(item) for item in value)
    if kind == "list":
        return [_constant_value(item) for item in value]
    return value


def public_constants():
    global _public_constants
    if _public_constants is None:
        _public_constants = {name: _constant_value(value) for name, value
                             in _query(b"", "public_constants").items()}
    return _public_constants
