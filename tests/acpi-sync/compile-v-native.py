#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Emit the independent ACPI fixture as a native kernel V object."""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("compile_v_native_fixture", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    compiler.generate(Path(__file__).resolve().parent / "nativefixture", args.output.resolve(), args.arch, ["nofloat"])
