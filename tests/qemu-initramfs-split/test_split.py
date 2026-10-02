"""Small archive coverage for the uncompressed QEMU boot module splitter."""

import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPLITTER = ROOT / "tools/split-qemu-initramfs.py"


class SplitQemuInitramfsTest(unittest.TestCase):
    def test_shrinking_image_removes_only_obsolete_modules(self) -> None:
        with tempfile.TemporaryDirectory(prefix="vinix-module-shrink.") as temporary:
            directory = Path(temporary)
            source = directory / "source.tar"
            cache = directory / "parts"
            command = [sys.executable, str(SPLITTER), str(source), str(cache), "--max-bytes", "20480"]

            def write_source(count: int) -> None:
                with tarfile.open(source, "w", format=tarfile.USTAR_FORMAT) as archive:
                    for index in range(count):
                        member = tarfile.TarInfo(f"file-{index}")
                        member.size = 6000
                        archive.addfile(member, io.BytesIO(b"x" * member.size))

            write_source(3)
            first = subprocess.run(command, check=True, capture_output=True, text=True)
            old_parts = [Path(line) for line in first.stdout.splitlines()]
            self.assertEqual(len(old_parts), 3)
            unrelated = cache / "other.tar"
            unrelated.write_bytes(b"keep")
            outside = directory / "outside"
            outside.mkdir()
            sentinel = outside / "keep.tar"
            sentinel.write_bytes(b"keep outside")
            symlink = cache / "part-999.tar"
            symlink.symlink_to(outside, target_is_directory=True)
            matching_directory = cache / "part-888.tar"
            matching_directory.mkdir()

            write_source(1)
            rebuilt = subprocess.run(command, check=True, capture_output=True, text=True)
            parts = [Path(line) for line in rebuilt.stdout.splitlines()]
            self.assertEqual(parts, old_parts[:1])
            self.assertTrue(parts[0].is_file())
            self.assertTrue(all(not part.exists() for part in old_parts[1:]))
            self.assertFalse(symlink.is_symlink())
            self.assertEqual(sentinel.read_bytes(), b"keep outside")
            self.assertEqual(unrelated.read_bytes(), b"keep")
            self.assertTrue(matching_directory.is_dir())
            self.assertEqual(json.loads((cache / "manifest.json").read_text())["parts"], [parts[0].name])
            reused = subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(reused.stdout, rebuilt.stdout)
            self.assertEqual(reused.stderr, "")

    def test_failed_rebuild_preserves_previous_cache(self) -> None:
        with tempfile.TemporaryDirectory(prefix="vinix-module-failed.") as temporary:
            directory = Path(temporary)
            source = directory / "source.tar"
            cache = directory / "parts"
            with tarfile.open(source, "w", format=tarfile.USTAR_FORMAT) as archive:
                member = tarfile.TarInfo("file")
                member.size = 6000
                archive.addfile(member, io.BytesIO(b"x" * member.size))
            command = [sys.executable, str(SPLITTER), str(source), str(cache), "--max-bytes", "20480"]
            first = subprocess.run(command, check=True, capture_output=True, text=True)
            part = Path(first.stdout.strip())
            old_part = part.read_bytes()
            old_manifest = (cache / "manifest.json").read_bytes()

            source.write_bytes(b"invalid tar")
            failed = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(part.read_bytes(), old_part)
            self.assertEqual((cache / "manifest.json").read_bytes(), old_manifest)
            self.assertEqual(list(cache.glob(".parts.*")), [])

    def test_parts_preserve_members_and_reuse_cache(self) -> None:
        with tempfile.TemporaryDirectory(prefix="vinix-module-parts.") as temporary:
            directory = Path(temporary)
            source = directory / "source.tar"
            with tarfile.open(source, "w", format=tarfile.USTAR_FORMAT) as archive:
                folder = tarfile.TarInfo("root/")
                folder.type = tarfile.DIRTYPE
                folder.mode = 0o755
                archive.addfile(folder)
                for index in range(5):
                    payload = directory / f"file-{index}"
                    payload.write_bytes(bytes([65 + index]) * 6000)
                    archive.add(payload, arcname=f"root/file-{index}")

            command = [
                sys.executable,
                str(SPLITTER),
                str(source),
                str(directory / "parts"),
                "--max-bytes",
                "20480",
            ]
            first = subprocess.run(command, check=True, capture_output=True, text=True)
            second = subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(first.stdout, second.stdout)
            self.assertEqual(second.stderr, "")

            parts = [Path(line) for line in first.stdout.splitlines()]
            self.assertEqual(len(parts), 5)
            entries: list[tuple[str, bytes]] = []
            for part in parts:
                self.assertLessEqual(part.stat().st_size, 20480)
                with tarfile.open(part) as archive:
                    for member in archive:
                        if member.isfile():
                            payload = archive.extractfile(member)
                            assert payload is not None
                            entries.append((member.name, payload.read()))
            self.assertEqual(
                entries,
                [(f"root/file-{index}", bytes([65 + index]) * 6000) for index in range(5)],
            )


if __name__ == "__main__":
    unittest.main()
