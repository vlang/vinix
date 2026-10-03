#!/usr/bin/env python3
"""Expose host game files as a read-only ext2 disk without copying their data."""

from __future__ import annotations

import argparse
import bisect
from collections import OrderedDict
from dataclasses import dataclass, field
import errno
import json
import os
from pathlib import Path
import socket
import socketserver
import stat
import struct
import threading
import uuid

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
    return (value + unit - 1) // unit


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
    info = path.lstat()
    if stat.S_ISDIR(info.st_mode):
        node = existing if existing and stat.S_ISDIR(existing.info.st_mode) else Node(path, info)
        node.path, node.info = path, info
        with os.scandir(path) as entries:
            for entry in sorted(entries, key=lambda item: os.fsencode(item.name)):
                name = os.fsencode(entry.name)
                if not name or len(name) > 255:
                    raise ValueError(f"Invalid ext2 filename: {entry.path}")
                node.children[entry.name] = scan(Path(entry.path), node.children.get(entry.name))
        return node
    if stat.S_ISREG(info.st_mode):
        if info.st_size > MAX_FILE:
            raise ValueError(f"Vinix cannot read a file larger than 4 GiB: {path}")
        return Node(path, info)
    if stat.S_ISLNK(info.st_mode):
        return Node(path, info)
    raise ValueError(f"Only directories, regular files and symlinks can be exported: {path}")


def flatten(root: Node) -> list[Node]:
    nodes = [root]
    root.inode, root.parent = 2, 2
    next_inode = 11

    def visit(parent: Node) -> None:
        nonlocal next_inode
        for child in parent.children.values():
            child.inode, child.parent = next_inode, parent.inode
            next_inode += 1
            nodes.append(child)
            visit(child)

    visit(root)
    return nodes


def directory_data(node: Node) -> bytes:
    entries = [(node.inode, b".", 2), (node.parent, b"..", 2)]
    for name, child in node.children.items():
        kind = 2 if stat.S_ISDIR(child.info.st_mode) else 7 if stat.S_ISLNK(child.info.st_mode) else 1
        entries.append((child.inode, os.fsencode(name), kind))
    blocks = []
    block = bytearray(BLOCK)
    offset, previous = 0, None
    for inode, name, kind in entries:
        size = rounded(8 + len(name), 4) * 4
        if offset + size > BLOCK:
            struct.pack_into("<H", block, previous + 4, BLOCK - previous)
            blocks.append(bytes(block))
            block, offset = bytearray(BLOCK), 0
        struct.pack_into("<IHBB", block, offset, inode, size, len(name), kind)
        block[offset + 8:offset + 8 + len(name)] = name
        previous, offset = offset, offset + size
    struct.pack_into("<H", block, previous + 4, BLOCK - previous)
    blocks.append(bytes(block))
    return b"".join(blocks)


def pointer_count(count: int) -> int:
    remaining = max(0, count - 12)
    total = 0
    for level in (1, 2, 3):
        covered = min(remaining, POINTERS ** level)
        if covered:
            total += sum(rounded(covered, POINTERS ** index) for index in range(1, level + 1))
        remaining -= covered
    if remaining:
        raise ValueError("File exceeds ext2's triple-indirect addressing")
    return total


def backup_group(group: int) -> bool:
    if group in (0, 1):
        return True
    for base in (3, 5, 7):
        value = group
        while value and value % base == 0:
            value //= base
        if value == 1:
            return True
    return False


