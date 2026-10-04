#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and verify headerless SHA-256 Merkle block images for Vinix."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from typing import BinaryIO


BLOCK_SIZE = 4096
DIGEST_SIZE = 32
HASHES_PER_BLOCK = BLOCK_SIZE // DIGEST_SIZE
MAX_BYTES = (1 << 63) - 1
FORMAT = "dm-verity-v1-sha256-4096-no-salt-no-superblock"
TOKEN_PREFIX = "vinix.verity="


class InvalidImage(ValueError):
    pass


def layout(data_blocks: int) -> list[tuple[int, int]]:
    """Return (image block offset, block count) for each level, leaf first.

    Hash levels are physically root first. A one-data-block image has no
    tree; its root digest is the hash of the data block, as in dm-verity v1.
    """
    if (isinstance(data_blocks, bool) or not isinstance(data_blocks, int)
            or not 1 <= data_blocks <= MAX_BYTES // BLOCK_SIZE):
        raise InvalidImage("data block count must be a positive, bounded integer")
    counts = []
    children = data_blocks
    while children > 1:
        children = (children + HASHES_PER_BLOCK - 1) // HASHES_PER_BLOCK
        counts.append(children)
    position = data_blocks
    levels = []
    for count in reversed(counts):
        levels.append((position, count))
        position += count
    if position > MAX_BYTES // BLOCK_SIZE:
        raise InvalidImage("data and hash tree exceed the supported device size")
    return list(reversed(levels))


def root_hash(value: str) -> bytes:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise InvalidImage("root hash must be exactly 64 lowercase hexadecimal digits")
    return bytes.fromhex(value)


def device_name(value: str) -> str:
    # No traversal, aliases, whitespace, partitions separated with slashes,
    # or delimiters. The kernel selects this exact device, never scans disks.
    if not isinstance(value, str) or not re.fullmatch(r"/dev/[A-Za-z0-9][A-Za-z0-9_.-]{0,62}", value):
        raise InvalidImage("device must be an exact /dev block-device path")
    return value


def command_line(device: str, data_blocks: int, digest: str) -> str:
    layout(data_blocks)
    root_hash(digest)
    return f"{TOKEN_PREFIX}1,{device_name(device)},{data_blocks},{digest}"


def parse_command_line(token: str) -> tuple[str, int, str]:
    match = re.fullmatch(r"vinix\.verity=1,(/dev/[A-Za-z0-9_.-]+),([1-9][0-9]*),([0-9a-f]{64})", token)
    if not match:
        raise InvalidImage("invalid verified-root command-line token")
    device, count, digest = match.groups()
    try:
        blocks = int(count)
    except ValueError as error:
        raise InvalidImage("invalid verified-root data block count") from error
    if command_line(device, blocks, digest) != token:
        raise InvalidImage("noncanonical verified-root command-line token")
    return device, blocks, digest


def regular(path: Path) -> Path:
    if path.is_symlink() or not path.is_file():
        raise InvalidImage(f"input must be a regular file, without a leaf symlink: {path}")
    return path


def read_block(stream: BinaryIO, offset: int) -> bytes:
    stream.seek(offset * BLOCK_SIZE)
    data = stream.read(BLOCK_SIZE)
    if len(data) != BLOCK_SIZE:
        raise InvalidImage(f"short read at image block {offset}")
    return data


def hash_block(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def total_blocks(data_blocks: int) -> int:
    return data_blocks + sum(count for _, count in layout(data_blocks))


def verify(path: Path, data_blocks: int, digest: str) -> None:
    """Scrub every data and hash block against separately trusted N/root.

    This verifies the stored hash blocks, rather than trusting a regenerated
    tree alone. Unused slots must be canonical zero padding. Size is exact.
    Memory use is bounded to a few blocks irrespective of the image size.
    """
    expected = root_hash(digest)
    levels = layout(data_blocks)
    regular(path)
    expected_size = total_blocks(data_blocks) * BLOCK_SIZE
    with path.open("rb") as stream:
        if os.fstat(stream.fileno()).st_size != expected_size:
            raise InvalidImage("image size differs from its trusted data/tree geometry")
        if not levels:
            if hash_block(read_block(stream, 0)) != expected:
                raise InvalidImage("data block 0 differs from the trusted root hash")
            if os.fstat(stream.fileno()).st_size != expected_size:
                raise InvalidImage("image size changed during verification")
            return
        children_offset, children_count = 0, data_blocks
        for offset, count in levels:
            for index in range(count):
                stored = read_block(stream, offset + index)
                used = min(HASHES_PER_BLOCK, children_count - index * HASHES_PER_BLOCK)
                for slot in range(used):
                    child = children_offset + index * HASHES_PER_BLOCK + slot
                    if hash_block(read_block(stream, child)) != stored[slot * DIGEST_SIZE:(slot + 1) * DIGEST_SIZE]:
                        raise InvalidImage(f"hash mismatch for image block {child}")
                if any(stored[used * DIGEST_SIZE:]):
                    raise InvalidImage(f"nonzero unused hash slots in image block {offset + index}")
            children_offset, children_count = offset, count
        if hash_block(read_block(stream, levels[-1][0])) != expected:
            raise InvalidImage("hash tree differs from the trusted root hash")
        if os.fstat(stream.fileno()).st_size != expected_size:
            raise InvalidImage("image size changed during verification")


def build(source: Path, output: Path, pad: bool = False) -> dict:
    """Create a new image from operator-trusted data; never alter the input."""
    regular(source)
    output = output.absolute()
    if output.exists() or output.is_symlink():
        raise InvalidImage("output already exists; choose a new image path")
    output.parent.mkdir(parents=True, exist_ok=True)
    size = source.stat().st_size
    if not size or (size % BLOCK_SIZE and not pad):
        raise InvalidImage("data must be nonempty and 4096-byte aligned (or use --pad explicitly)")
    data_blocks = (size + BLOCK_SIZE - 1) // BLOCK_SIZE
    levels = layout(data_blocks)
    with tempfile.TemporaryDirectory(prefix=".vinix-verity-", dir=output.parent) as temporary:
        work = Path(temporary)
        image = work / "image"
        with source.open("rb") as incoming, image.open("wb") as outgoing:
            shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
            if outgoing.tell() != size:
                raise InvalidImage("input size changed while copying")
            outgoing.write(b"\0" * (data_blocks * BLOCK_SIZE - size))
        if not levels:
            with image.open("rb") as stream:
                digest = hash_block(read_block(stream, 0)).hex()
        else:
            previous = image
            children = data_blocks
            files = []
            for level, (_, count) in enumerate(levels):
                current = work / f"level-{level}"
                with previous.open("rb") as incoming, current.open("wb") as outgoing:
                    for index in range(count):
                        hashes = bytearray(BLOCK_SIZE)
                        used = min(HASHES_PER_BLOCK, children - index * HASHES_PER_BLOCK)
                        for slot in range(used):
                            data = incoming.read(BLOCK_SIZE)
                            if len(data) != BLOCK_SIZE:
                                raise InvalidImage("short read while constructing hash tree")
                            hashes[slot * DIGEST_SIZE:(slot + 1) * DIGEST_SIZE] = hash_block(data)
                        outgoing.write(hashes)
                files.append(current)
                previous, children = current, count
            with previous.open("rb") as stream:
                digest = hash_block(read_block(stream, 0)).hex()
            with image.open("ab") as outgoing:
                for path in reversed(files):
                    with path.open("rb") as incoming:
                        shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
        verify(image, data_blocks, digest)
        # Linking the completed file publishes atomically and cannot replace a
        # concurrently created output. The temporary is on the same filesystem.
        os.link(image, output)
    return {"format": FORMAT, "data_blocks": data_blocks, "root_hash": digest,
            "block_size": BLOCK_SIZE, "tree_blocks": total_blocks(data_blocks) - data_blocks,
            "image_bytes": total_blocks(data_blocks) * BLOCK_SIZE,
            "source_bytes": size}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="operation", required=True)
    create = commands.add_parser("build", help="append a Merkle tree to operator-trusted data")
    create.add_argument("--data", type=Path, required=True, help="completed read-only ext2 image or aligned data")
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--pad", action="store_true", help="explicitly pad the final data block with zeroes")
    check = commands.add_parser("verify", help="scrub the entire image against a separately trusted root")
    check.add_argument("image", type=Path)
    token = commands.add_parser("command-line", help="format the token to authenticate in boot policy")
    token.add_argument("--device", required=True)
    for command in (check, token):
        command.add_argument("--data-blocks", type=int, required=True)
        command.add_argument("--root-hash", required=True)
    args = parser.parse_args()
    try:
        if args.operation == "build":
            print(json.dumps(build(args.data, args.output, args.pad), sort_keys=True, indent=2))
        elif args.operation == "verify":
            verify(args.image, args.data_blocks, args.root_hash)
            print("All data and hash blocks verified against the supplied root.")
        else:
            print(command_line(args.device, args.data_blocks, args.root_hash))
    except (InvalidImage, OSError) as error:
        parser.exit(1, f"ERROR: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
