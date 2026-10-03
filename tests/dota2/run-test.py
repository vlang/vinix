#!/usr/bin/env python3
"""Host regressions for preparing the real-game capture fixture."""
import importlib.util
import errno
import io
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace


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


class ExportReadTests(unittest.TestCase):
    def test_success_preserves_real_bytes_and_range(self):
        calls = []
        def read(offset, count):
            calls.append((offset, count))
            return b"actual bytes"
        export = SimpleNamespace(read=read)
        observer = runner.ExportReads(export)
        self.assertEqual(export.read(4096, 12), b"actual bytes")
        self.assertEqual(calls, [(4096, 12)])
        self.assertEqual(observer.report(), {"requests": 1, "bytes": 12,
                                            "error_count": 0, "failures": []})

    def test_error_is_preserved_and_diagnostics_are_bounded(self):
        error = OSError(errno.EIO, "source changed")
        def read(offset, count):
            raise error
        export = SimpleNamespace(read=read)
        observer = runner.ExportReads(export)
        with redirect_stdout(io.StringIO()) as output:
            for index in range(40):
                with self.assertRaises(OSError) as raised:
                    export.read(index * 4096, 4096)
                self.assertIs(raised.exception, error)
        report = observer.report()
        self.assertEqual(report["requests"], 40)
        self.assertEqual(report["bytes"], 0)
        self.assertEqual(report["error_count"], 40)
        self.assertEqual(len(report["failures"]), 32)
        self.assertEqual(report["failures"][0]["offset"], 0)
        self.assertEqual(report["failures"][0]["errno"], errno.EIO)
        self.assertEqual(len(output.getvalue().splitlines()), 32)


class ArgumentTests(unittest.TestCase):
    def test_invalid_memory_does_not_create_a_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory) / "fixture"
            for memory in ("0", "-1"):
                result = subprocess.run([sys.executable, str(Path(__file__).with_name("run.py")),
                                         "--prepare-only", "--work", str(work),
                                         f"--memory-mib={memory}"], capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn("memory must be positive", result.stderr)
                self.assertFalse(work.exists())


if __name__ == "__main__":
    unittest.main()
