#!/usr/bin/env python3
"""Generate the allocation-free Windows64 Office licensing compatibility DLL."""
import argparse
import importlib.util
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent


def generate(output, arch="amd64"):
    spec = importlib.util.spec_from_file_location("office_v_generator", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    compiler.generate(SUPPORT / "officecore", output.resolve(), arch, ["nofloat"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cc", help="Windows64 compiler; emit a DLL instead of only its generated artifact")
    parser.add_argument("--generated-dir", type=Path)
    args = parser.parse_args()
    if args.cc:
        directory = args.generated_dir or args.output.parent / "office-generated"
        directory.mkdir(parents=True, exist_ok=True)
        source = directory / "office.c"
        generate(source)
        subprocess.run([args.cc, "-Os", "-s", "-shared", "-Wall", "-Wextra", "-Werror",
                        "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
                        "-I", str(SUPPORT), str(source), str(SUPPORT / "sppc-office.def"),
                        "-o", str(args.output)], check=True)
    else:
        generate(args.output)
