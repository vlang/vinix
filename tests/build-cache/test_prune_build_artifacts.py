"""Scratch archive retention must never delete VM data or active build inputs."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/prune-build-artifacts.py"
SPEC = importlib.util.spec_from_file_location("prune_build", SCRIPT)
PRUNE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRUNE)


class PruneBuildArtifactsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.clock = time.time()

    def file(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"reproducible archive\n")
        return path

    def prune(self, keep=None, dry_run=False):
        with patch.object(PRUNE.time, "time", return_value=self.clock + 8 * 86400), \
                patch.object(PRUNE, "active_paths", return_value=set()):
            return PRUNE.prune(self.root, 7, keep or set(), dry_run)

    def test_old_experiments_removed_but_recent_and_reusable_inputs_kept(self):
        old = [self.file(f"build/minecraft-desktop-initramfs-{variant}.tar")
               for variant in ("host-fill", "runtime-fix", "2x", "clean", "debug")]
        old.append(self.file("build/desktop-perf/initramfs-desktop-123.iso"))
        metadata = self.file("build/desktop-perf/initramfs-desktop-123.iso.json")
        old.append(self.file("build/.initramfs-desktop-qemu.tar.gz.abc123"))
        old.append(self.file("build-support/init-aarch64/.initramfs-desktop.tar.def456"))
        preserved = [self.file(name) for name in (
            "build/minecraft-desktop-root.ext2", "build/minecraft-desktop-boot.img",
            "build/macos.qcow2", "build/downloads/initramfs.tar",
            "build/staging/initramfs.tar", "build/vinix-installer/initramfs.tar",
            "build/sources.tar.gz", "build/desktop-root-seed.tar.gz",
            "build/initramfs-desktop-qemu.tar", "build/initramfs-desktop-qemu.iso",
            "build/initramfs-desktop-full.iso", "build-support/init-aarch64/initramfs.tar",
            "build-support/init-aarch64/initramfs-desktop.tar",
        )]
        recent = self.file("build/new-initramfs.tar")
        os.utime(recent, (self.clock + 7 * 86400,) * 2)
        preserved.append(recent)
        count, freed = self.prune()
        self.assertEqual(count, len(old))
        self.assertGreater(freed, 0)
        self.assertTrue(all(not path.exists() for path in old + [metadata]))
        self.assertTrue(all(path.exists() for path in preserved))
        self.assertEqual(self.prune(), (0, 0))

    def test_keep_override_marker_and_dry_run(self):
        explicit = self.file("build/custom-initramfs.tar")
        marked = self.file("build/minecraft-initramfs.tar")
        self.file("build/minecraft-initramfs.tar.keep")
        removable = self.file("build/other-initramfs.tar")
        count, _ = self.prune({explicit}, dry_run=True)
        self.assertEqual(count, 1)
        self.assertTrue(removable.exists())
        count, _ = self.prune({explicit})
        self.assertEqual(count, 1)
        self.assertTrue(explicit.exists())
        self.assertTrue(marked.exists())
        self.assertFalse(removable.exists())

    def test_symlinks_and_directory_links_are_not_followed(self):
        outside = self.file("external/initramfs.tar")
        (self.root / "build").mkdir()
        link = self.root / "build/linked-initramfs.tar"
        link.symlink_to(outside)
        (self.root / "build/qemu-desktop-capture").symlink_to(outside.parent)
        self.assertEqual(self.prune(), (0, 0))
        self.assertTrue(link.is_symlink())
        self.assertTrue(outside.exists())

    def test_concurrent_replacement_is_preserved(self):
        path = self.file("build/old-initramfs.tar")

        def replacing_inspector(paths, root):
            replacement = path.with_suffix(".new")
            replacement.write_bytes(b"new build")
            replacement.replace(path)
            return set()

        with patch.object(PRUNE, "active_paths", side_effect=replacing_inspector):
            self.assertEqual(PRUNE.prune(self.root, 0, set(), False), (0, 0))
        self.assertEqual(path.read_bytes(), b"new build")

    def test_open_archive_is_preserved(self):
        path = self.file("build/open-initramfs.tar")
        with path.open("rb"):
            self.assertEqual(PRUNE.prune(self.root, 0, set(), False), (0, 0))
        self.assertTrue(path.exists())

    def test_environment_override_and_automatic_opt_out(self):
        kept = self.file("build/override-initramfs.tar")
        kept_iso = self.file("build/override-initramfs.iso")
        removable = self.file("build/other-initramfs.tar")
        command = [sys.executable, str(SCRIPT), "--root", str(self.root),
                   "--older-than-days", "0", "--automatic"]
        environment = dict(os.environ, VINIX_PRUNE_BUILD="0")
        subprocess.run(command, env=environment, check=True, capture_output=True)
        self.assertTrue(removable.exists())
        environment.update(VINIX_PRUNE_BUILD="1", VINIX_DESKTOP_INITRAMFS=str(kept),
                           VINIX_AMD64_DESKTOP_ISO=str(kept_iso))
        subprocess.run(command, env=environment, check=True, capture_output=True)
        self.assertTrue(kept.exists())
        self.assertTrue(kept_iso.exists())
        self.assertFalse(removable.exists())

    def test_another_sessions_future_image_input_is_preserved(self):
        path = self.file("build/future-initramfs.tar")
        # The selected image exists only in this process's environment, and
        # is not in its arguments or open descriptors yet.
        environment = dict(os.environ, VINIX_DESKTOP_INITRAMFS=str(path))
        child = subprocess.Popen([sys.executable, "-c",
                                  "import sys; print('ready', flush=True); sys.stdin.read()"],
                                 env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        try:
            self.assertEqual(child.stdout.readline(), b"ready\n")
            self.assertEqual(PRUNE.prune(self.root, 0, set(), False), (0, 0))
            self.assertTrue(path.exists())
        finally:
            child.stdin.close()
            child.wait(timeout=5)
            child.stdout.close()

    def test_failed_inspection_prevents_deletion(self):
        path = self.file("build/old-initramfs.tar")
        with patch.object(PRUNE, "active_paths", side_effect=RuntimeError("inspection failed")):
            with self.assertRaises(RuntimeError):
                PRUNE.prune(self.root, 0, set(), False)
        self.assertTrue(path.exists())


if __name__ == "__main__":
    unittest.main()
