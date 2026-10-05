#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/split-desktop-initramfs.py"
SPEC = importlib.util.spec_from_file_location("split_desktop_initramfs", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SplitDesktopInitramfsTests(unittest.TestCase):
    def test_moves_root_payload_and_keeps_mountpoint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source_root = work / "source"
            (source_root / "root/.wine").mkdir(parents=True)
            (source_root / "usr/bin").mkdir(parents=True)
            (source_root / "root/.wine/state").write_text("office", encoding="utf-8")
            (source_root / "usr/bin/app").write_text("base", encoding="utf-8")
            source = work / "desktop.tar"
            base = work / "qemu.tar"
            seed = work / "root.tar.gz"
            with tarfile.open(source, "w", format=tarfile.USTAR_FORMAT) as archive:
                archive.add(source_root, arcname=".")

            members, payload_bytes = MODULE.split_archive(source, base, seed)

            self.assertGreater(members, 0)
            self.assertEqual(payload_bytes, len("office"))
            with tarfile.open(base, "r:") as archive:
                names = {name.removeprefix("./").rstrip("/") for name in archive.getnames()}
                self.assertIn("root", names)
                self.assertIn("usr/bin/app", names)
                self.assertNotIn("root/.wine/state", names)
            with tarfile.open(seed, "r:gz") as archive:
                names = {name.removeprefix("./").rstrip("/") for name in archive.getnames()}
                self.assertIn(".wine/state", names)
                self.assertNotIn("root/.wine/state", names)
                state = archive.extractfile(".wine/state")
                assert state is not None
                self.assertEqual(state.read(), b"office")

    def test_rejects_parent_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "unsafe.tar"
            with tarfile.open(source, "w", format=tarfile.USTAR_FORMAT) as archive:
                member = tarfile.TarInfo("../escape")
                member.size = 0
                archive.addfile(member)
            with self.assertRaisesRegex(ValueError, "unsafe archive member"):
                MODULE.split_archive(
                    source, work / "base.tar", work / "seed.tar.gz"
                )

    def test_cache_identity_requires_every_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "desktop.tar"
            source.write_bytes(b"archive")
            base = work / "base.tar"
            seed = work / "seed.tar.gz"
            manifest = work / "manifest.json"
            identity = MODULE.source_identity(source)
            manifest.write_text(json.dumps(identity), encoding="utf-8")
            base.write_bytes(b"base")

            self.assertFalse(
                MODULE.cache_matches(manifest, identity, (base, seed))
            )
            seed.write_bytes(b"seed")
            self.assertTrue(
                MODULE.cache_matches(manifest, identity, (base, seed))
            )


if __name__ == "__main__":
    unittest.main()
