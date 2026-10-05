#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate the translated Steam preload's native V build artifact."""
import argparse
import importlib.util
from pathlib import Path
import shutil
import tempfile
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def diagnostic_declarations():
    """Derive the compiler scaffold's bare libc declarations from V imports."""
    source = (HERE / "robustcore/core.v").read_text()
    match = re.search(r"fn C\.fprintf\(([^\n]+)\) (\w+)", source)
    types = {"voidptr": "void *", "&char": "char *", "i32": "int"}
    parameters = []
    for parameter in match[1].split(","):
        name, vtype = parameter.strip().split()
        parameters.append("..." if name.startswith("...") else types[vtype] + " " + name)
    declaration = types[match[2]] + " fprintf(" + ", ".join(parameters) + ");\n"
    global_match = re.search(r"__global C\.stderr (\w+)", source)
    declaration += "extern " + types[global_match[1]] + " stderr;\n"
    # Use native stdio when it exists; no V policy depends on its private layout.
    return "#if __has_include(<stdio.h>)\n#include <stdio.h>\n#else\n" + declaration + "#endif\n"


def generate(output, i386=False, host=False):
    spec = importlib.util.spec_from_file_location("vmodule", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    with tempfile.TemporaryDirectory(prefix="vinix-steam-robust-") as directory:
        source = Path(directory) / "robustcore"
        shutil.copytree(HERE / "robustcore", source)
        if not i386:
            (source / "mapping.v").unlink()
        compiler.generate(source, output.resolve(), "i386" if i386 and not host else "amd64",
                          ["steam_i386"] if i386 else [])
    # This headerless preload uses no integer printf macros. V's unused
    # diagnostic scaffold otherwise pulls inttypes.h's host-specific includes.
    text = output.read_text().replace("#include <inttypes.h>\n", "")
    layout = '\n_Static_assert(sizeof(size_t) == sizeof(void *) && '
    layout += 'sizeof(intptr_t) == sizeof(void *), "native pointer and C long ABI");\n'
    if i386:
        layout += '_Static_assert(sizeof(robustcore__Mapping) == 3 * sizeof(void *) && '
        layout += 'offsetof(robustcore__Mapping, requested) == sizeof(void *) && '
        layout += 'offsetof(robustcore__Mapping, padded) == 2 * sizeof(void *), "mapping record ABI");\n'
    output.write_text(diagnostic_declarations() + text + layout)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--i386", action="store_true")
    parser.add_argument("--host", action="store_true", help="LP64 fixture compilation of either policy")
    args = parser.parse_args()
    generate(args.output, args.i386, args.host)
