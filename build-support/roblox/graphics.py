#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Overlay checksum-pinned x86 graphics libraries into a private Roblox root.

Existing AppImage files take precedence. Library aliases become hardlinks so
Vinix's O_NOFOLLOW loader can open them without duplicating Mesa's drivers.
The calling runtime builder supplies glibc separately.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
LOCK = Path(__file__).with_name("graphics.lock.json")


def load_debian_tools():
    spec = importlib.util.spec_from_file_location(
        "vinix_roblox_debian_root", ROOT / "build-support/debian-root.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    original_members = module.ar_members

    # Ubuntu uses zstd data archives, which Python before 3.14 cannot open.
    # Reuse the existing validated extractor after decoding that one member.
    def members(data):
        for name, payload in original_members(data):
            if name.startswith("data.tar") and name.endswith(".zst"):
                payload = subprocess.check_output(["zstd", "-dc"], input=payload)
                name = name[:-4]
            yield name, payload

    module.ar_members = members
    return module


def link_target(path: Path, root: Path) -> Path:
    for _ in range(32):
        if not path.is_symlink():
            return path
        target = os.readlink(path)
        path = root / target.lstrip("/") if target.startswith("/") else path.parent / target
        path = Path(os.path.normpath(path))
        if not path.is_relative_to(root):
            raise RuntimeError(f"library link escapes graphics root: {path}")
    raise RuntimeError(f"graphics library link cycle: {path}")


def overlay(source: Path, output: Path) -> tuple[int, int]:
    copied = preserved = 0
    inodes: dict[tuple[int, int, int], Path] = {}
    # Resolve aliases from the source, even if their target occurs later in
    # sorted order. Link equivalent files by inode or content, as the shared
    # Debian extractor materializes tar hardlinks as copies.
    content: dict[tuple[int, int, str], Path] = {}
    import hashlib

    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        destination = output / relative
        if path.is_dir() and not path.is_symlink():
            if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
                raise RuntimeError(f"graphics directory conflicts with existing file: {destination}")
            destination.mkdir(parents=True, exist_ok=True)
            continue
        if destination.exists() or destination.is_symlink():
            preserved += 1
            continue
        resolved = link_target(path, source)
        # Noble's libxml2 documentation includes NEWS.gz -> changelog.gz
        # without shipping the latter file. It is unrelated to runtime code.
        if not resolved.exists() and relative.parts[:3] == ("usr", "share", "doc"):
            continue
        if resolved.is_dir():
            destination.parent.mkdir(parents=True, exist_ok=True)
            target = output / resolved.relative_to(source)
            destination.symlink_to(os.path.relpath(target, destination.parent))
            copied += 1
            continue
        if not resolved.is_file():
            raise RuntimeError(f"unsupported graphics package entry: {path}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        attributes = resolved.stat()
        mode = attributes.st_mode & 0o7777
        inode = (attributes.st_dev, attributes.st_ino, mode)
        original = inodes.get(inode)
        if original is None:
            digest = hashlib.sha256(resolved.read_bytes()).hexdigest()
            key = (attributes.st_size, mode, digest)
            original = content.get(key)
        if original is None:
            shutil.copy2(resolved, destination)
            inodes[inode] = destination
            content[key] = destination
        else:
            os.link(original, destination)
            inodes[inode] = original
        copied += 1
        # Absolute Ubuntu ICD paths must resolve through this private root's
        # LD_LIBRARY_PATH, rather than the desktop's native ARM libraries.
        if relative.parts[:4] in (("usr", "share", "vulkan", "icd.d"),
                                 ("usr", "share", "glvnd", "egl_vendor.d")):
            document = json.loads(destination.read_text())
            library = document.get("ICD", {}).get("library_path", "")
            if library.startswith("/"):
                document["ICD"]["library_path"] = Path(library).name
                destination.write_text(json.dumps(document, indent=2) + "\n")
    return copied, preserved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--output", type=Path, required=True,
                        help="private runtime prefix to overlay, preserving existing files")
    parser.add_argument("--cache", type=Path,
                        default=ROOT / "build-aarch64-roblox/downloads")
    parser.add_argument("--mirror", help="override the archive mirror without changing hashes")
    arguments = parser.parse_args()
    if shutil.which("zstd") is None:
        raise SystemExit("Roblox graphics staging requires zstd on the build host")
    manifest = json.loads(LOCK.read_text())
    if manifest["format"] != 1 or manifest["architecture"] != "amd64":
        raise SystemExit("unsupported Roblox graphics lock")
    tools = load_debian_tools()
    selected = []
    for record in manifest["packages"]:
        if not re.fullmatch(r"[0-9a-f]{64}", record["sha256"]):
            raise SystemExit(f"missing graphics package checksum: {record['package']}")
        selected.append(tools.Package(record["package"], record["version"],
                                      record["architecture"], record["filename"],
                                      record["sha256"], record["size"], (), ()))
    if len({Path(package.filename).name for package in selected}) != len(selected):
        raise SystemExit("duplicate graphics download filenames")
    arguments.cache.mkdir(parents=True, exist_ok=True)
    arguments.output.mkdir(parents=True, exist_ok=True)
    mirror = arguments.mirror or manifest["mirror"]
    print(f"Staging {len(selected)} pinned Roblox graphics packages", flush=True)
    with ThreadPoolExecutor(max_workers=6) as downloads:
        archives = list(downloads.map(
            lambda package: tools.download(mirror, package, arguments.cache), selected))
    with tempfile.TemporaryDirectory(prefix="roblox-graphics-", dir=arguments.cache.parent) as directory:
        source = Path(directory)
        for archive in archives:
            tools.extract_deb(archive, source)
        copied, preserved = overlay(source, arguments.output.resolve())
    provenance = arguments.output / "usr/share/vinix/roblox-graphics-manifest.json"
    provenance.parent.mkdir(parents=True, exist_ok=True)
    provenance.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Graphics ready: {arguments.output} ({copied} files, {preserved} existing files preserved)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
