#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile the native V module which directly binds upstream header primitives."""
import argparse
import importlib.util
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[2]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    parser.add_argument("--host", action="store_true")
    parser.add_argument("--implementations-only", action="store_true",
                        help="Compile first-party header algorithms for standalone header tests")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("compile_v_module", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    defines = ["nofloat"]
    if args.host:
        defines.append("linuxkpi_host_test")
    source = ROOT / "kernel/linuxkpi/headercore"
    if args.implementations_only:
        # Reuse the production algorithms and their V foreign declarations.
        # The small test object needs no unrelated callback/storage definitions.
        with tempfile.TemporaryDirectory(prefix="vinix-header-implementations-") as directory:
            isolated = Path(directory) / "headercore"
            isolated.mkdir()
            (isolated / "primitive.v").write_bytes((source / "primitive.v").read_bytes())
            (isolated / "policy.v").write_bytes((source / "policy.v").read_bytes())
            declarations = []
            for filename, names in (("common.v", ("spinlock_t", "task_struct")),
                                    ("wait.v", ("atomic_t",))):
                text = (source / filename).read_text()
                for name in names:
                    pattern = r"(?:@\[typedef\]\s*)?struct C\." + name + r"\s*\{[^}]*\}"
                    matches = re.findall(pattern, text)
                    if len(matches) != 1:
                        raise ValueError(f"Expected exactly one native {name} declaration in {filename}")
                    declarations.append(matches[0])
            (isolated / "native_types.v").write_text("@[translated]\nmodule headercore\n"
                                                       '#include "linuxkpi_header_primitive_v_contract.h"\n' +
                                                       "\n".join(declarations) + "\n")
            compiler.generate(isolated, args.output.resolve(), args.arch, defines)
    else:
        compiler.generate(source, args.output.resolve(), args.arch, defines)
