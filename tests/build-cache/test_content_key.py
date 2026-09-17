#!/usr/bin/env python3

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "build-support" / "content-key.py"


def content_key(*paths: Path, metadata: bool = False) -> str:
    command = ["python3", str(SCRIPT)]
    if metadata:
        command.append("--metadata")
    command.extend(str(path) for path in paths)
    result = subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    return result.stdout.strip()


class ContentKeyTests(unittest.TestCase):
    def test_ignores_mtime_but_tracks_content_and_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "tree"
            root.mkdir()
            file = root / "app"
            file.write_text("one\n", encoding="utf-8")
            file.chmod(0o644)

            first = content_key(root)
            os.utime(file, (1_000_000_000, 1_000_000_000))
            self.assertEqual(first, content_key(root))

            file.write_text("two\n", encoding="utf-8")
            second = content_key(root)
            self.assertNotEqual(first, second)

            file.chmod(0o755)
            self.assertNotEqual(second, content_key(root))

    def test_metadata_mode_tracks_in_place_tree_changes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "tree"
            nested = root / "usr" / "lib"
            nested.mkdir(parents=True)
            file = nested / "libexample.so"
            file.write_text("same-sized-a\n", encoding="utf-8")

            first = content_key(root, metadata=True)
            os.utime(file, (1_000_000_000, 1_000_000_000))
            self.assertNotEqual(first, content_key(root, metadata=True))

    def test_tracks_symlink_targets_and_missing_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "tree"
            root.mkdir()
            (root / "one").write_text("same\n", encoding="utf-8")
            (root / "two").write_text("same\n", encoding="utf-8")
            link = root / "current"
            link.symlink_to("one")
            missing = Path(tmp) / "missing"

            first = content_key(root, missing)
            link.unlink()
            link.symlink_to("two")
            self.assertNotEqual(first, content_key(root, missing))

    def test_root_location_is_not_part_of_the_content_key(self) -> None:
        with tempfile.TemporaryDirectory() as left_tmp, tempfile.TemporaryDirectory() as right_tmp:
            left = Path(left_tmp) / "tree"
            right = Path(right_tmp) / "tree"
            left.mkdir()
            right.mkdir()
            (left / "value").write_text("identical\n", encoding="utf-8")
            (right / "value").write_text("identical\n", encoding="utf-8")
            self.assertEqual(content_key(left), content_key(right))


if __name__ == "__main__":
    unittest.main()
