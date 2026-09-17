#!/usr/bin/env python3
"""Print a deterministic content fingerprint for files and directory trees.

Unlike a build timestamp, this intentionally ignores mtimes and inode numbers.
It is used to decide whether rebuilding a generated image would change any of
its meaningful mutable payload.
"""

from __future__ import annotations

import hashlib
import os
import stat
import sys
from pathlib import Path


def add_field(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def hash_path(digest: "hashlib._Hash", path: Path, label: bytes) -> None:
    add_field(digest, label)
    try:
        info = path.lstat()
    except FileNotFoundError:
        add_field(digest, b"missing")
        return

    mode = stat.S_IMODE(info.st_mode)
    add_field(digest, oct(mode).encode())

    if stat.S_ISLNK(info.st_mode):
        add_field(digest, b"symlink")
        add_field(digest, os.readlink(path).encode("utf-8", "surrogateescape"))
        return

    if stat.S_ISREG(info.st_mode):
        add_field(digest, b"file")
        add_field(digest, str(info.st_size).encode())
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
        return

    if stat.S_ISDIR(info.st_mode):
        add_field(digest, b"directory")
        for name in sorted(os.listdir(path), key=os.fsencode):
            encoded = os.fsencode(name)
            hash_path(digest, path / name, label + b"/" + encoded)
        return

    # These keys are only expected to cover ordinary build outputs. Keep an
    # explicit representation for an accidental special file rather than
    # silently treating it as an empty regular file.
    add_field(digest, b"special")
    add_field(digest, str(stat.S_IFMT(info.st_mode)).encode())


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {Path(sys.argv[0]).name} PATH [PATH ...]", file=sys.stderr)
        return 2

    digest = hashlib.sha256()
    add_field(digest, b"vinix-content-key-v1")
    for index, raw_path in enumerate(sys.argv[1:]):
        # Root locations are deliberately excluded. Moving a checkout should
        # not make an otherwise identical image look different.
        hash_path(digest, Path(raw_path), f"root-{index}".encode())
    print(digest.hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
