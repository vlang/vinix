#!/usr/bin/env python3
"""Generate native Linux ABI fixture artifacts from maintained V modules."""
import argparse
import runpy
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def generate_module(module, output, arch):
    generate = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))["generate"]
    generate(Path(module).resolve(), Path(output).resolve(),
             "arm64" if arch == "aarch64" else "amd64", ("nofloat",))
    return Path(output)


def generate_serial(output, arch):
    return generate_module(ROOT / "tests/kernel-gaps/serialcore", output, arch)


def compile_module(module, output, arch, flags):
    output = Path(output)
    source = generate_module(module, output.with_suffix(".c"), arch)
    # Compiler-generated V support includes unused inline helpers and unused
    # initializer arguments. Apply these two exceptions only to the V object;
    # independent C fixture inputs retain their complete warning policy.
    compile_flags = [flag for flag in flags if flag not in ("-static", "-nostdlib", "-pie")
                     and not flag.startswith(("-L", "-l", "-Wl,", "-fuse-ld="))]
    subprocess.run(compile_flags + ["-Wno-unused-function", "-Wno-unused-parameter", "-fPIC",
                                   "-I", str(Path(module).resolve()), "-c", str(source),
                                   "-o", str(output)], check=True)
    return output


def compile_serial(output, arch, flags):
    return compile_module(ROOT / "tests/kernel-gaps/serialcore", output, arch, flags)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--module", type=Path,
                        help="Generate this fixture module instead of the serial constructor")
    args = parser.parse_args()
    if args.module:
        generate_module(args.module, args.output, args.arch)
    else:
        generate_serial(args.output, args.arch)