class Builder:
    def __init__(self, state: Path, nodes: list[Node]):
        self.nodes, self.state = nodes, state
        required = 0
        for node in nodes:
            if stat.S_ISDIR(node.info.st_mode):
                count = len(directory_data(node)) // BLOCK
            elif stat.S_ISLNK(node.info.st_mode):
                size = len(os.fsencode(os.readlink(node.path)))
                count = rounded(size, BLOCK) if size > 60 else 0
            else:
                count = rounded(node.info.st_size, BLOCK)
            required += count + pointer_count(count)
        # Group metadata is small; iterate until there is room for all of it.
        self.groups = max(1, rounded(required + 16, GROUP_BLOCKS - 8))
        while True:
            self.inodes_per_group = max(32, rounded(len(nodes) + 9, self.groups * 32) * 32)
            self.gdt_blocks = rounded(self.groups * 32, BLOCK)
            self.table_blocks = self.inodes_per_group * INODE_SIZE // BLOCK
            self.used = []
            self.tables = []
            for group in range(self.groups):
                prefix = 1 + self.gdt_blocks if backup_group(group) else 0
                self.used.append(prefix + 2 + self.table_blocks)
                self.tables.append(group * GROUP_BLOCKS + prefix + 2)
            if self.groups * GROUP_BLOCKS - sum(self.used) >= required:
                break
            self.groups += 1
        self.block_count = self.groups * GROUP_BLOCKS
        if self.block_count > 0xFFFFFFFF or self.inodes_per_group > GROUP_BLOCKS:
            raise ValueError("Export exceeds this ext2 layout's limits")
        self.group = 0
        self.files: list[dict] = []
        self.regions: list[list[int]] = []
        self.fd = os.open(state / "metadata.ext2", os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
        os.ftruncate(self.fd, self.block_count * BLOCK)

    def allocate(self, count: int) -> list[tuple[int, int]]:
        runs = []
        while count:
            if self.group >= self.groups:
                raise ValueError("Export ran out of blocks")
            available = GROUP_BLOCKS - self.used[self.group]
            if not available:
                self.group += 1
                continue
            take = min(count, available)
            runs.append((self.group * GROUP_BLOCKS + self.used[self.group], take))
            self.used[self.group] += take
            count -= take
        return runs

    def write(self, offset: int, data: bytes) -> None:
        while data:
            written = os.pwrite(self.fd, data, offset)
            if not written:
                raise OSError("Short metadata write")
            offset += written
            data = data[written:]

    def address_tree(self, runs: list[tuple[int, int]]) -> tuple[list[int], int]:
        def blocks():
            for start, count in runs:
                yield from range(start, start + count)

        iterator = iter(blocks())
        count = sum(length for _, length in runs)
        pointers = [next(iterator) for _ in range(min(count, 12))]
        pointers += [0] * (12 - len(pointers))
        indirect = 0

        def tree(level: int, length: int) -> int:
            nonlocal indirect
            block = self.allocate(1)[0][0]
            indirect += 1
            if level == 1:
                values = [next(iterator) for _ in range(length)]
            else:
                values = [tree(level - 1, min(POINTERS ** (level - 1), length - offset))
                          for offset in range(0, length, POINTERS ** (level - 1))]
            values += [0] * (POINTERS - len(values))
            self.write(block * BLOCK, struct.pack("<1024I", *values))
            return block

        remaining = max(0, count - 12)
        for level in (1, 2, 3):
            take = min(remaining, POINTERS ** level)
            pointers.append(tree(level, take) if take else 0)
            remaining -= take
        return pointers, indirect

    def add_node(self, node: Node) -> None:
        mode = node.info.st_mode & 0xFFFF & ~0o222
        data = None
        inline = None
        if stat.S_ISDIR(mode):
            data = directory_data(node)
            size = len(data)
            links = 2 + sum(stat.S_ISDIR(child.info.st_mode) for child in node.children.values())
        elif stat.S_ISLNK(mode):
            data = os.fsencode(os.readlink(node.path))
            size, links = len(data), 1
            if size <= 60:
                inline, data = data, None
        else:
            size, links = node.info.st_size, 1
        count = 0 if inline is not None else rounded(size, BLOCK)
        runs = self.allocate(count)
        if data is not None:
            position = 0
            for start, length in runs:
                chunk = data[position:position + length * BLOCK]
                self.write(start * BLOCK, chunk)
                position += length * BLOCK
        elif stat.S_ISREG(mode):
            index = len(self.files)
            self.files.append({"path": str(node.path), "identity": identity(node.info)})
            position = 0
            for start, length in runs:
                self.regions.append([start * BLOCK, length * BLOCK, index, position])
                position += length * BLOCK
        pointers, indirect = self.address_tree(runs)
        inode = bytearray(INODE_SIZE)
        timestamp = max(0, min(0xFFFFFFFF, int(node.info.st_mtime)))
        struct.pack_into("<HHIIIIIHHIII", inode, 0, mode, 0, size, timestamp,
                         timestamp, timestamp, 0, 0, links, (count + indirect) * 8, 0, 0)
        if inline is not None:
            inode[40:40 + len(inline)] = inline
        else:
            struct.pack_into("<15I", inode, 40, *pointers)
        group, index = divmod(node.inode - 1, self.inodes_per_group)
        self.write(self.tables[group] * BLOCK + index * INODE_SIZE, inode)

    def finish(self) -> dict:
        try:
            for node in self.nodes:
                self.add_node(node)
            gdt = bytearray(self.gdt_blocks * BLOCK)
            last_inode = len(self.nodes) + 9
            directory_counts = [0] * self.groups
            for node in self.nodes:
                if stat.S_ISDIR(node.info.st_mode):
                    directory_counts[(node.inode - 1) // self.inodes_per_group] += 1
            free_inodes = 0
            for group in range(self.groups):
                prefix = 1 + self.gdt_blocks if backup_group(group) else 0
                base = group * GROUP_BLOCKS
                used_inodes = max(0, min(self.inodes_per_group, last_inode - group * self.inodes_per_group))
                free = self.inodes_per_group - used_inodes
                free_inodes += free
                struct.pack_into("<IIIHHH", gdt, group * 32, base + prefix, base + prefix + 1,
                                 self.tables[group], GROUP_BLOCKS - self.used[group], free, directory_counts[group])
                bitmap = bytearray(BLOCK)
                full, tail = divmod(self.used[group], 8)
                bitmap[:full] = b"\xff" * full
                if tail:
                    bitmap[full] = (1 << tail) - 1
                self.write((base + prefix) * BLOCK, bitmap)
                bitmap = bytearray(b"\xff" * BLOCK)
                for index in range(used_inodes, self.inodes_per_group):
                    bitmap[index // 8] &= ~(1 << (index % 8))
                self.write((base + prefix + 1) * BLOCK, bitmap)
            superblock = bytearray(1024)
            struct.pack_into("<11I", superblock, 0, self.groups * self.inodes_per_group,
                             self.block_count, 0, self.block_count - sum(self.used), free_inodes,
                             0, 2, 2, GROUP_BLOCKS, GROUP_BLOCKS, self.inodes_per_group)
            struct.pack_into("<HHHHHH", superblock, 52, 0, 0xFFFF, 0xEF53, 1, 1, 0)
            struct.pack_into("<IIIIHH", superblock, 64, 0, 0, 0, 1, 0, 0)
            struct.pack_into("<IHHIII", superblock, 84, 11, INODE_SIZE, 0, 0, 2, 3)
            superblock[104:120] = uuid.uuid4().bytes
            superblock[120:136] = b"Vinix game data\x00"
            for group in range(self.groups):
                if backup_group(group):
                    struct.pack_into("<H", superblock, 90, group)
                    self.write(group * GROUP_BLOCKS * BLOCK + (1024 if group == 0 else 0), superblock)
                    self.write((group * GROUP_BLOCKS + 1) * BLOCK, gdt)
            os.fsync(self.fd)
            manifest = {"version": 1, "size": self.block_count * BLOCK,
                        "files": self.files, "regions": sorted(self.regions)}
            with (self.state / "manifest.json").open("x") as output:
                json.dump(manifest, output, separators=(",", ":"))
            return manifest
        finally:
            os.close(self.fd)


def build(source: Path, state: Path, overlays: list[Path] = ()) -> dict:
    state = state.resolve()
    roots = [source.resolve(), *(path.resolve() for path in overlays)]
    for path in roots:
        if not path.is_dir():
            raise ValueError(f"Export root is not a directory: {path}")
        if state.is_relative_to(path):
            raise ValueError("Metadata directory must be outside every exported root")
    root = scan(roots[0])
    for path in roots[1:]:
        root = scan(path, root)
    nodes = flatten(root)
    state.mkdir(parents=True, exist_ok=True)
    if (state / "metadata.ext2").exists() or (state / "manifest.json").exists():
        raise ValueError("Use a fresh export state directory")
    return Builder(state, nodes).finish()


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


if __name__ == "__main__":
    main()
