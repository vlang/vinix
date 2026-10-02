#!/usr/bin/env python3
"""Validate exported ext2 with e2fsprogs and exercise NBD with the QEMU client."""
from __future__ import annotations

import errno
import importlib.util
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ext2_export", ROOT / "tools/dota2/ext2_export.py")
EXPORTER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = EXPORTER
SPEC.loader.exec_module(EXPORTER)


def executable(name: str) -> str:
    candidate = shutil.which(name) or f"/opt/homebrew/opt/e2fsprogs/sbin/{name}"
    if not Path(candidate).is_file():
        raise unittest.SkipTest(f"{name} is required")
    return candidate


class Client:
    def __init__(self, port: int):
        self.connection = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.connection.settimeout(10)
        self.assert_magic = struct.unpack(">QQH", EXPORTER.receive(self.connection, 18))
        assert self.assert_magic == (EXPORTER.NBD_MAGIC, EXPORTER.OPTION_MAGIC, 3)
        self.connection.sendall(struct.pack(">I", 3))
        self.connection.sendall(struct.pack(">QII", EXPORTER.OPTION_MAGIC, 1, 0))
        self.size, self.flags = struct.unpack(">QH", EXPORTER.receive(self.connection, 10))

    def request(self, command: int, offset: int, length: int, data: bytes = b""):
        self.connection.sendall(struct.pack(">IHH8sQI", EXPORTER.REQUEST_MAGIC, 0, command,
                                            b"testcase", offset, length) + data)
        magic, error, handle = struct.unpack(">II8s", EXPORTER.receive(self.connection, 16))
        assert magic == 0x67446698 and handle == b"testcase"
        return error, EXPORTER.receive(self.connection, length) if command == 0 and not error else b""

    def close(self):
        self.connection.close()


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-export-test-")
        self.base = Path(self.temporary.name)
        self.source = self.base / "source"
        self.source.mkdir()
        (self.source / "nested").mkdir()
        (self.source / "empty").touch()
        (self.source / "short-link").symlink_to("nested/package.vpk")
        (self.source / "long-link").symlink_to("nested/" + "x" * 90)
        (self.source / 'a "quoted" café').write_bytes(b"filename test")
        self.package = self.source / "nested/package.vpk"
        self.patterns = [(0, 0xA5), (12 * 4096 - 127, 0xB6),
                         ((12 + 1024) * 4096 - 127, 0xC7), (128 * 1024 * 1024 - 127, 0xD8)]
        with self.package.open("wb") as output:
            output.truncate(130 * 1024 * 1024 + 13)
            for offset, pattern in self.patterns:
                output.seek(offset)
                output.write(bytes([pattern]) * 8192)
            output.seek(-13, os.SEEK_END)
            output.write(b"partial block")
        overlay = self.base / "overlay"
        (overlay / "nested").mkdir(parents=True)
        (overlay / "nested/loader").write_bytes(b"overlay executable")
        (overlay / "nested/loader").chmod(0o755)
        (overlay / "empty").write_bytes(b"replaced")
        self.state = self.base / "state"
        self.manifest = EXPORTER.build(self.source, self.state, [overlay])
        self.export = EXPORTER.Export(self.state)

    def tearDown(self):
        self.export.close()
        self.temporary.cleanup()

    def bmap(self, path: str, block: int) -> int:
        output = subprocess.check_output([executable("debugfs"), "-R", f"bmap /{path} {block}",
                                          str(self.state / "metadata.ext2")], text=True, stderr=subprocess.DEVNULL)
        return int(output.strip())

    def test_valid_layout_and_qemu_reads(self):
        subprocess.run([executable("e2fsck"), "-fn", str(self.state / "metadata.ext2")], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Sparse host package is 130 MiB, but neither it nor export metadata
        # consumes that size. This catches accidental payload materialisation.
        self.assertLess((self.state / "metadata.ext2").stat().st_blocks * 512, 2 * 1024 * 1024)
        self.assertLess(self.package.stat().st_blocks * 512, 128 * 1024)
        self.assertEqual(self.manifest["size"], 256 * 1024 * 1024)
        with EXPORTER.Server(self.state, 0) as server:
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            try:
                uri = f"nbd://127.0.0.1:{server.server_address[1]}/"
                arguments = [executable("qemu-io"), "-r", "-f", "raw"]
                for offset, pattern in self.patterns:
                    # Resolve each page through debugfs, independently of the
                    # builder's region map. Reads straddle indirect boundaries.
                    remaining = 8192
                    while remaining:
                        block, inside = divmod(offset, 4096)
                        take = min(4096 - inside, remaining)
                        disk = self.bmap("nested/package.vpk", block) * 4096 + inside
                        arguments += ["-c", f"read -P {pattern} {disk} {take}"]
                        offset += take
                        remaining -= take
                subprocess.run(arguments + [uri], check=True, stdout=subprocess.DEVNULL)
            finally:
                server.shutdown()
                thread.join()

    def test_partial_block_overlay_and_symlinks(self):
        size = self.package.stat().st_size
        block = self.bmap("nested/package.vpk", size // 4096)
        self.assertEqual(self.export.read(block * 4096, 4096), b"partial block" + bytes(4096 - 13))
        loader = self.bmap("nested/loader", 0)
        self.assertEqual(self.export.read(loader * 4096, 18), b"overlay executable")
        empty = self.bmap("empty", 0)
        self.assertEqual(self.export.read(empty * 4096, 8), b"replaced")
        for name, target in (("short-link", "nested/package.vpk"), ("long-link", "nested/" + "x" * 90)):
            result = subprocess.check_output([executable("debugfs"), "-R", f"stat /{name}",
                                              str(self.state / "metadata.ext2")], text=True, stderr=subprocess.DEVNULL)
            self.assertIn("Type: symlink", result)
            if name == "short-link":
                self.assertIn(target, result)
            else:
                block = self.bmap(name, 0)
                self.assertEqual(self.export.read(block * 4096, len(target)), target.encode())

    def test_readonly_protocol_and_source_change(self):
        block = self.bmap("nested/package.vpk", 0)
        original = bytes([0xA5]) * 16
        with EXPORTER.Server(self.state, 0) as server:
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            client = Client(server.server_address[1])
            try:
                self.assertEqual(client.flags & 2, 2)
                self.assertEqual(client.request(0, block * 4096, 16), (0, original))
                self.assertEqual(client.request(1, block * 4096, 16, b"X" * 16)[0], errno.EROFS)
                self.assertEqual(client.request(0, block * 4096, 16), (0, original))
                self.assertEqual(client.request(0, client.size - 1, 2)[0], errno.EINVAL)
                with self.package.open("r+b") as output:
                    output.write(b"changed")
                self.assertEqual(client.request(0, block * 4096, 16)[0], errno.EIO)
            finally:
                client.close()
                server.shutdown()
                thread.join()

    def test_refuse_oversized_file_and_nested_state(self):
        with self.assertRaisesRegex(ValueError, "outside every exported root"):
            EXPORTER.build(self.source, self.source / "export")
        with (self.source / "too-large").open("wb") as output:
            output.truncate(1 << 32)
        with self.assertRaisesRegex(ValueError, "larger than 4 GiB"):
            EXPORTER.build(self.source, self.base / "oversized")


if __name__ == "__main__":
    unittest.main()
