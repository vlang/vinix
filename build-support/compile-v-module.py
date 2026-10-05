#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Emit a freestanding V module's C build artifact without the V runtime."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def emit_header(source, output, header):
    """Derive public declarations from compiler output and V readonly metadata.

    The V compiler currently omits pointee const qualifiers. An ABI readonly
    comment identifies those exported parameters without maintaining C bodies
    or duplicate function signatures.
    """
    readonly = {}
    readonly_pointer = {}
    for path in sorted(source.glob("*.v")):
        for function, parameter in re.findall(
                r"^// ABI readonly: (\w+)\.(\w+)\s*$", path.read_text(), re.M):
            readonly.setdefault(function, set()).add(parameter)
        for function, parameter in re.findall(
                r"^// ABI readonly-pointer: (\w+)\.(\w+)\s*$", path.read_text(), re.M):
            readonly_pointer.setdefault(function, set()).add(parameter)
    declarations = []
    for prototype in re.findall(
            r'__attribute__\(\(visibility\("default"\)\)\) ([^;{}\n]+);',
            output.read_text()):
        match = re.fullmatch(r"(.+?) (\w+)\((.*)\)", prototype)
        if not match:
            raise ValueError(f"Unsupported exported declaration: {prototype}")
        result, name, parameters = match.groups()
        for parameter in readonly.pop(name, set()):
            pattern = r"\b(\w+)\* " + re.escape(parameter) + r"(?=,|$)"
            parameters, count = re.subn(pattern, r"const \1* " + parameter, parameters)
            if count != 1:
                raise ValueError(f"Readonly metadata does not match {name}.{parameter}")
        for parameter in readonly_pointer.pop(name, set()):
            pattern = r"\b(\w+\*)\* " + re.escape(parameter) + r"(?=,|$)"
            parameters, count = re.subn(pattern, r"\1 const* " + parameter, parameters)
            if count != 1:
                raise ValueError(f"Readonly pointer metadata does not match {name}.{parameter}")
        declaration = f"{result} {name}({parameters});"
        for vtype, ctype in {"i32": "int32_t", "u32": "uint32_t", "i64": "int64_t",
                             "u64": "uint64_t", "i16": "int16_t", "u16": "uint16_t",
                             "i8": "int8_t", "u8": "uint8_t", "usize": "size_t",
                             "isize": "intptr_t"}.items():
            declaration = re.sub(r"\b" + vtype + r"\b", ctype, declaration)
        # These standalone headers describe scalar/pointer APIs. Fail early
        # when a module needs a public struct or callback type definition.
        types = [declaration[:declaration.index(name)].strip()]
        parameter_text = declaration[declaration.index("(") + 1:-2]
        for parameter in parameter_text.split(","):
            types.append(re.sub(r"\s+\w+$", "", parameter.strip()))
        primitives = {"void", "bool", "char", "short", "int", "long", "float", "double",
                      "const", "signed", "unsigned", "size_t", "intptr_t"}
        primitives.update(f"{prefix}int{bits}_t" for prefix in ("", "u") for bits in (8, 16, 32, 64))
        unknown = {token for value in types for token in re.findall(r"\w+", value)
                   if token not in primitives}
        if unknown:
            raise ValueError(f"Export {name} requires unsupported public types: {sorted(unknown)}")
        declarations.append(declaration)
    if readonly or readonly_pointer:
        raise ValueError(f"Readonly metadata names absent exports: {readonly}, {readonly_pointer}")
    if not declarations:
        raise ValueError("Module has no exported declarations")
    guard = "VINIX_GENERATED_" + re.sub(r"\W", "_", header.name.upper())
    header.write_text("// Generated from V; do not maintain this build artifact.\n"
                      f"#ifndef {guard}\n#define {guard}\n"
                      "#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n"
                      "#ifdef __cplusplus\nextern \"C\" {\n#endif\n" +
                      "\n".join(declarations) +
                      "\n#ifdef __cplusplus\n}\n#endif\n#endif\n")


def generate(source, output, arch="amd64", defines=()):
    v = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
        "find-v", str(ROOT),
    ], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-v-module-") as directory:
        work = Path(directory)
        shutil.copytree(source, work / source.name)
        (work / "v.mod").write_text("Module { name: 'native_module' }\n")
        (work / "entry.v").write_text(f"module main\nimport {source.name} as _\n")
        command = [v, "-shared", "-no-builtin", "-no-closures", "-os", "vinix",
                   "-arch", arch, "-target-libc-headers", "-gc", "none", "-manualfree"]
        for define in defines:
            command.extend(["-d", define])
        subprocess.run(command + ["-o", str(output), str(work)], check=True,
                       env={**os.environ, "V_C_ERROR_BUG_REPORT_DISABLED": "1"})
        # Independently compiled V modules otherwise export identical shared
        # library initialization symbols. Preserve their constructor/destructor
        # behavior while giving each module its own generated scaffolding.
        text = output.read_text()
        text = re.sub(r"\b(_vinit|_vcleanup|_vinit_caller|_vcleanup_caller|"
                      r"_vno_main_init_caller|_v3_no_main_initialized)\b",
                      lambda match: source.name + "_" + match[1], text)
        # A module implementing execinfo supplies its own exported declarations.
        # Suppress only this translation unit's legacy compiler fallback. Other
        # callers still receive the compiler's normal backtrace declarations.
        if re.search(r'visibility\("default"\)\)\) [^;\n]+ backtrace\(', text):
            text = "#define __V_HAVE_EXECINFO_H 1\n" + text
        output.write_text(text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    parser.add_argument("-d", "--define", action="append", default=[])
    parser.add_argument("--header", type=Path, help="Emit public ABI declarations as a build artifact")
    args = parser.parse_args()
    generate(args.source.resolve(), args.output.resolve(), args.arch, args.define)
    if args.header:
        emit_header(args.source.resolve(), args.output.resolve(), args.header.resolve())
