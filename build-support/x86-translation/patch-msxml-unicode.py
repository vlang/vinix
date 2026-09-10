#!/usr/bin/env python3
"""Teach Wine's built-in MSXML the Windows XML encoding name ``unicode``.

MSXML accepts ``encoding="unicode"`` as a UTF-16LE declaration and Office
Click-to-Run uses that spelling in configuration streams. Wine's statically
linked libxml2 rejects it. Repurpose its rarely used ISO-8859-16 default
handler as a second name for the UTF-16LE converter so built-in MSXML matches
Windows without requiring Microsoft's native DLL.

The replacement is length preserving. UTF-16LE itself remains registered so
BOM auto-detection continues to work.
"""

from pathlib import Path
import os
import struct
import sys
import tempfile


UTF16_CONTEXT = b"UTF-16LE\0UTF-16BE\0"
OLD_ALIAS = b"ISO-8859-16\0"
NEW_ALIAS = b"UNICODE\0" + bytes(len(OLD_ALIAS) - len(b"UNICODE\0"))


def pe_layout(data: bytes) -> tuple[int, int, list[tuple[int, int, int]]]:
    """Return image base, pointer size, and (file, size, RVA) sections."""
    if data[:2] != b"MZ":
        raise ValueError("not a PE image")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe : pe + 4] != b"PE\0\0":
        raise ValueError("invalid PE signature")
    section_count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    if magic == 0x20B:
        pointer_size = 8
        image_base = struct.unpack_from("<Q", data, optional + 24)[0]
    elif magic == 0x10B:
        pointer_size = 4
        image_base = struct.unpack_from("<I", data, optional + 28)[0]
    else:
        raise ValueError(f"unsupported PE optional-header magic: {magic:#x}")

    sections = []
    section_table = optional + optional_size
    for index in range(section_count):
        entry = section_table + index * 40
        raw_size, raw_offset = struct.unpack_from("<II", data, entry + 16)
        virtual_address = struct.unpack_from("<I", data, entry + 12)[0]
        sections.append((raw_offset, raw_size, virtual_address))
    return image_base, pointer_size, sections


def offset_to_va(
    offset: int, image_base: int, sections: list[tuple[int, int, int]]
) -> int:
    for raw_offset, raw_size, virtual_address in sections:
        if raw_offset <= offset < raw_offset + raw_size:
            return image_base + virtual_address + offset - raw_offset
    raise ValueError(f"file offset {offset:#x} is outside PE sections")


def references(data: bytes, value: int, pointer_size: int) -> list[int]:
    packed = value.to_bytes(pointer_size, "little")
    return [index for index in range(len(data)) if data.startswith(packed, index)]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} MSXML3.DLL", file=sys.stderr)
        return 2

    target = Path(sys.argv[1])
    data = bytearray(target.read_bytes())
    image_base, pointer_size, sections = pe_layout(data)
    utf_count = data.count(UTF16_CONTEXT)
    old_count = data.count(OLD_ALIAS)
    new_count = data.count(NEW_ALIAS)
    if utf_count != 1 or (old_count, new_count) not in ((1, 0), (0, 1)):
        raise ValueError(
            "unexpected MSXML handler layout: "
            f"utf16={utf_count}, old={old_count}, new={new_count}"
        )

    utf_offset = data.index(UTF16_CONTEXT)
    alias_offset = data.index(OLD_ALIAS if old_count else NEW_ALIAS)
    utf_references = references(
        data, offset_to_va(utf_offset, image_base, sections), pointer_size
    )
    alias_references = references(
        data, offset_to_va(alias_offset, image_base, sections), pointer_size
    )
    if len(utf_references) != 1 or len(alias_references) != 1:
        raise ValueError(
            "unexpected MSXML handler references: "
            f"utf16={utf_references}, alias={alias_references}"
        )

    utf_entry = utf_references[0]
    alias_entry = alias_references[0]
    converter_size = pointer_size * 2
    utf_converters = data[
        utf_entry + pointer_size : utf_entry + pointer_size + converter_size
    ]
    alias_converters = data[
        alias_entry + pointer_size : alias_entry + pointer_size + converter_size
    ]
    if old_count:
        data[alias_offset : alias_offset + len(OLD_ALIAS)] = NEW_ALIAS
        data[
            alias_entry + pointer_size : alias_entry + pointer_size + converter_size
        ] = utf_converters
    elif alias_converters != utf_converters:
        raise ValueError("MSXML unicode alias has unexpected converter pointers")
    else:
        print(f"MSXML Windows unicode handler already present: {target}")
        return 0

    mode = target.stat().st_mode
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
        output.write(data)
        temporary = Path(output.name)
    os.chmod(temporary, mode)
    os.replace(temporary, target)
    print(f"patched MSXML Windows unicode handler: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
