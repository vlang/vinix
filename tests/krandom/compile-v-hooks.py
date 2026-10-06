#!/usr/bin/env python3
"""Compile the V hardware model and complete libc variadic producer together."""
import argparse
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def compile_hooks(output, arch, flags, module=None):
    output = Path(output)
    compile_module = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_module"]
    module = Path(module) if module else ROOT / "tests/krandom/hosthooks"
    core = output.with_name(output.stem + "-core.o")
    compile_module(module, core, arch, flags)
    native = output.with_name(output.stem + "-abi.o")
    asm = module / ("varargs-arm64.S" if arch == "aarch64" else "varargs-amd64.S")
    compile_flags = [flag for flag in flags if not flag.startswith(("-L", "-l", "-Wl,", "-fuse-ld="))]
    subprocess.run(compile_flags + ["-c", str(asm), "-o", str(native)], check=True)
    # Existing v test launches accept one object in their unquoted ldflags.
    subprocess.run(flags + ["-nostdlib", "-r", str(core), str(native), "-o", str(output)], check=True)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("compiler", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.compiler:
        parser.error("pass a native compiler and flags")
    compile_hooks(args.output, args.arch, args.compiler)
