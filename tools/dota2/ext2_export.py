#!/usr/bin/env python3
"""Expose host game files as a read-only ext2 disk without copying their data."""

from __future__ import annotations

import argparse
import bisect
from collections import OrderedDict
from dataclasses import dataclass, field
import errno
import importlib.util
import json
import os
from pathlib import Path
import socket
import socketserver
import stat
import struct
import threading
import uuid

_NATIVE_SPEC = importlib.util.spec_from_file_location("ext2_native", Path(__file__).with_name("_ext2_native.py"))
_NATIVE = importlib.util.module_from_spec(_NATIVE_SPEC)
_NATIVE_SPEC.loader.exec_module(_NATIVE)

BLOCK = 4096
GROUP_BLOCKS = BLOCK * 8
POINTERS = BLOCK // 4
INODE_SIZE = 128
MAX_FILE = 0xFFFFFFFF  # Vinix's inode.read still clamps to size32l.
MAX_REQUEST = 32 * 1024 * 1024
NBD_MAGIC = 0x4E42444D41474943
OPTION_MAGIC = 0x49484156454F5054
REPLY_MAGIC = 0x3E889045565A9
REQUEST_MAGIC = 0x25609513
EXPORT_FLAGS = 3  # HAS_FLAGS | READ_ONLY


def rounded(value: int, unit: int) -> int:
    return _NATIVE.call('rounded', (value, unit), globals())


def identity(info: os.stat_result) -> list[int]:
    return _NATIVE.call('identity', (info,), globals())


def same_source(info: os.stat_result, recorded: list[int]) -> bool:
    # macOS can number a volume differently after a restart. The inode, size
    # and both timestamps still identify an unchanged file on that volume.
    return _NATIVE.call('same_source', (info, recorded), globals())


@dataclass
class Node:
    path: Path
    info: os.stat_result
    children: dict[str, "Node"] = field(default_factory=dict)
    inode: int = 0
    parent: int = 0


def scan(path: Path, existing: Node | None = None) -> Node:
    return _NATIVE.call('scan', (path, existing), globals())


def flatten(root: Node) -> list[Node]:
    return _NATIVE.call('flatten', (root,), globals())


def directory_data(node: Node) -> bytes:
    return _NATIVE.call('directory_data', (node,), globals())


def pointer_count(count: int) -> int:
    return _NATIVE.call('pointer_count', (count,), globals())


def backup_group(group: int) -> bool:
    return _NATIVE.call('backup_group', (group,), globals())


class Builder:
    def __init__(self, state: Path, nodes: list[Node]):
        _NATIVE.call("initialize", (self, state, nodes), globals())
        self.fd = os.open(state / "metadata.ext2", os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
        os.ftruncate(self.fd, self.block_count * BLOCK)

    def allocate(self, count: int) -> list[tuple[int, int]]:
        return _NATIVE.call('allocate', (self, count), globals())

    def write(self, offset: int, data: bytes) -> None:
        return _NATIVE.call('write', (self, offset, data), globals())

    def address_tree(self, runs: list[tuple[int, int]]) -> tuple[list[int], int]:
        return _NATIVE.call('address_tree', (self, runs), globals())

    def add_node(self, node: Node) -> None:
        return _NATIVE.call('add_node', (self, node), globals())

    def finish(self) -> dict:
        return _NATIVE.call('finish', (self,), globals())


def build(source: Path, state: Path, overlays: list[Path] = ()) -> dict:
    return _NATIVE.call('build', (source, state, overlays), globals())


class Export:
    def __init__(self, state: Path):
        return _NATIVE.call('export_initialize', (self, state), globals())

    def close(self) -> None:
        return _NATIVE.call('close', (self,), globals())

    def read_source(self, index: int, offset: int, count: int) -> bytes:
        # Bound descriptors while rejecting an updated or replaced host file.
        return _NATIVE.call('read_source', (self, index, offset, count), globals())

    def read(self, offset: int, count: int) -> bytes:
        return _NATIVE.call('read', (self, offset, count), globals())


def receive(connection: socket.socket, count: int) -> bytes:
    return _NATIVE.call('receive', (connection, count), globals())


class Handler(socketserver.BaseRequestHandler):
    def option_reply(self, option: int, kind: int, data: bytes = b"") -> None:
        return _NATIVE.call('option_reply', (self, option, kind, data), globals())

    def negotiate(self) -> bool:
        return _NATIVE.call('negotiate', (self,), globals())

    def handle(self) -> None:
        return _NATIVE.call('handle', (self,), globals())


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    block_on_close = False

    def __init__(self, state: Path, port: int, export_name: str = ""):
        self.export = Export(state)
        self.export_name = export_name.encode()
        try:
            super().__init__(("127.0.0.1", port), Handler)
        except BaseException:
            self.export.close()
            raise

    def server_close(self) -> None:
        super().server_close()
        self.export.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("build", help="Write metadata and a host-file map")
    create.add_argument("source", type=Path)
    create.add_argument("--overlay", type=Path, action="append", default=[])
    create.add_argument("--state", type=Path, required=True)
    serve = commands.add_parser("serve", help="Serve the metadata and unchanged host files")
    serve.add_argument("--state", type=Path, required=True)
    serve.add_argument("--port", type=int, default=10809)
    serve.add_argument("--export-name", default="")
    args = parser.parse_args()
    if args.command == "build":
        manifest = build(args.source, args.state, args.overlay)
        stored = (args.state / "metadata.ext2").stat().st_blocks * 512
        print(f"Exported {len(manifest['files'])} files; disk size {manifest['size']} bytes; metadata storage {stored} bytes")
    else:
        with Server(args.state, args.port, args.export_name) as server:
            name = f"/{args.export_name}" if args.export_name else "/"
            print(f"Read-only ext2: nbd://127.0.0.1:{server.server_address[1]}{name}", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass


_NATIVE.bind(globals())


if __name__ == "__main__":
    main()
