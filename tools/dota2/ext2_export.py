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
    return [info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns]


def same_source(info: os.stat_result, recorded: list[int]) -> bool:
    # macOS can number a volume differently after a restart. The inode, size
    # and both timestamps still identify an unchanged file on that volume.
    return identity(info)[1:] == recorded[1:]


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
        manifest = json.loads((state / "manifest.json").read_text())
        if manifest["version"] != 1:
            raise ValueError("Unsupported export manifest")
        self.size = manifest["size"]
        self.files, self.regions = manifest["files"], manifest["regions"]
        self.starts = [region[0] for region in self.regions]
        self.metadata = os.open(state / "metadata.ext2", os.O_RDONLY)
        self.open_files: OrderedDict[int, int] = OrderedDict()
        self.lock = threading.Lock()

    def close(self) -> None:
        with self.lock:
            for fd in self.open_files.values():
                os.close(fd)
            self.open_files.clear()
            os.close(self.metadata)

    def read_source(self, index: int, offset: int, count: int) -> bytes:
        # Bound descriptors while rejecting an updated or replaced host file.
        with self.lock:
            entry = self.files[index]
            fd = self.open_files.pop(index, None)
            if fd is None:
                fd = os.open(entry["path"], os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            self.open_files[index] = fd
            while len(self.open_files) > 64:
                _, expired = self.open_files.popitem(last=False)
                os.close(expired)
            if not same_source(os.fstat(fd), entry["identity"]):
                raise OSError(errno.EIO, f"Source changed; rebuild the export: {entry['path']}")
            size = entry["identity"][2]
            wanted = max(0, min(count, size - offset))
            result = os.pread(fd, wanted, offset)
            if len(result) != wanted or not same_source(os.fstat(fd), entry["identity"]):
                raise OSError(errno.EIO, f"Source changed while reading: {entry['path']}")
            return result + bytes(count - wanted)

    def read(self, offset: int, count: int) -> bytes:
        if offset < 0 or count < 0 or count > MAX_REQUEST or offset + count > self.size:
            raise OSError(errno.EINVAL, "Invalid disk read range")
        output = []
        end = offset + count
        while offset < end:
            index = bisect.bisect_right(self.starts, offset) - 1
            if index >= 0 and offset < self.regions[index][0] + self.regions[index][1]:
                start, length, source, source_offset = self.regions[index]
                length = min(end - offset, start + length - offset)
                output.append(self.read_source(source, source_offset + offset - start, length))
            else:
                next_index = index + 1
                boundary = self.starts[next_index] if next_index < len(self.starts) else self.size
                length = min(end - offset, boundary - offset)
                data = os.pread(self.metadata, length, offset)
                if len(data) != length:
                    raise OSError(errno.EIO, "Short metadata read")
                output.append(data)
            offset += length
        return b"".join(output)


def receive(connection: socket.socket, count: int) -> bytes:
    parts = []
    while count:
        part = connection.recv(count)
        if not part:
            raise EOFError
        parts.append(part)
        count -= len(part)
    return b"".join(parts)


class Handler(socketserver.BaseRequestHandler):
    def option_reply(self, option: int, kind: int, data: bytes = b"") -> None:
        self.request.sendall(struct.pack(">QIII", REPLY_MAGIC, option, kind, len(data)) + data)

    def negotiate(self) -> bool:
        self.request.sendall(struct.pack(">QQH", NBD_MAGIC, OPTION_MAGIC, 3))
        flags, = struct.unpack(">I", receive(self.request, 4))
        if not flags & 1 or flags & ~3:
            return False
        for _ in range(64):
            magic, option, length = struct.unpack(">QII", receive(self.request, 16))
            if magic != OPTION_MAGIC or length > 65536:
                return False
            data = receive(self.request, length)
            if option == 2:  # ABORT
                self.option_reply(option, 1)
                return False
            if option == 1:  # EXPORT_NAME
                if data != self.server.export_name:
                    return False
                self.request.sendall(struct.pack(">QH", self.server.export.size, EXPORT_FLAGS))
                if not flags & 2:
                    self.request.sendall(bytes(124))
                return True
            if option == 3:  # LIST
                name = self.server.export_name
                self.option_reply(option, 2, struct.pack(">I", len(name)) + name)
                self.option_reply(option, 1)
            elif option in (6, 7):  # INFO / GO
                if len(data) < 6:
                    self.option_reply(option, 0x80000003)
                    continue
                name_length, = struct.unpack_from(">I", data)
                if name_length > len(data) - 6:
                    self.option_reply(option, 0x80000003)
                    continue
                name = data[4:4 + name_length]
                infos, = struct.unpack_from(">H", data, 4 + name_length)
                if len(data) != name_length + 6 + infos * 2:
                    self.option_reply(option, 0x80000003)
                elif name != self.server.export_name:
                    self.option_reply(option, 0x80000006)
                else:
                    self.option_reply(option, 3, struct.pack(">HQH", 0, self.server.export.size, EXPORT_FLAGS))
                    requested = struct.unpack_from(f">{infos}H", data, 6 + name_length)
                    if 3 in requested:
                        self.option_reply(option, 3, struct.pack(">HIII", 3, 1, BLOCK, MAX_REQUEST))
                    self.option_reply(option, 1)
                    if option == 7:
                        return True
            else:
                self.option_reply(option, 0x80000001)
        return False

    def handle(self) -> None:
        self.request.settimeout(120)
        self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            if not self.negotiate():
                return
            # The guest can spend minutes compiling shaders between reads.
            # Keep the handshake bounded, then let the negotiated disk remain
            # available until the client disconnects.
            self.request.settimeout(None)
            while True:
                magic, flags, command, handle, offset, length = struct.unpack(">IHH8sQI", receive(self.request, 28))
                if magic != REQUEST_MAGIC or length > MAX_REQUEST:
                    return
                if command == 2:  # DISC
                    return
                error, data = 0, b""
                if command == 1:  # Consume WRITE payload before rejecting it.
                    receive(self.request, length)
                    error = errno.EROFS
                elif flags:
                    error = errno.EINVAL
                elif command == 0:
                    try:
                        data = self.server.export.read(offset, length)
                    except OSError as exc:
                        error = exc.errno or errno.EIO
                elif command == 3:  # FLUSH on a read-only export.
                    pass
                else:
                    error = errno.EROFS if command in (4, 6) else errno.EINVAL
                self.request.sendall(struct.pack(">II8s", 0x67446698, error, handle) + data)
        except (EOFError, ConnectionError, socket.timeout):
            pass


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
