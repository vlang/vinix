#!/usr/bin/env python3
import io
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest
import urllib.error
import urllib.request


REPOSITORY = Path(__file__).resolve().parents[2]
SERVER = REPOSITORY / "tools/qemu-package-store.py"

import importlib.util
_spec = importlib.util.spec_from_file_location("package_fixture_native", REPOSITORY / "tools/_package_store_native.py")
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)
_controller = _native._host.Controller(Path(__file__).with_name("package_fixture.v"), "VINIX_PACKAGE_FIXTURE_QUERY")


def archive(entries: dict[str, bytes]) -> bytes:
    return _native.call('fixture_archive', [entries], globals(), controller=_controller)


class PackageStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        return _native.call('fixture_setUp', [self], globals(), controller=_controller)

    def tearDown(self) -> None:
        return _native.call('fixture_tearDown', [self], globals(), controller=_controller)

    def upload(self, body: bytes) -> int:
        return _native.call('fixture_upload', [self, body], globals(), controller=_controller)

    def test_atomic_valid_overlay_replacement(self) -> None:
        return _native.call('fixture_test_atomic_valid_overlay_replacement', [self], globals(), controller=_controller)

    def test_rejects_traversal_and_keeps_previous_overlay(self) -> None:
        return _native.call('fixture_test_rejects_traversal_and_keeps_previous_overlay', [self], globals(), controller=_controller)

    def source_snapshot(self) -> tarfile.TarFile:
        return _native.call('fixture_source_snapshot', [self], globals(), controller=_controller)

    def source_snapshot_bytes(self) -> bytes:
        return _native.call('fixture_source_snapshot_bytes', [self], globals(), controller=_controller)

    def test_source_snapshot_reflects_live_tracked_and_untracked_files(self) -> None:
        return _native.call('fixture_test_source_snapshot_reflects_live_tracked_and_untracked_files', [self], globals(), controller=_controller)

    def fetch(self, path: str) -> bytes:
        return _native.call('fixture_fetch', [self, path], globals(), controller=_controller)

    def test_serves_each_live_app_build_from_its_own_directory(self) -> None:
        return _native.call('fixture_test_serves_each_live_app_build_from_its_own_directory', [self], globals(), controller=_controller)

    def test_live_app_without_a_build_is_not_found(self) -> None:
        return _native.call('fixture_test_live_app_without_a_build_is_not_found', [self], globals(), controller=_controller)

    def test_source_snapshot_skips_oversized_files(self) -> None:
        # A sparse file costs nothing on disk but would add 65 MiB to every
        # guest sync, as an interrupted desktop build's partial tar once did.
        return _native.call('fixture_test_source_snapshot_skips_oversized_files', [self], globals(), controller=_controller)


if __name__ == "__main__":
    unittest.main(verbosity=2)
