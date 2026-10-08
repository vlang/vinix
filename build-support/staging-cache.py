#!/usr/bin/env python3
"""Check or publish a content key for an extracted application layer."""

from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import sys
import tempfile


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "vinix_build_cache", HERE.parent / "desktop/tools/build_cache.py"
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load build_cache.py")
BUILD_CACHE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD_CACHE)


def cache_key(args: argparse.Namespace) -> str:
    native = BUILD_CACHE._native
    return native.request("staging_key", root=native.wire(HERE.parent),
                          values=[native.wire(value) for value in args.value],
                          sources=[native.wire(path) for path in args.source],
                          metadata=[native.wire(path) for path in args.metadata],
                          vlib=[native.wire(path) for path in args.vlib])


def complete(args: argparse.Namespace) -> bool:
    native = BUILD_CACHE._native
    return native.request("staging_complete", staging=native.wire(args.staging),
                          required=[native.wire(path) for path in args.required],
                          executable=[native.wire(path) for path in args.executable],
                          any=[native.wire(path) for path in args.executable_any])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "record"))
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--staging", type=Path, required=True)
    parser.add_argument("--source", type=Path, action="append", default=[])
    parser.add_argument("--metadata", type=Path, action="append", default=[])
    parser.add_argument("--vlib", type=Path, action="append", default=[])
    parser.add_argument("--value", action="append", default=[])
    parser.add_argument("--required", type=Path, action="append", default=[])
    parser.add_argument("--executable", type=Path, action="append", default=[])
    parser.add_argument("--executable-any", type=Path, action="append", default=[])
    args = parser.parse_args()
    key = cache_key(args)
    if args.action == "check":
        try:
            return 0 if complete(args) and args.state.read_text().strip() == key else 1
        except OSError:
            return 1
    if not complete(args):
        parser.error("refusing to cache an incomplete staging tree")
    args.state.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=args.state.parent,
                                     prefix=args.state.name + ".", delete=False) as output:
        temporary = Path(output.name)
        output.write(key + "\n")
    os.replace(temporary, args.state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
