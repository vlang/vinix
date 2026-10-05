#!/usr/bin/env python3
# Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
# Use of this source code is governed by a GPL v2 license
# that can be found in the LICENSE file.
"""Read an FDT the way kernel/devicetree/devicetree.v does.

Big-endian header, structure and cell properties; missing #address-cells and
#size-cells default to 2 like the kernel; reg is translated through every
ancestor's ranges exactly as get_translated_reg_ranges does. Used to check
the Apple loader's ADT conversion against XNU's own IODeviceMemory windows.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field

FDT_MAGIC = 0xD00DFEED
BEGIN_NODE, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


@dataclass
class Node:
    name: str
    parent: "Node | None"
    properties: dict[str, bytes] = field(default_factory=dict)
    children: list["Node"] = field(default_factory=list)

    def path(self) -> str:
        if self.parent is None:
            return "/"
        parent = self.parent.path()
        return f"{parent.rstrip('/')}/{self.name}"


def parse(blob: bytes) -> Node:
    magic, total, off_struct, off_strings = struct.unpack_from(">IIII", blob, 0)
    if magic != FDT_MAGIC or total > len(blob):
        raise ValueError("not an FDT")

    def string(offset: int) -> str:
        end = blob.index(b"\0", off_strings + offset)
        return blob[off_strings + offset : end].decode()

    offset = off_struct
    stack: list[Node] = []
    root: Node | None = None
    while True:
        token = struct.unpack_from(">I", blob, offset)[0]
        offset += 4
        if token == BEGIN_NODE:
            end = blob.index(b"\0", offset)
            name = blob[offset:end].decode("ascii", "replace")
            offset = (end + 4) & ~3
            node = Node(name, stack[-1] if stack else None)
            if stack:
                stack[-1].children.append(node)
            else:
                root = node
            stack.append(node)
        elif token == END_NODE:
            stack.pop()
        elif token == PROP:
            length, name_offset = struct.unpack_from(">II", blob, offset)
            offset += 8
            stack[-1].properties[string(name_offset)] = blob[offset : offset + length]
            offset = (offset + length + 3) & ~3
        elif token == NOP:
            continue
        elif token == END:
            break
        else:
            raise ValueError(f"bad FDT token {token}")
    if root is None or stack:
        raise ValueError("unbalanced FDT")
    return root


def get_u32(node: Node, name: str, default: int | None = None) -> int | None:
    value = node.properties.get(name)
    if value is None or len(value) < 4:
        return default
    return struct.unpack(">I", value[:4])[0]


def read_cells(data: bytes, offset: int, count: int) -> int:
    if count == 1:
        return struct.unpack_from(">I", data, offset)[0]
    if count == 2:
        return struct.unpack_from(">Q", data, offset)[0]
    raise ValueError(f"unsupported cell count {count}")


def is_apple_adt(node: Node) -> bool:
    while node.parent is not None:
        node = node.parent
    return "vinix,apple-adt" in node.properties


def translate(node: Node, address: int) -> int | None:
    apple = is_apple_adt(node)
    bus = node.parent
    while bus is not None:
        if bus.parent is None:
            break
        ranges = bus.properties.get("ranges")
        if not ranges and apple:
            # XNU's IODTResolveAddressCell: no ranges ends the walk.
            break
        if ranges:
            child_cells = get_u32(bus, "#address-cells", 2)
            parent_cells = get_u32(bus.parent, "#address-cells", 2)
            size_cells = get_u32(bus, "#size-cells", 2)
            stride = 4 * (child_cells + parent_cells + size_cells)
            if not stride or len(ranges) % stride:
                return None
            for offset in range(0, len(ranges), stride):
                child = read_cells(ranges, offset, child_cells)
                parent = read_cells(ranges, offset + 4 * child_cells, parent_cells)
                size = read_cells(ranges, offset + 4 * (child_cells + parent_cells), size_cells)
                if child <= address < child + size:
                    address = parent + (address - child)
                    break
            else:
                return None
        bus = bus.parent
    return address


def translated_reg(node: Node) -> list[tuple[int, int]] | None:
    reg = node.properties.get("reg")
    if reg is None or node.parent is None:
        return None
    address_cells = get_u32(node.parent, "#address-cells", 2)
    size_cells = get_u32(node.parent, "#size-cells", 2)
    stride = 4 * (address_cells + size_cells)
    if not stride or len(reg) % stride:
        return None
    result = []
    for offset in range(0, len(reg), stride):
        base = read_cells(reg, offset, address_cells)
        size = read_cells(reg, offset + 4 * address_cells, size_cells) if size_cells else 0
        translated = translate(node, base)
        if translated is None:
            return None
        result.append((translated, size))
    return result


def walk(node: Node):
    yield node
    for child in node.children:
        yield from walk(child)
