#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stage a pinned native Weston host for Cordial's embedded web windows."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
LOCK = Path(__file__).with_name("wayland.lock.json")
PREFIX = "/opt/vinix-roblox-wayland"
REQUIRED = ("lib/ld-musl-aarch64.so.1", "usr/bin/weston",
            "usr/lib/libweston-14/x11-backend.so", "usr/lib/weston/kiosk-shell.so",
            "usr/share/X11/xkb/rules/evdev")


def stage(output: Path, cache: Path, android) -> dict:
    manifest = json.loads(LOCK.read_text())
    if manifest["format"] != 1 or manifest["architecture"] != "aarch64":
        raise RuntimeError("unsupported Roblox Wayland lock")
    packages = manifest["packages"]
    names = [record["filename"] for record in packages]
    if len(set(names)) != len(names):
        raise RuntimeError("duplicate Roblox Wayland download filenames")
    for record in packages:
        if Path(record["filename"]).name != record["filename"] or not re.fullmatch(
                r"[0-9a-f]{64}", record["sha256"]):
            raise RuntimeError("invalid Roblox Wayland package record")
    cache.mkdir(parents=True, exist_ok=True)

    def fetch(record):
        archive = cache / record["filename"]
        android.download(record["url"], archive, record["sha256"])
        return archive

    print(f"Staging {len(packages)} pinned native Weston packages", flush=True)
    with ThreadPoolExecutor(max_workers=6) as downloads:
        archives = list(downloads.map(fetch, packages))
    output.mkdir(parents=True, exist_ok=True)
    for archive in archives:
        android.extract_apk(archive, output)
    android.materialize_library_links(output)
    for name in REQUIRED:
        if not (output / name).is_file():
            raise RuntimeError(f"native Weston package closure is missing {name}")
    provenance = output / "usr/share/vinix/roblox-wayland-manifest.json"
    provenance.parent.mkdir(parents=True, exist_ok=True)
    provenance.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Native Weston ready: {output}")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("vinix_android_builder",
                                                 ROOT / "build-support/android/build.py")
    assert spec is not None and spec.loader is not None
    android = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = android
    spec.loader.exec_module(android)
    stage(args.output.resolve(), args.cache.resolve(), android)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
