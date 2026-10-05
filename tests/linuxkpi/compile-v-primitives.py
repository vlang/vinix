#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile the native V module which directly binds upstream header primitives."""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="amd64")
    parser.add_argument("--host", action="store_true")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("compile_v_module", ROOT / "build-support/compile-v-module.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    defines = ["nofloat"]
    if args.host:
        defines.append("linuxkpi_host_test")
    compiler.generate(ROOT / "kernel/linuxkpi/headercore", args.output.resolve(), args.arch, defines)
