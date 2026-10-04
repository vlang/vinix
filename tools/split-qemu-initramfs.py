#!/usr/bin/env python3
"""Split a tar initramfs into Limine modules below FAT32's per-file limit."""

from __future__ import annotations

import argparse
import copy
import fcntl
import json
import os
from pathlib import Path
import re
import tarfile
import tempfile


DEFAULT_MAX_BYTES = 3 * 1024 * 1024 * 1024
FORMAT_VERSION = 1


def identity(source: Path, max_bytes: int) -> dict[str, object]:
    stat = source.stat()
    return {
        "format": FORMAT_VERSION,
        "source": str(source.resolve()),
        "device": stat.st_dev,
        "inode": stat.st_ino,
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "max_bytes": max_bytes,
    }


def current_parts(manifest: Path, expected: dict[str, object], directory: Path) -> list[Path]:
    try:
        saved = json.loads(manifest.read_text(encoding="utf-8"))
        names = saved["parts"]
        if saved["identity"] != expected or not names:
            return []
        paths = [directory / name for name in names]
        if all(path.is_file() and 0 < path.stat().st_size <= expected["max_bytes"] for path in paths):
            return paths
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        pass
    return []


def split(source: Path, staging: Path, max_bytes: int) -> list[Path]:
    parts: list[Path] = []
    output: tarfile.TarFile | None = None
    estimated = 0
    try:
        with tarfile.open(source, "r:") as archive:
            for member in archive:
                payload_bytes = (member.size + 511) // 512 * 512 if member.isfile() else 0
                needed = 512 + payload_bytes
                if needed + tarfile.RECORDSIZE > max_bytes:
                    raise ValueError(f"tar member exceeds module limit: {member.name}")
                if output is None or estimated + needed + tarfile.RECORDSIZE > max_bytes:
                    if output is not None:
                        output.close()
                    part = staging / f"part-{len(parts) + 1:03d}.tar"
                    parts.append(part)
                    output = tarfile.open(part, "w:", format=tarfile.USTAR_FORMAT)
                    estimated = 0
                payload = archive.extractfile(member) if member.isfile() else None
                output.addfile(copy.copy(member), payload)
                estimated += needed
        if output is None:
            raise ValueError("initramfs is empty")
    finally:
        if output is not None:
            output.close()
    for part in parts:
        if part.stat().st_size > max_bytes:
            raise ValueError(f"module exceeds size limit: {part}")
    return parts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    args = parser.parse_args()
    if args.max_bytes < tarfile.RECORDSIZE * 2 or args.max_bytes > 4294967295:
        parser.error("--max-bytes must be between 20480 and FAT32's 4 GiB limit")
    source = args.source.resolve(strict=True)
    directory = args.directory.absolute()
    if not source.is_file():
        parser.error(f"not a regular file: {source}")
    directory.mkdir(parents=True, exist_ok=True)
    manifest = directory / "manifest.json"
    with (directory / ".lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        expected = identity(source, args.max_bytes)
        parts = current_parts(manifest, expected, directory)
        if not parts:
            print(f"==> Splitting {source.name} into uncompressed FAT32 modules...", file=os.sys.stderr)
            with tempfile.TemporaryDirectory(prefix=".parts.", dir=directory) as temporary:
                staged = split(source, Path(temporary), args.max_bytes)
                new_manifest = Path(temporary) / "manifest.json"
                new_manifest.write_text(
                    json.dumps({"identity": expected, "parts": [part.name for part in staged]}) + "\n",
                    encoding="utf-8",
                )
                for part in staged:
                    os.replace(part, directory / part.name)
                os.replace(new_manifest, manifest)
                parts = [directory / part.name for part in staged]
                # Only discard old modules once the replacement cache is published.
                # Unlinking a symlink removes the link itself, never its target.
                current_names = {part.name for part in parts}
                for obsolete in directory.iterdir():
                    if (
                        obsolete.name not in current_names
                        and re.fullmatch(r"part-[0-9]{3,}\.tar", obsolete.name)
                        and (obsolete.is_file() or obsolete.is_symlink())
                    ):
                        obsolete.unlink()
        for part in parts:
            print(part)


if __name__ == "__main__":
    main()
