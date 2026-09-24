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
    digest = BUILD_CACHE.new_digest("vinix-staging-cache", 1)
    BUILD_CACHE.hash_path(digest, HERE / "staging-cache.py", "staging-helper")
    BUILD_CACHE.hash_path(digest, HERE.parent / "desktop/tools/build_cache.py", "hash-helper")
    for value in args.value:
        BUILD_CACHE.add_hash_field(digest, value)
    for index, path in enumerate(args.source):
        BUILD_CACHE.hash_path(digest, path, f"source-{index}")
    for index, path in enumerate(args.metadata):
        BUILD_CACHE.hash_path(digest, path, f"metadata-{index}", metadata_only=True)
    for index, path in enumerate(args.vlib):
        BUILD_CACHE.hash_path(digest, path, f"vlib-{index}", metadata_only=True,
                              ignore=BUILD_CACHE.ignored_vlib_entry)
    return digest.hexdigest()


def complete(args: argparse.Namespace) -> bool:
    return args.staging.is_dir() and all(
        (args.staging / path).exists() for path in args.required
    ) and all((args.staging / path).is_file() and os.access(args.staging / path, os.X_OK)
              for path in args.executable) and (not args.executable_any or any(
                  (args.staging / path).is_file() and os.access(args.staging / path, os.X_OK)
                  for path in args.executable_any))


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
