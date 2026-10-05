"""Verify the cached QEMU module ISO contains the exact source archive."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "tools/build-qemu-module-iso.py"


@unittest.skipUnless(shutil.which("xorriso"), "xorriso is not installed")
class QemuModuleIsoTest(unittest.TestCase):
    def test_image_and_cache(self) -> None:
        with tempfile.TemporaryDirectory(prefix="vinix-module-iso.") as temporary:
            root = Path(temporary)
            source = root / "initramfs.tar"
            output = root / "module.iso"
            source.write_bytes(b"first archive\n")
            command = [sys.executable, str(BUILDER), str(source), str(output)]

            subprocess.run(command, check=True, capture_output=True)
            first_time = output.stat().st_mtime_ns
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(output.stat().st_mtime_ns, first_time)

            extracted = root / "extracted.tar"
            subprocess.run(
                [
                    "xorriso", "-osirrox", "on", "-indev", str(output),
                    "-extract", "/boot/initramfs.tar", str(extracted),
                ],
                check=True,
                capture_output=True,
            )
            self.assertEqual(extracted.read_bytes(), source.read_bytes())

            source.write_bytes(b"second archive\n")
            subprocess.run(command, check=True, capture_output=True)
            self.assertNotEqual(output.stat().st_mtime_ns, first_time)


if __name__ == "__main__":
    unittest.main()
