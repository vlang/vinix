#!/usr/bin/env python3
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time
import unittest
import urllib.error
import urllib.request


REPOSITORY = Path(__file__).resolve().parents[2]
SERVER = REPOSITORY / "tools/qemu-package-store.py"


def archive(entries: dict[str, bytes]) -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name, contents in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(contents)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(contents))
    return output.getvalue()


class PackageStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.store = root / "packages.tar"
        self.ready = root / "ready"
        self.server = subprocess.Popen(
            [
                "python3",
                str(SERVER),
                "--store",
                str(self.store),
                "--port",
                "0",
                "--ready-file",
                str(self.ready),
                "--max-bytes",
                str(1024 * 1024),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        for _ in range(100):
            if self.ready.exists() and self.ready.stat().st_size:
                break
            if self.server.poll() is not None:
                self.fail(self.server.stdout.read())
            time.sleep(0.01)
        self.assertTrue(self.ready.exists() and self.ready.stat().st_size)
        self.port = int(self.ready.read_text())

    def tearDown(self) -> None:
        self.server.terminate()
        self.server.wait(timeout=5)
        self.server.stdout.close()
        self.temporary.cleanup()

    def upload(self, body: bytes) -> int:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/packages", data=body, method="PUT"
        )
        with urllib.request.urlopen(request) as response:
            return response.status

    def test_atomic_valid_overlay_replacement(self) -> None:
        self.assertEqual(self.upload(archive({"usr/bin/gtk3-demo": b"one"})), 204)
        self.assertEqual(self.upload(archive({"etc/apk/world": b"gtk\n"})), 204)
        with tarfile.open(self.store, "r:") as saved:
            self.assertEqual(saved.extractfile("etc/apk/world").read(), b"gtk\n")
            self.assertNotIn("usr/bin/gtk3-demo", saved.getnames())

    def test_rejects_traversal_and_keeps_previous_overlay(self) -> None:
        good = archive({"usr/lib/libgtk.so": b"gtk"})
        self.assertEqual(self.upload(good), 204)
        before = self.store.read_bytes()
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.upload(archive({"../escape": b"bad"}))
        self.assertEqual(failure.exception.code, 400)
        self.assertEqual(self.store.read_bytes(), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
