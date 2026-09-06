#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import copy
import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import verify_reads as verify


class ReadVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "image"
        self.data = bytes((i * 17 + 3) & 255 for i in range(65536))
        self.source.write_bytes(self.data)
        self.manifest = verify.record(str(self.source), [(0, 8192), (12345, 8001), (61440, 4096)], "synthetic host fixture")

    def test_readonly_and_awkward_chunks(self):
        real_open = os.open
        observed = []
        def tracked(path, flags, *args, **kwargs):
            observed.append(flags)
            return real_open(path, flags, *args, **kwargs)
        with mock.patch.object(verify.os, "open", side_effect=tracked):
            result = verify.check(str(self.source), self.manifest, 2)
        self.assertEqual(observed, [os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)])
        self.assertEqual(result["result"], "REFERENCE COMPARISON PASS")
        self.assertFalse(result["physical_hardware_independently_verified"])
        self.assertEqual(self.source.read_bytes(), self.data)

    def test_known_hash(self):
        self.assertEqual(self.manifest["ranges"][1]["sha256"], hashlib.sha256(self.data[12345:20346]).hexdigest())

    def test_mismatch(self):
        self.source.write_bytes(b"x" + self.data[1:])
        with self.assertRaisesRegex(ValueError, "MISMATCH"):
            verify.check(str(self.source), self.manifest, 1)

    def test_short_read(self):
        self.source.write_bytes(self.data[:16384])
        with self.assertRaisesRegex(OSError, "short read"):
            verify.check(str(self.source), self.manifest, 1)

    def test_bad_manifests(self):
        for value in (-1, True, 1 << 63, "0"):
            bad = copy.deepcopy(self.manifest)
            bad["ranges"][0]["offset"] = value
            with self.assertRaises(ValueError): verify.validate_manifest(bad)
        bad = copy.deepcopy(self.manifest)
        bad["ranges"][1] = copy.deepcopy(bad["ranges"][0])
        with self.assertRaises(ValueError): verify.validate_manifest(bad)
        bad = copy.deepcopy(self.manifest); bad["ranges"][0]["sha256"] = "bad"
        with self.assertRaises(ValueError): verify.validate_manifest(bad)
        with self.assertRaises(ValueError): verify.check(str(self.source), self.manifest, 0)

    def test_cannot_overwrite_source_or_symlink(self):
        with self.assertRaises(FileExistsError): verify.save_new_manifest(str(self.source), self.manifest)
        alias = Path(self.temp.name) / "alias"
        alias.symlink_to(self.source)
        with self.assertRaises(FileExistsError): verify.save_new_manifest(str(alias), self.manifest)
        self.assertEqual(self.source.read_bytes(), self.data)

    def test_manifest_roundtrip(self):
        path = Path(self.temp.name) / "manifest.json"
        verify.save_new_manifest(str(path), self.manifest)
        self.assertEqual(verify.load_manifest(str(path)), self.manifest)
        verify.check(str(self.source), verify.load_manifest(str(path)), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
