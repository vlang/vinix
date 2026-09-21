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
        self.source = root / "source"
        (self.source / "desktop").mkdir(parents=True)
        (self.source / "desktop/main.v").write_text("module main\n", encoding="utf-8")
        (self.source / "desktop/local.v").write_text("module main\n", encoding="utf-8")
        (self.source / ".gitignore").write_text("ignored.txt\nthird_party/\n", encoding="utf-8")
        (self.source / "ignored.txt").write_text("not shared\n", encoding="utf-8")
        (self.source / "third_party/ui2").mkdir(parents=True)
        (self.source / "third_party/ui2/v.mod").write_text(
            'Module { name: "ui2" }\n', encoding="utf-8"
        )
        subprocess.run(["git", "init", "-q", str(self.source)], check=True)
        subprocess.run(
            ["git", "-C", str(self.source), "add", ".gitignore", "desktop/main.v"],
            check=True,
        )
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
                "--source-root",
                str(self.source),
                "--source-extra",
                "third_party/ui2",
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

    def source_snapshot(self) -> tarfile.TarFile:
        with urllib.request.urlopen(
            f"http://127.0.0.1:{self.port}/vinix-source.tar"
        ) as response:
            return tarfile.open(fileobj=io.BytesIO(response.read()), mode="r:")

    def test_source_snapshot_reflects_live_tracked_and_untracked_files(self) -> None:
        with self.source_snapshot() as snapshot:
            self.assertEqual(snapshot.extractfile("desktop/main.v").read(), b"module main\n")
            self.assertIn("desktop/local.v", snapshot.getnames())
            self.assertIn("third_party/ui2/v.mod", snapshot.getnames())
            self.assertNotIn("ignored.txt", snapshot.getnames())
            self.assertFalse(any(".git/" in name for name in snapshot.getnames()))

        (self.source / "desktop/main.v").write_text(
            "module main\n// changed after server start\n", encoding="utf-8"
        )
        with self.source_snapshot() as snapshot:
            self.assertIn(
                b"changed after server start",
                snapshot.extractfile("desktop/main.v").read(),
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
