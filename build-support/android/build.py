#!/usr/bin/env python3
"""Stage a pinned, private Android Translation Layer runtime for Vinix."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
LOCK = SUPPORT / "packages.lock.json"

_boot_spec = importlib.util.spec_from_file_location("vinix_android_runtime_native", SUPPORT / "_boot_native.py")
_boot = importlib.util.module_from_spec(_boot_spec)
_boot_spec.loader.exec_module(_boot)
MIRROR = "https://dl-cdn.alpinelinux.org/alpine/edge"
PREFIX = "/opt/vinix-android-aarch64"
ARCHITECTURE = "aarch64"
REPOSITORIES = ("main", "community", "testing")
ROOT_PACKAGES = ("android-translation-layer", "font-dejavu", "font-noto", "ca-certificates-bundle")
CALCULATOR = {
    "filename": "Arity-1.1.apk",
    "url": "https://storage.googleapis.com/google-code-archive-source/v2/code.google.com/arity-calculator/source-archive.zip",
    "archive_member": "arity-calculator/rel/Arity-1.1.apk",
    "archive_sha256": "1b39e4f968e7d21602ea166f73a1b36c35213b78e9e3e06b74053cfdc98dfbe2",
    "sha256": "1928e65ced8cbe78be2ff3cb4c321e9e75d138e8e30ea1368fbb772a86827d1d",
    "version": "1.1",
    "license": "Apache-2.0",
    "activity": "calculator/Calculator",
}
REQUIRED = ("lib/ld-musl-aarch64.so.1", "usr/bin/android-translation-layer",
            "usr/lib/art/libart.so", "usr/lib/java/dex/android_translation_layer/api-impl.jar",
            "usr/lib/java/dex/android_translation_layer/framework-res.apk",
            "usr/lib/java/dex/android_translation_layer/natives/libtranslation_layer_main.so",
            "usr/lib/libvinix-android-compat.so", "art-runtime-manifest.json",
            "bionic-runtime-manifest.json", "atl-runtime-manifest.json",
            "runtime-manifest.json", "architecture")


def art_tools():
    return _boot.build_call('art_tools', {}, globals(), values={})


def musl_tools():
    return _boot.build_call('musl_tools', {}, globals(), values={})


def runtime_tools():
    return _boot.build_call('runtime_tools', {}, globals(), values={})


def sha256(path: Path) -> str:
    return _boot.build_call('sha256', {}, globals(), values={'path': path})


def download(url: str, target: Path, expected: str | None = None) -> str:
    return _boot.build_call('download', {}, globals(), values={'url': url, 'target': target, 'expected': expected})


def make_lock(downloads: Path, mirror: str) -> dict:
    return _boot.build_call('make_lock', {}, globals(), values={'downloads': downloads, 'mirror': mirror})


def extract_apk(archive: Path, target: Path) -> None:
    # APK v2 is several concatenated gzip/tar streams: signatures, control,
    # payload. ignore_zeros keeps reading past each stream's end markers.
    return _boot.build_call('extract_apk', {}, globals(), values={'archive': archive, 'target': target})


def materialize_library_links(runtime: Path) -> None:
    # Vinix's loader does not reliably follow aliases when opening DSOs.
    return _boot.build_call('materialize_library_links', {}, globals(), values={'runtime': runtime})


def relocate_configuration(runtime: Path) -> None:
    # Fontconfig embeds /usr/share/fonts and includes relative conf.d files.
    # Rewrite its own paths to the matching fonts/config in this runtime.
    return _boot.build_call('relocate_configuration', {}, globals(), values={'runtime': runtime})


def calculator_apk(downloads: Path) -> Path:
    return _boot.build_call('calculator_apk', {}, globals(), values={'downloads': downloads})


def stage(args: argparse.Namespace, lock: dict, downloads: Path) -> Path:
    return _boot.build_call('stage', {}, globals(), values={'args': args, 'package_lock': lock, 'downloads': downloads})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path,
                        default=os.environ.get("VINIX_ANDROID_BUILD_DIR"))
    parser.add_argument("--with-calculator", action="store_true", help="include the verified Arity calculator APK")
    parser.add_argument("--art-runtime", type=Path, default=os.environ.get("VINIX_ANDROID_ART_RUNTIME"),
                        help="verified ARM64 ART overlay built for Vinix's 16 KiB pages")
    parser.add_argument("--bionic-runtime", type=Path, default=os.environ.get("VINIX_ANDROID_BIONIC_RUNTIME"),
                        help="verified ARM64 APK native-library loader built for 16 KiB pages")
    parser.add_argument("--atl-runtime", type=Path, default=os.environ.get("VINIX_ANDROID_ATL_RUNTIME"),
                        help="verified coherent ARM64 ATL native/framework/resource overlay")
    parser.add_argument("--update-lock", action="store_true", help="resolve current Alpine indexes and pin their closure")
    parser.add_argument("--mirror", default=os.environ.get("ALPINE_MIRROR", MIRROR),
                        help="Alpine edge mirror used when updating the package lock")
    args = parser.parse_args()
    return _boot.build_call('main', {}, globals(), values={'args': args})



if __name__ == "__main__":
    raise SystemExit(main())
