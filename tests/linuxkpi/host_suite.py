#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile independent V LinuxKPI host tests against the production objects."""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "tests/linuxkpi"
spec = importlib.util.spec_from_file_location("linuxkpi_host_native", TESTS / "_host_native.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)

def __getattr__(name):
    if name == "GROUPS":
        return tuple(tuple(row) for row in native.request("groups"))
    raise AttributeError(name)


def build(work, arch, sanitize=True):
    native.request("suite", source=work, arch=arch, sanitize=sanitize)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    parser.add_argument("--arch", choices=("arm64", "amd64"), required=True)
    parser.add_argument("--native", action="store_true", help="Build unsanitized target objects for a native guest; assertions remain active")
    args = parser.parse_args()
    build(args.work.resolve(), args.arch, not args.native)
