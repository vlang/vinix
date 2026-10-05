#!/usr/bin/env python3
"""Give every inode of an ext2 image to root.

mke2fs -d copies the ownership of the host files it populates an image from, so
a root filesystem built on a Mac arrives owned by whoever ran the build. Vinix
runs as root and enforces Unix permissions, and programs that look at who owns
their home directory notice: Firefox refuses to start with "Running Firefox as
root in a regular user's session is not supported".

The uid and gid live in four fixed fields of each inode, and the images this
builds have no metadata checksums, so the fix is a linear pass over the inode
tables rather than a command per file.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

SUPERBLOCK_OFFSET = 1024
# Offsets within one inode. osd2 holds the high halves of a 32-bit owner.
I_UID = 2
I_GID = 24
I_UID_HIGH = 120
I_GID_HIGH = 122
INCOMPAT_64BIT = 0x0080
ROCOMPAT_METADATA_CSUM = 0x0400


def set_root_owner(path: Path) -> int:
    with path.open("r+b") as image:
        image.seek(SUPERBLOCK_OFFSET)
        superblock = image.read(1024)
        if len(superblock) < 1024:
            raise SystemExit(f"{path}: too small to hold a superblock")
        if struct.unpack_from("<H", superblock, 56)[0] != 0xEF53:
            raise SystemExit(f"{path}: not an ext2 image")

        inodes_count = struct.unpack_from("<I", superblock, 0)[0]
        first_data_block = struct.unpack_from("<I", superblock, 20)[0]
        block_size = 1024 << struct.unpack_from("<I", superblock, 24)[0]
        inodes_per_group = struct.unpack_from("<I", superblock, 40)[0]
        revision = struct.unpack_from("<I", superblock, 76)[0]
        inode_size = struct.unpack_from("<H", superblock, 88)[0] if revision >= 1 else 128
        feature_incompat = struct.unpack_from("<I", superblock, 96)[0]
        feature_ro_compat = struct.unpack_from("<I", superblock, 100)[0]

        if feature_incompat & INCOMPAT_64BIT or feature_ro_compat & ROCOMPAT_METADATA_CSUM:
            raise SystemExit(
                f"{path}: 64-bit or checksummed images need their descriptors rewritten too"
            )
        if inodes_per_group == 0 or inode_size < 128:
            raise SystemExit(f"{path}: implausible inode geometry")

        group_count = (inodes_count + inodes_per_group - 1) // inodes_per_group
        image.seek((first_data_block + 1) * block_size)
        descriptors = image.read(32 * group_count)
        if len(descriptors) < 32 * group_count:
            raise SystemExit(f"{path}: truncated group descriptor table")

        changed = 0
        for group in range(group_count):
            table_block = struct.unpack_from("<I", descriptors, group * 32 + 8)[0]
            remaining = inodes_count - group * inodes_per_group
            count = min(inodes_per_group, remaining)
            image.seek(table_block * block_size)
            table = bytearray(image.read(inode_size * count))
            if len(table) < inode_size * count:
                raise SystemExit(f"{path}: truncated inode table in group {group}")
            for index in range(count):
                base = index * inode_size
                for field in (I_UID, I_GID, I_UID_HIGH, I_GID_HIGH):
                    if struct.unpack_from("<H", table, base + field)[0] != 0:
                        struct.pack_into("<H", table, base + field, 0)
                        changed += 1
            image.seek(table_block * block_size)
            image.write(table)
        return changed


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} IMAGE", file=sys.stderr)
        return 2
    set_root_owner(Path(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
