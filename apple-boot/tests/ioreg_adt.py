#!/usr/bin/env python3
# Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
# Use of this source code is governed by a GPL v2 license
# that can be found in the LICENSE file.
"""Rebuild the running Mac's Apple DeviceTree from the IORegistry.

The IODeviceTree plane holds every ADT property iBoot handed XNU as OSData,
next to properties XNU added of other types. Keeping only the data-valued
properties with ADT-sized names reproduces the tree the boot loader saw,
including values iBoot fills in at boot (aic-iack-offset, dram-size, ...)
that the signed template on disk leaves as placeholders.

XNU also records each node's translated register windows as IODeviceMemory;
they are returned beside the blob so a converter's address translation can be
checked against Apple's own.
"""

from __future__ import annotations

import argparse
import plistlib
import struct
import subprocess
from pathlib import Path

ADT_NAME_BYTES = 32


def load_ioreg() -> dict:
    output = subprocess.run(
        ["ioreg", "-a", "-l", "-p", "IODeviceTree", "-r", "-d", "0", "-n", "device-tree"],
        check=True,
        capture_output=True,
    ).stdout
    root = plistlib.loads(output)
    if isinstance(root, list):
        root = root[0]
    return root


def node_name(entry: dict) -> str:
    name = entry.get("name")
    if isinstance(name, bytes):
        return name.split(b"\0", 1)[0].decode("ascii", "replace")
    return entry.get("IORegistryEntryName", "")


def encode_node(entry: dict, path: str, memory: dict[str, list[tuple[int, int]]]) -> bytes:
    properties = []
    for key, value in entry.items():
        if not isinstance(value, bytes) or len(key.encode()) >= ADT_NAME_BYTES:
            continue
        if key.startswith("IO"):
            continue
        properties.append((key, value))
    children = entry.get("IORegistryEntryChildren", [])
    windows = entry.get("IODeviceMemory")
    if isinstance(windows, list):
        ranges = []
        for window in windows:
            if isinstance(window, list):
                window = window[0] if window else {}
            if isinstance(window, dict) and "address" in window:
                ranges.append((int(window["address"]), int(window["length"])))
        memory[path] = ranges
    out = bytearray(struct.pack("<II", len(properties), len(children)))
    for key, value in properties:
        out += key.encode().ljust(ADT_NAME_BYTES, b"\0")
        out += struct.pack("<I", len(value))
        out += value + b"\0" * ((-len(value)) % 4)
    for child in children:
        child_path = f"{path}/{node_name(child)}" if path != "/" else f"/{node_name(child)}"
        out += encode_node(child, child_path, memory)
    return bytes(out)


def build(root: dict | None = None) -> tuple[bytes, dict[str, list[tuple[int, int]]]]:
    root = root or load_ioreg()
    memory: dict[str, list[tuple[int, int]]] = {}
    return encode_node(root, "/", memory), memory


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    blob, memory = build()
    args.output.write_bytes(blob)
    print(f"{len(blob)} bytes, {len(memory)} nodes with IODeviceMemory")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
