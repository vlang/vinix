#!/usr/bin/env python3
"""Host regressions for preparing the real-game capture fixture."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("dota2_run", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class InstallTests(unittest.TestCase):
    def test_replace_readonly_pin_without_changing_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "pin"
            source.write_bytes(b"new desktop")
            source.chmod(0o555)
            target = root / "fixture/usr/bin/desktop"
            target.parent.mkdir(parents=True)
            target.write_bytes(b"old desktop")
            target.chmod(0o555)
            runner.install(source, target)
            runner.install(source, target)
            self.assertEqual(target.read_bytes(), b"new desktop")
            self.assertEqual(target.stat().st_mode & 0o777, 0o555)
            self.assertEqual(source.read_bytes(), b"new desktop")
            self.assertEqual(source.stat().st_mode & 0o777, 0o555)

    def test_replace_symlink_without_writing_its_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.write_bytes(b"replacement")
            original = root / "original"
            original.write_bytes(b"keep")
            target = root / "target"
            target.symlink_to(original)
            runner.install(source, target)
            self.assertFalse(target.is_symlink())
            self.assertEqual(target.read_bytes(), b"replacement")
            self.assertEqual(original.read_bytes(), b"keep")

    def test_identical_source_and_target_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.write_bytes(b"keep")
            source.chmod(0o444)
            runner.install(source, source)
            self.assertEqual(source.read_bytes(), b"keep")


if __name__ == "__main__":
    unittest.main()
