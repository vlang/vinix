#!/usr/bin/env python3
"""Emit the V kmod descriptor as static native data for the Darwin loader."""
import argparse
from pathlib import Path
import re
import runpy
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OFFSETS = {"next": 0, "info_version": 8, "id": 12, "name": 16,
           "version": 80, "reference_count": 144, "reference_list": 148,
           "address": 156, "size": 164, "hdr_size": 172, "start": 180, "stop": 188}


def generate(output: Path, arch: str = "amd64") -> None:
    generate_v = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
    with tempfile.TemporaryDirectory(prefix="vinix-kmod-meta-") as directory:
        raw = Path(directory) / "metadata.c"
        generate_v(HERE / "kmodmeta", raw, arch, ("nofloat",))
        text = raw.read_text()
    # Freestanding kmod loading precedes V constructors. Promote only the
    # compiler's sole aggregate assignment to a static data initializer; all
    # values, arrays, callback types and names still come from maintained V.
    body = re.findall(r"void kmodmeta__vinit\(int ___argc, voidptr ___argv\) \{\n(.*?)\n\}", text, re.S)
    if len(body) != 1:
        raise ValueError("V metadata must have exactly one initializer")
    assignment = re.fullmatch(
        r"\s*kmod_info = \(\{kmodmeta__Info (\w+) = \(kmodmeta__Info\)(\{[^{}]*\}); (.*) \1;\}\);",
        body[0], re.S)
    if not assignment:
        raise ValueError("V metadata initializer is not the expected fixed aggregate")
    temporary, initializer, copies = assignment.groups()
    # The compiler lowers fixed-array fields to copies inside its aggregate
    # expression. Only these literal arrays become static field initializers.
    for field in ("name", "version"):
        copy = re.match(r"memcpy\(" + re.escape(temporary) + r"\." + field +
                        r", \(u8\[64\]\)(\{[^{}]*\}), sizeof\(" +
                        re.escape(temporary) + r"\." + field + r"\)\); ?", copies)
        if not copy:
            raise ValueError(f"unsupported fixed {field} initializer")
        initializer = initializer[:-1] + f", .{field} = " + copy[1] + "}"
        copies = copies[copy.end():]
    if copies or re.search(r"\b(?!u8\b)\w+\s*\(", initializer):
        raise ValueError("kmod metadata cannot call a runtime initializer")
    start = text.index("typedef struct kmodmeta__Info kmodmeta__Info;")
    end = text.index("\nstatic void v3_eprint_lit", start)
    declarations = text[start:end]
    declarations = re.sub(r"^typedef struct __v_(?:option|result) .*\n", "", declarations, flags=re.M)
    aliases = re.findall(r"^typedef (?:u?int(?:8|32)_t) (?:u8|i32|u32);$", text, re.M)
    if len(aliases) != 3:
        raise ValueError("unsupported metadata integer declarations")
    output.write_text("// Generated from V; do not maintain this build artifact.\n"
                      "#include <stddef.h>\n#include <stdint.h>\n" +
                      "\n".join(aliases) + "\n" + declarations +
                      "\n__attribute__((visibility(\"default\"))) kmodmeta__Info kmod_info = " +
                      initializer + ";\n" +
                      '_Static_assert(sizeof(kmodmeta__Info) == 196, "kmod size");\n' +
                      '_Static_assert(_Alignof(kmodmeta__Info) == 4, "kmod alignment");\n' +
                      "".join(f'_Static_assert(offsetof(kmodmeta__Info, {field}) == {offset}, "kmod {field}");\n'
                              for field, offset in OFFSETS.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    args = parser.parse_args()
    generate(args.output.resolve(), args.arch)
