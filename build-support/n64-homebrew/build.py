#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the MIT-licensed PADDLE N64 ROM using ordinary LLVM MIPS backends."""
from __future__ import annotations
import argparse
from pathlib import Path
import runpy
import shutil
import struct
import subprocess

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[1]


def tool(name: str, directory: Path | None) -> str:
    locations = ([directory / name] if directory else []) + [
        Path("/opt/homebrew/opt/llvm/bin") / name, Path("/opt/homebrew/opt/lld/bin") / name,
        Path("/usr/lib/llvm-23/bin") / name, Path("/usr/lib/llvm-20/bin") / name]
    for path in locations:
        if path.is_file():
            return str(path)
    result = shutil.which(name)
    if result:
        return result
    raise SystemExit(f"missing {name}: install LLVM and pass --llvm-bin")


def segments(path: Path, base: int, limit: int) -> bytes:
    elf = path.read_bytes()
    fields = struct.unpack_from(">16sHHIIIIIHHHHHH", elf)
    offset, entry_size, count = fields[5], fields[9], fields[10]
    image = bytearray()
    for index in range(count):
        kind, start, address, _, size, memory, _, _ = struct.unpack_from(
            ">IIIIIIII", elf, offset + index * entry_size)
        if kind != 1:
            continue
        if address < base or address + memory > limit:
            raise SystemExit(f"{path.name}: load segment is outside the program region")
        needed = address - base + memory
        image.extend(bytes(max(0, needed - len(image))))
        image[address - base:address - base + size] = elf[start:start + size]
    return bytes(image)


def checksum(rom: bytearray) -> None:
    # Conventional CIC-6102 checksum. The open IPL3 does not enforce it, but a
    # normal header permits inspection with ordinary N64 ROM utilities.
    mask, seed = 0xffffffff, 0xf8ca4ddc
    t1 = t2 = t3 = t4 = t5 = t6 = seed
    padded = rom + bytes(max(0, 0x101000 - len(rom)))
    for offset in range(0x1000, 0x101000, 4):
        word = struct.unpack_from(">I", padded, offset)[0]
        total = (t6 + word) & mask
        t4 = (t4 + (total < t6)) & mask
        t6 = total
        t3 ^= word
        shift = word & 31
        rotated = ((word << shift) | (word >> ((32 - shift) & 31))) & mask
        t5 = (t5 + rotated) & mask
        t2 ^= rotated if t2 > word else t6 ^ word
        t1 = (t1 + (t5 ^ word)) & mask
    struct.pack_into(">II", rom, 0x10, t6 ^ t4 ^ t3, t5 ^ t2 ^ t1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--llvm-bin", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    clang, linker = tool("clang", args.llvm_bin), tool("ld.lld", args.llvm_bin)
    flags = ["--target=mips-none-elf", "-march=mips3", "-mabi=32", "-mno-abicalls",
             "-fno-pic", "-G0", "-msoft-float", "-ffreestanding", "-fno-builtin",
             "-fno-stack-protector", "-O2", "-Wall", "-Wextra", "-Werror"]
    for source in ("ipl3.S", "start.S", "paddlecore/mmio.S"):
        target = output / (Path(source).name + ".o")
        subprocess.run([clang, *flags, "-c", str(SOURCE / source), "-o", str(target)], check=True)
    # V has no MIPS target. Its no-builtin C backend uses a 32-bit type model;
    # actual o32 widths, big-endian data and instructions belong to LLVM MIPS.
    # This module contains no architecture-selected V code or hosted runtime.
    core = SOURCE / "paddlecore"
    generated = output / "paddle.generated.c"
    generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
    generate(core, generated, "x86")
    subprocess.run([clang, *flags, "-Wno-unused-function", "-Wno-unused-parameter",
                    "-I" + str(core), "-I" + str(core / "freestanding"),
                    "-c", str(generated), "-o", str(output / "paddle.v.o")], check=True)
    for name, sources in (("ipl3", ("ipl3.S.o",)), ("game", ("start.S.o", "paddle.v.o", "mmio.S.o"))):
        subprocess.run([linker, "-m", "elf32btsmip", "-T", str(SOURCE / (name + ".ld")),
                        *(str(output / source) for source in sources), "-o", str(output / (name + ".elf"))], check=True)
    rom = bytearray(0x100000)
    struct.pack_into(">IIII", rom, 0, 0x80371240, 0x0000000f, 0x80000400, 0x00000000)
    rom[0x20:0x34] = b"VINIX PADDLE".ljust(20, b" ")
    # Advanced homebrew cartridge ID DE; version nibble 3 selects 32 KiB SRAM.
    rom[0x3b:0x40] = b"NDEE\x30"
    boot = segments(output / "ipl3.elf", 0xa4000040, 0xa4001000)
    program = segments(output / "game.elf", 0x80000400, 0x800ff400)
    rom[0x40:0x40 + len(boot)] = boot
    rom[0x1000:0x1000 + len(program)] = program
    checksum(rom)
    (output / "paddle.z64").write_bytes(rom)
    shutil.copy2(SOURCE / "LICENSE", output / "LICENSE")
    print(output / "paddle.z64")


if __name__ == "__main__":
    main()
