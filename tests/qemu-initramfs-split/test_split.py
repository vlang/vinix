"""Small archive coverage for the uncompressed QEMU boot module splitter."""

from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPLITTER = ROOT / "tools/split-qemu-initramfs.py"


class SplitQemuInitramfsTest(unittest.TestCase):
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
