#!/usr/bin/env python3
"""Persist a QEMU guest package overlay and serve its host source checkout.

The server only listens on loopback. QEMU user networking exposes the host's
loopback services to its guest at 10.0.2.2; this is not a general network
service.
"""

from __future__ import annotations

import argparse
import http.server
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile

from host_clipboard import ClipboardError, read_clipboard

import importlib.util
_spec = importlib.util.spec_from_file_location("package_store_native", Path(__file__).with_name("_package_store_native.py"))
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)


# The guest downloads the whole shared checkout on every build. A stray build
# artifact (an abandoned multi-gigabyte initramfs tar, a disk image) would make
# that download outlast curl's timeout and stall the build indefinitely.
MAX_SHARED_FILE_BYTES = 64 * 1024 * 1024

# Native applications a host cross-build can replace in a running guest, by
# exec name, and the directory under the source root scripts/cross-compile-app.sh
# publishes each one's executable and version to.
LIVE_APPS = {
    "vinix-files": "build-aarch64-desktop-apps/files-live",
    "vinix-activity": "build-aarch64-desktop-apps/activity-live",
    "vinix-settings": "build-aarch64-desktop-apps/settings-live",
}


class OverlayError(Exception):
    pass


class SourceSnapshotError(Exception):
    pass


def validate_overlay(path: Path, maximum: int) -> None:
    return _native.call('validate_overlay', [path, maximum], globals())


class OverlayHandler(http.server.BaseHTTPRequestHandler):
    server_version = "VinixPackageStore/1"

    def do_GET(self) -> None:
        return _native.call('get', [self], globals())

    def send_app_build(self, app: str, name: str) -> None:
        return _native.call('send_app_build', [self, app, name], globals())

    def send_source_snapshot(self) -> None:
        return _native.call('send_source_snapshot', [self], globals())

    def do_PUT(self) -> None:
        self.save_overlay()

    def save_overlay(self) -> None:
        return _native.call('save_overlay', [self], globals())

    def log_message(self, format_string: str, *args: object) -> None:
        return _native.call('log_message', [format_string, args], globals())


def git_worktree_files(root: Path) -> list[Path]:
    return _native.call('git_worktree_files', [root], globals())


def extra_worktree_files(root: Path, relative: Path) -> list[Path]:
    return _native.call('extra_worktree_files', [root, relative], globals())


def stage_desktop_sources(root: Path, ui2: Path, destination: Path) -> None:
    """Materialize the host-only Python staging output for the guest.

    The staging tools normally create absolute symlinks for cheap host builds.
    Those links would point at macOS paths after extraction in Vinix, so build
    into a linked tree first and then copy it while following every symlink.
    """
    return _native.call('stage_desktop_sources', [root, ui2, destination], globals())


def normalize_staged_member(member: tarfile.TarInfo) -> tarfile.TarInfo:
    """Keep generated staging metadata stable across otherwise identical requests."""
    return _native.call('normalize_staged_member', [member], globals())


def build_source_snapshot(
    root: Path, extras: tuple[Path, ...], ui2_source: Path | None = None
) -> tempfile.SpooledTemporaryFile:
    return _native.call('build_source_snapshot', [root, extras, ui2_source], globals())


class OverlayServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        destination: Path,
        maximum: int,
        source_root: Path | None,
        source_extras: tuple[Path, ...],
        ui2_source: Path | None,
        clipboard: bool = False,
    ):
        super().__init__(address, OverlayHandler)
        self.destination = destination
        self.maximum_overlay = maximum
        self.source_root = source_root
        self.source_extras = source_extras
        self.ui2_source = ui2_source
        self.clipboard = clipboard


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", type=Path, required=True)
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--ready-file", type=Path)
    parser.add_argument("--max-bytes", type=int, default=1024 * 1024 * 1024)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--source-extra", type=Path, action="append", default=[])
    parser.add_argument("--ui2-source", type=Path)
    parser.add_argument("--clipboard", action="store_true")
    args = parser.parse_args()

    _native.call("main", [args, parser], globals())


if __name__ == "__main__":
    main()
