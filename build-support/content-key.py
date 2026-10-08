#!/usr/bin/env python3
"""Print deterministic fingerprints for files and directory trees.

The default content mode ignores mtimes and inode numbers and is used to decide
whether rebuilding a generated image would change any meaningful mutable
payload. ``--metadata`` avoids reading file contents and instead fingerprints
filesystem metadata; it is useful for cheaply detecting an in-place rebuild of
a large staging tree.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import sys
from pathlib import Path

_native_spec = importlib.util.spec_from_file_location("vinix_cache_native", Path(__file__).with_name("_cache_native.py"))
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def add_field(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def main() -> int:
    args = sys.argv[1:]
    metadata_only = False
    if args[:1] == ["--metadata"]:
        metadata_only = True
        args = args[1:]
    if not args:
        print(
            f"usage: {Path(sys.argv[0]).name} [--metadata] PATH [PATH ...]",
            file=sys.stderr,
        )
        return 2

    print(_native.request("content", paths=[_native.wire(Path(path)) for path in args],
                          metadata=metadata_only))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
