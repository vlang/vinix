#!/usr/bin/env python3
"""Host-side tests for Minecraft version/runtime selection."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "build-support/minecraft/fetch-minecraft.py"
SPEC = importlib.util.spec_from_file_location("vinix_fetch_minecraft", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
fetch_minecraft = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fetch_minecraft)


class VersionSelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.java25 = json.dumps(
            {"id": "26.2", "type": "release", "javaVersion": {"majorVersion": 25}}
        ).encode()
        self.java21 = json.dumps(
            {
                "id": "1.21.5",
                "type": "release",
                "javaVersion": {"majorVersion": 21},
            }
        ).encode()
        manifest = {
            "latest": {"release": "26.2", "snapshot": "26.3-snapshot-1"},
            "versions": [
                {
                    "id": "26.2",
                    "type": "release",
                    "url": "https://example.invalid/26.2.json",
                    "sha1": hashlib.sha1(self.java25).hexdigest(),
                },
                {
                    "id": "1.21.5",
                    "type": "release",
                    "url": "https://example.invalid/1.21.5.json",
                    "sha1": hashlib.sha1(self.java21).hexdigest(),
                },
            ],
        }
        self.responses = {
            fetch_minecraft.VERSION_MANIFEST: json.dumps(manifest).encode(),
            "https://example.invalid/26.2.json": self.java25,
            "https://example.invalid/1.21.5.json": self.java21,
        }

    def fake_fetch(self, url: str) -> bytes:
        return self.responses[url]

    def test_release_selects_newest_client_supported_by_packaged_java(self) -> None:
        with patch.object(fetch_minecraft, "fetch", self.fake_fetch):
            version_id, version = fetch_minecraft.resolve_version("release", 21)

        self.assertEqual(version_id, "1.21.5")
        self.assertEqual(version["javaVersion"]["majorVersion"], 21)

    def test_explicit_incompatible_version_is_rejected(self) -> None:
        with patch.object(fetch_minecraft, "fetch", self.fake_fetch):
            with self.assertRaisesRegex(SystemExit, "needs Java 25"):
                fetch_minecraft.resolve_version("26.2", 21)


if __name__ == "__main__":
    unittest.main()
