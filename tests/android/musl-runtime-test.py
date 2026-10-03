#!/usr/bin/env python3
"""Check Android's private allocator provider and source-build receipt."""
from __future__ import annotations

from copy import deepcopy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "android_musl_runtime", ROOT / "build-support/android/musl-runtime.py")
assert spec and spec.loader
musl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(musl)


def elf(machine: int = 183, offset: int = 0) -> bytes:
    """A complete load-segment fixture accepted by the real ELF validator."""
    size = max(256, offset + 128)
    data = bytearray(size)
    data[:16] = b"\x7fELF\x02\x01\x01" + bytes(9)
    struct.pack_into("<HHIQQQIHHHHHH", data, 16,
                     3, machine, 1, 0x400080, 64, 0, 0, 64, 56, 1, 0, 0, 0)
    struct.pack_into("<IIQQQQQQ", data, 64,
                     1, 5, offset, 0x400000, 0, size - offset, size - offset, 65536)
    return bytes(data)


class RuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        self.manifest = {
            "version": "1.2.6", "arch": "aarch64",
            "source_sha256": musl.SOURCE_SHA256,
            "source_url": "https://musl.libc.org/releases/musl-1.2.6.tar.gz",
            "patches": musl.source_patches(), "retention": 1,
            "cflags": "-fstack-protector-strong -DVINIX_MALLOC_RETAIN=1",
            "ldflags": "-Wl,-soname,libc.musl-aarch64.so.1 -Wl,-z,max-page-size=65536",
            "compiler_target": "aarch64-linux-musl",
        }
        self.install_libraries(elf())
        self.write_manifest()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def install_libraries(self, contents: bytes) -> None:
        for name in musl.LIBRARIES:
            path = self.runtime / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.unlink(missing_ok=True)
            path.write_bytes(contents)
        self.manifest["libc_so_sha256"] = hashlib.sha256(contents).hexdigest()

    def write_manifest(self) -> Path:
        receipt = self.runtime / musl.MANIFEST
        receipt.parent.mkdir(parents=True, exist_ok=True)
        receipt.write_text(json.dumps(self.manifest))
        return receipt

    def reject(self) -> None:
        self.write_manifest()
        with self.assertRaises((RuntimeError, OSError, ValueError)):
            musl.read_manifest(self.runtime)

    def test_accepts_verified_private_runtime_with_materialized_loader_alias(self) -> None:
        loader, alias = (self.runtime / name for name in musl.LIBRARIES)
        alias.unlink()
        os.link(loader, alias)
        self.assertEqual(musl.read_manifest(self.runtime), self.manifest)
        self.assertEqual(loader.stat().st_ino, alias.stat().st_ino)

    def test_rejects_loader_or_libc_tampering(self) -> None:
        for name in musl.LIBRARIES:
            with self.subTest(name=name):
                self.install_libraries(elf())
                path = self.runtime / name
                path.write_bytes(path.read_bytes() + b"changed")
                self.reject()

    def test_rejects_wrong_architecture_or_page_layout_even_with_matching_hash(self) -> None:
        for contents in (elf(machine=62), elf(offset=4096), b"not an ELF",
                         b"\x7fELF\x02\x01\x01"):
            with self.subTest(contents=contents[:16]):
                self.install_libraries(contents)
                self.reject()

    def test_rejects_missing_libraries_and_unmaterialized_symlinks(self) -> None:
        for name in musl.LIBRARIES:
            for symlink in (False, True):
                with self.subTest(name=name, symlink=symlink):
                    self.install_libraries(elf())
                    path = self.runtime / name
                    path.unlink()
                    if symlink:
                        target = self.root / "outside-libc.so"
                        target.write_bytes(elf())
                        path.symlink_to(target)
                    self.reject()

    def test_rejects_missing_or_symlinked_build_receipt(self) -> None:
        receipt = self.write_manifest()
        receipt.unlink()
        with self.assertRaises(FileNotFoundError):
            musl.read_manifest(self.runtime)
        external = self.root / "external-receipt.json"
        external.write_text(json.dumps(self.manifest))
        receipt.symlink_to(external)
        with self.assertRaisesRegex(RuntimeError, "receipt must be a regular file"):
            musl.read_manifest(self.runtime)

    def test_rejects_an_ordinary_source_built_libc_without_statistics_patch(self) -> None:
        self.manifest["patches"] = [
            record for record in self.manifest["patches"]
            if record["name"] != musl.PATCH.name]
        self.reject()

    def test_rejects_source_and_build_settings_outside_private_android_recipe(self) -> None:
        for key, value in (("version", "1.2.5"), ("arch", "x86_64"),
                           ("source_sha256", "0" * 64), ("source_url", "https://example.org/musl.tar.gz"),
                           ("retention", 0), ("cflags", "-O2"),
                           ("ldflags", "-Wl,-soname,libc.musl-aarch64.so.1"),
                           ("compiler_target", "x86_64-linux-musl")):
            with self.subTest(key=key):
                original = self.manifest[key]
                self.manifest[key] = value
                self.reject()
                self.manifest[key] = original

    def test_rejects_stale_reordered_or_incomplete_patch_receipts(self) -> None:
        original = deepcopy(self.manifest["patches"])
        stale = deepcopy(original)
        stale[-1]["sha256"] = "0" * 64
        for records in (original[:-1], original[1:], list(reversed(original)),
                        original + [original[-1]], stale):
            with self.subTest(records=records):
                self.manifest["patches"] = records
                self.reject()
        self.manifest["patches"] = original

    def test_source_patch_changes_invalidate_an_existing_receipt(self) -> None:
        # Use copies to exercise the production source-hash check without
        # changing any shared repository patch or mocking the reader.
        sources = self.root / "source-patches"
        alpine = sources / "alpine-1.2.6"
        shutil.copytree(musl.MUSL / "alpine-1.2.6", alpine)
        shutil.copy2(musl.MUSL / "malloc-retain.patch", sources)
        private = sources / musl.PATCH.name
        shutil.copy2(musl.PATCH, private)
        with patch.object(musl, "MUSL", sources), patch.object(musl, "PATCH", private):
            self.assertEqual(musl.read_manifest(self.runtime), self.manifest)
            for target in (private, sources / "malloc-retain.patch"):
                original = target.read_bytes()
                target.write_bytes(original + b"\nchanged input\n")
                with self.subTest(target=target.name):
                    self.reject()
                target.write_bytes(original)
            self.assertEqual(musl.read_manifest(self.runtime), self.manifest)

    def test_rejects_invalid_receipt_format(self) -> None:
        receipt = self.write_manifest()
        for text in ("{", "[]", "null", "1"):
            with self.subTest(text=text):
                receipt.write_text(text)
                with self.assertRaises((RuntimeError, ValueError)):
                    musl.read_manifest(self.runtime)


if __name__ == "__main__":
    unittest.main()
