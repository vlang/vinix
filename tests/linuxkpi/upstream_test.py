#!/usr/bin/env python3
"""Exercise archive integrity and extraction without accessing the network."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("upstream", ROOT / "kernel/linuxkpi/upstream.py")
upstream = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upstream)


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.pin = upstream.PIN
        upstream.PIN = {
            "version": "test", "url": "unused", "directories": ["driver/"],
            "files": [], "excluded_directories": [],
        }
        archive = self.base / "linux-test.tar.xz"
        with tarfile.open(archive, "w:xz") as output:
            for name, contents in [("driver/a.c", b"unmodified\n"), ("unwanted.c", b"excluded\n")]:
                info = tarfile.TarInfo("linux-test/" + name)
                info.size = len(contents)
                output.addfile(info, io.BytesIO(contents))
        upstream.PIN["sha256"] = upstream.digest(archive)

    def tearDown(self):
        upstream.PIN = self.pin
        self.temp.cleanup()

    def test_modifications_and_added_files_are_rejected(self):
        root = upstream.fetch(self.base)
        self.assertFalse((root / "unwanted.c").exists())
        upstream.verify(root)
        file = root / "driver/a.c"
        file.write_text("changed\n")
        with self.assertRaisesRegex(ValueError, "modified upstream source"):
            upstream.verify(root)
        file.write_text("unmodified\n")
        (root / "driver/extra.c").write_text("extra\n")
        with self.assertRaisesRegex(ValueError, "file set changed"):
            upstream.verify(root)

    def test_manifest_pin_rejects_rewritten_checksums(self):
        root = upstream.fetch(self.base)
        manifest = root / ".vinix-upstream.json"
        upstream.PIN["manifest_sha256"] = upstream.digest(manifest)
        file = root / "driver/a.c"
        file.write_text("changed\n")
        data = json.loads(manifest.read_text())
        data["files"]["driver/a.c"] = upstream.digest(file)
        manifest.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "pinned manifest"):
            upstream.verify(root)

    def test_path_escape_is_rejected(self):
        archive = self.base / "linux-test.tar.xz"
        with tarfile.open(archive, "w:xz") as output:
            info = tarfile.TarInfo("linux-test/driver/../../outside.c")
            info.size = 1
            output.addfile(info, io.BytesIO(b"x"))
        upstream.PIN["sha256"] = upstream.digest(archive)
        with self.assertRaisesRegex(ValueError, "unsafe archive member"):
            upstream.fetch(self.base)
        self.assertFalse((self.base / "outside.c").exists())


if __name__ == "__main__":
    unittest.main()
