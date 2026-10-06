#!/usr/bin/env python3
"""Compare the V descriptor's native object data with an immutable C input."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import struct
import subprocess

HERE = Path(__file__).resolve().parent


def descriptor(path):
    """Read Mach-O native data and external relocations without executing code."""
    blob = path.read_bytes()
    header = struct.unpack_from("<IiiIIIII", blob)
    assert header[0] == 0xfeedfacf and header[3] == 1
    position = 32
    sections = []
    symbols = None
    for _ in range(header[4]):
        command, size = struct.unpack_from("<II", blob, position)
        if command == 0x19:
            count = struct.unpack_from("<I", blob, position + 64)[0]
            for i in range(count):
                section = struct.unpack_from("<16s16sQQIIIIIIII", blob, position + 72 + i * 80)
                sections.append(section)
        elif command == 2:
            symbols = struct.unpack_from("<IIII", blob, position + 8)
        position += size
    assert symbols is not None
    symoff, nsyms, stroff, strsize = symbols
    names = []
    exports = []
    for i in range(nsyms):
        string, kind, section, description, value = struct.unpack_from("<IBBHQ", blob, symoff + i * 16)
        assert string < strsize
        name = blob[stroff + string:].split(b"\0", 1)[0].decode()
        names.append(name)
        if kind & 1:
            exports.append((name, kind, section, description, value))
    data = [s for s in sections if s[0].rstrip(b"\0") == b"__data"]
    assert len(data) == 1
    data = data[0]
    assert data[3] == 196 and data[5] == 2  # byte size and log2 alignment
    assert all(s[3] == 0 for s in sections if s is not data)
    relocations = []
    for i in range(data[7]):
        address, info = struct.unpack_from("<II", blob, data[6] + i * 8)
        assert info & (1 << 27)  # external native symbol
        relocations.append((address, names[info & 0xffffff], info >> 24))
    relocations.sort()
    assert [(a, n) for a, n, _ in relocations] == [(180, "_kmod_alloc_start"), (188, "_kmod_alloc_stop")]
    assert sorted(n for n, *_ in exports) == ["_kmod_alloc_start", "_kmod_alloc_stop", "_kmod_info"]
    return {"bytes": blob[data[4]:data[4] + data[3]].hex(),
            "relocations": relocations, "symbols": sorted(exports),
            "alignment": 1 << data[5], "size": data[3]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-reference", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    args = parser.parse_args()
    work = args.state_dir.resolve()
    work.mkdir(parents=True, exist_ok=False)
    generate = runpy.run_path(str(HERE / "compile-v-kmod-info.py"))["generate"]
    results = []
    for arch, varch in (("x86_64", "amd64"), ("arm64", "arm64")):
        target = work / arch
        target.mkdir()
        translated = target / "v.c"
        generate(translated, varch)
        original = target / "c.c"
        original.write_bytes(args.original_reference.read_bytes())
        flags = [os.environ.get("CC", "clang"), "-arch", arch, "-std=c11", "-O2",
                 "-Wall", "-Wextra", "-Werror", "-fno-builtin", "-ffreestanding",
                 "-fno-stack-protector"]
        if arch == "x86_64":
            flags += ["-mno-red-zone", "-mno-80387", "-mno-mmx", "-mno-sse", "-mno-sse2"]
        else:
            flags += ["-mgeneral-regs-only"]
        objects = []
        commands = []
        for source in (original, translated):
            obj = source.with_suffix(".o")
            command = flags + ["-c", str(source), "-o", str(obj)]
            subprocess.run(command, check=True)
            commands.append(command)
            objects.append(obj)
        c, v = map(descriptor, objects)
        assert c == v, (arch, c, v)
        results.append({"arch": arch, "descriptor": v, "commands": commands,
                        "objects_byte_identical": objects[0].read_bytes() == objects[1].read_bytes(),
                        "c_sha256": hashlib.sha256(objects[0].read_bytes()).hexdigest(),
                        "v_sha256": hashlib.sha256(objects[1].read_bytes()).hexdigest()})
    (work / "validation.json").write_text(json.dumps(results, indent=2) + "\n")
    print("KMOD METADATA: PASS both native ABIs, all196bytes, alignment and callback relocations")


if __name__ == "__main__":
    main()
