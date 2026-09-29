#!/usr/bin/env python3
# Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
# Use of this source code is governed by a GPL v2 license
# that can be found in the LICENSE file.
"""Append the kernel, initramfs and command line to the Apple loader.

The result is the raw image iBoot starts (`kmutil configure-boot --raw
--entry-point 2048 --lowest-virtual-address 0`). The loader finds the payload
header at its own `loader_end` symbol, so the loader is zero-padded up to it;
the header layout is struct payload_header in src/loader.h."""

from __future__ import annotations

import argparse
import struct
import sys
import time
from pathlib import Path

MAGIC = b"VNXAPPL1"
HEADER = struct.Struct("<8sII8Q")
BLOB_ALIGNMENT = 0x4000
FLAG_MAP_LOW_4G = 1


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def elf_symbol(path: Path, wanted: str) -> int:
    """Value of one symbol from a 64-bit little-endian ELF's .symtab."""
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x02\x01":
        raise SystemExit(f"{path}: not a 64-bit little-endian ELF")
    section_offset, = struct.unpack_from("<Q", data, 0x28)
    section_size, section_count = struct.unpack_from("<HH", data, 0x3A)
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, section_offset + index * section_size)
                for index in range(section_count)]
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        strings = sections[section[6]]
        for at in range(section[4], section[4] + section[5], section[9]):
            name, _, _, _, value, _ = struct.unpack_from("<IBBHQQ", data, at)
            start = strings[4] + name
            end = data.index(b"\0", start)
            if data[start:end].decode() == wanted:
                return value
    raise SystemExit(f"{path}: no symbol {wanted}")


def pack(loader: bytes, loader_end: int, kernel: bytes, initramfs: bytes, cmdline: str,
         flags: int, build_time: int) -> bytes:
    if len(loader) > loader_end:
        raise SystemExit(f"loader is {len(loader):#x} bytes, past loader_end {loader_end:#x}")
    if kernel[:4] != b"\x7fELF":
        raise SystemExit("the kernel is not an ELF file")
    command_line = cmdline.encode() + b"\0"

    offset = align(HEADER.size, BLOB_ALIGNMENT)
    kernel_offset = offset
    offset = align(offset + len(kernel), BLOB_ALIGNMENT)
    initramfs_offset = offset
    offset = align(offset + len(initramfs), BLOB_ALIGNMENT)
    cmdline_offset = offset
    total = align(offset + len(command_line), BLOB_ALIGNMENT)

    payload = bytearray(total)
    HEADER.pack_into(payload, 0, MAGIC, HEADER.size, flags, kernel_offset, len(kernel),
                     initramfs_offset, len(initramfs), cmdline_offset, len(command_line) - 1,
                     build_time, total)
    payload[kernel_offset:kernel_offset + len(kernel)] = kernel
    payload[initramfs_offset:initramfs_offset + len(initramfs)] = initramfs
    payload[cmdline_offset:cmdline_offset + len(command_line)] = command_line
    return loader + bytes(loader_end - len(loader)) + bytes(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    here = Path(__file__).resolve().parent
    parser.add_argument("--loader", type=Path, default=here / "build/vinix-apple-loader.bin")
    parser.add_argument("--loader-elf", type=Path, default=here / "build/vinix-apple-loader.elf")
    parser.add_argument("--kernel", type=Path, required=True)
    parser.add_argument("--initramfs", type=Path)
    parser.add_argument("--cmdline", default="")
    parser.add_argument("--map-low-4g", action="store_true",
                        help="HHDM-map the low 4 GiB (QEMU's MMIO) as Limine does")
    parser.add_argument("--build-time", type=int, default=int(time.time()))
    parser.add_argument("-o", "--output", type=Path, required=True)
    arguments = parser.parse_args()

    image = pack(arguments.loader.read_bytes(), elf_symbol(arguments.loader_elf, "loader_end"),
                 arguments.kernel.read_bytes(),
                 arguments.initramfs.read_bytes() if arguments.initramfs else b"",
                 arguments.cmdline, FLAG_MAP_LOW_4G if arguments.map_low_4g else 0,
                 arguments.build_time)
    arguments.output.write_bytes(image)
    print(f"{arguments.output}: {len(image)} bytes", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
