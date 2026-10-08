#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stage an independent V host fixture with shared native model declarations."""
import argparse
import importlib.util
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("linuxkpi_host_native", Path(__file__).with_name("_host_native.py"))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def existing(path):
    return Path(os.fsdecode(bytes.fromhex(native.request("existing", source=path))))


def generate(source, output, arch="arm64", shared_model=True):
    native.request("generate", source=source, output=output, arch=arch, shared_model=shared_model)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="arm64")
    parser.add_argument("--no-model", action="store_true")
    args = parser.parse_args()
    generate(args.source.resolve(), args.output.resolve(), args.arch, not args.no_model)
