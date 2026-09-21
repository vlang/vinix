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
import os
import stat
import sys
from pathlib import Path


def add_field(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def add_generation_metadata(digest: "hashlib._Hash", info: os.stat_result) -> None:
    # Inode/dev catch a builder replacing an output with byte-identical content;
    # ctime catches an in-place rewrite even when package extraction preserves
    # the source mtime. No file data is read in this mode.
    for value in (
        info.st_dev,
        info.st_ino,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
    ):
        add_field(digest, str(value).encode())


def hash_path(
    digest: "hashlib._Hash", path: Path, label: bytes, metadata_only: bool
) -> None:
    add_field(digest, label)
    try:
        info = path.lstat()
    except FileNotFoundError:
        add_field(digest, b"missing")
        return

    mode = stat.S_IMODE(info.st_mode)
    add_field(digest, oct(mode).encode())
    if metadata_only:
        add_generation_metadata(digest, info)

    if stat.S_ISLNK(info.st_mode):
        add_field(digest, b"symlink")
        add_field(digest, os.readlink(path).encode("utf-8", "surrogateescape"))
        return

    if stat.S_ISREG(info.st_mode):
        add_field(digest, b"file")
        add_field(digest, str(info.st_size).encode())
        if not metadata_only:
            with path.open("rb") as handle:
                while chunk := handle.read(1024 * 1024):
                    digest.update(chunk)
        return

    if stat.S_ISDIR(info.st_mode):
        add_field(digest, b"directory")
        for name in sorted(os.listdir(path), key=os.fsencode):
            encoded = os.fsencode(name)
            hash_path(digest, path / name, label + b"/" + encoded, metadata_only)
        return

    # These keys are only expected to cover ordinary build outputs. Keep an
    # explicit representation for an accidental special file rather than
    # silently treating it as an empty regular file.
    add_field(digest, b"special")
    add_field(digest, str(stat.S_IFMT(info.st_mode)).encode())


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

    digest = hashlib.sha256()
    add_field(
        digest,
        b"vinix-metadata-key-v1" if metadata_only else b"vinix-content-key-v1",
    )
    for index, raw_path in enumerate(args):
        # Content keys deliberately exclude root locations so moving a checkout
        # cannot change an otherwise identical image. Metadata keys are local
        # generation checks, so their inode/dev values intentionally do vary.
        hash_path(digest, Path(raw_path), f"root-{index}".encode(), metadata_only)
    print(digest.hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
