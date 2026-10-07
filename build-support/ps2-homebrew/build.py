#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the MIT-licensed PADDLE PS2 ELF with ordinary LLVM MIPS backends."""
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
        Path("/usr/lib/llvm-23/bin") / name,
        Path("/usr/lib/llvm-20/bin") / name]
    for path in locations:
        if path.is_file():
            return str(path)
    result = shutil.which(name)
    if result:
        return result
    raise SystemExit(f"missing {name}: install LLVM and pass --llvm-bin")


def load_segments(path: Path, base: int) -> bytes:
    elf = path.read_bytes()
    fields = struct.unpack_from("<16sHHIIIIIHHHHHH", elf)
    offset, entry_size, count = fields[5], fields[9], fields[10]
    image = bytearray()
    for i in range(count):
        kind, start, address, _, size, memory, _, _ = struct.unpack_from(
            "<IIIIIIII", elf, offset + i * entry_size)
        if kind != 1:
            continue
        if address < base or address + memory > 0x00100000:
            raise SystemExit("IOP segment is outside the bare-metal program region")
        needed = address - base + memory
        image.extend(bytes(max(0, needed - len(image))))
        image[address - base:address - base + size] = elf[start:start + size]
    return bytes(image)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--llvm-bin", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    clang, linker = tool("clang", args.llvm_bin), tool("ld.lld", args.llvm_bin)
    common = ["--target=mipsel-none-elf", "-mno-abicalls", "-fno-pic", "-G0", "-msoft-float",
              "-ffreestanding", "-fno-builtin", "-fno-stack-protector", "-O2", "-Wall", "-Wextra", "-Werror"]
    for cpu, arch, abi in (("iop", "mips1", "32"), ("ee", "mips3", "n32")):
        flags = [*common, f"-march={arch}", f"-mabi={abi}"]
        native = [f"start-{cpu}.S"] + (["eecore/sync.S"] if cpu == "ee" else [])
        for source in native:
            target = output / (source + ".o")
            target.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run([clang, *flags, f"-I{output}", "-c", str(SOURCE / source), "-o", str(target)], check=True)
        # V has no MIPS target. Generate architecture-neutral no-builtin C
        # using its 32-bit type model, then enforce the actual native ABI in
        # LLVM: IOP MIPS-I/o32 and EE MIPS-III/n32, both little-endian.
        core = SOURCE / ("iopcore" if cpu == "iop" else "eecore")
        generated = output / f"{cpu}.generated.c"
        generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
        generate(core, generated, "x86")
        program_object = output / f"{cpu}.v.o"
        subprocess.run([clang, *flags, "-Wno-unused-function", "-Wno-unused-parameter",
                        f"-I{core}", f"-I{SOURCE / 'freestanding'}", f"-I{output}",
                        "-c", str(generated), "-o", str(program_object)], check=True)
        elf = output / ("iop.elf" if cpu == "iop" else "paddle.elf")
        subprocess.run([linker, "-m", "elf32ltsmip" if cpu == "iop" else "elf32ltsmipn32",
                        "-T", str(SOURCE / f"{cpu}.ld"), str(output / (f"start-{cpu}.S.o")),
                        str(program_object), *(str(output / (source + ".o")) for source in native[1:]),
                        "-o", str(elf)], check=True)
        if cpu == "iop":
            data = load_segments(elf, 0x1000)
            (output / "iop-image.h").write_text("// Generated from iopcore; SPDX-License-Identifier: MIT\n"
                "static const unsigned char iop_image[] = {\n" +
                ",\n".join(",".join(f"0x{x:02x}" for x in data[i:i+16]) for i in range(0, len(data), 16)) + "\n};\n")
        else:
            data = bytearray(elf.read_bytes())
            # A marked ELF requests the explicit open bare-metal boot protocol;
            # standard PS2 SDK ELFs still require the user's BIOS.
            data[7] = 0x56
            elf.write_bytes(data)
    shutil.copy2(SOURCE / "LICENSE", output / "LICENSE")
    print(output / "paddle.elf")


if __name__ == "__main__":
    main()
