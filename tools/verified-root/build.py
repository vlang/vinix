#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and verify headerless SHA-256 Merkle block images for Vinix."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
from typing import BinaryIO

_spec = importlib.util.spec_from_file_location("vinix_verity_native", Path(__file__).with_name("_native.py"))
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)
BLOCK_SIZE = 4096
DIGEST_SIZE = 32
HASHES_PER_BLOCK = BLOCK_SIZE // DIGEST_SIZE
MAX_BYTES = (1 << 63) - 1
FORMAT = "dm-verity-v1-sha256-4096-no-salt-no-superblock"
TOKEN_PREFIX = "vinix.verity="

class InvalidImage(ValueError):
    pass

def _call(operation, **fields):
    try:
        return _native.request(operation, **fields)
    except ValueError as error:
        raise InvalidImage(str(error)) from error

def layout(data_blocks: int) -> list[tuple[int, int]]:
    return [tuple(level) for level in _call("layout", data_blocks=data_blocks)]

def root_hash(value: str) -> bytes:
    return bytes.fromhex(_call("root_hash", value=value))

def device_name(value: str) -> str:
    return _call("device_name", value=value)

def command_line(device: str, data_blocks: int, digest: str) -> str:
    return _call("command_line", device=device, data_blocks=data_blocks, digest=digest)

def parse_command_line(token: str) -> tuple[str, int, str]:
    return tuple(_call("parse_command_line", token=token))

def regular(path: Path) -> Path:
    _call("regular", path=str(path))
    return path

def read_block(stream: BinaryIO, offset: int) -> bytes:
    stream.seek(offset * BLOCK_SIZE)
    data = stream.read(BLOCK_SIZE)
    if len(data) != BLOCK_SIZE:
        raise InvalidImage(f"short read at image block {offset}")
    return data

def hash_block(data: bytes) -> bytes:
    return bytes.fromhex(_call("hash_block", data=memoryview(data).hex()))

def total_blocks(data_blocks: int) -> int:
    return _call("total_blocks", data_blocks=data_blocks)

def verify(path: Path, data_blocks: int, digest: str) -> None:
    _call("verify", path=str(path), data_blocks=data_blocks, digest=digest)

def build(source: Path, output: Path, pad: bool = False) -> dict:
    return _call("build", source=str(source), output=str(output), pad=bool(pad))


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
