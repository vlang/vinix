#!/usr/bin/env python3
"""Fetch the developer's pinned Nazi Zombies: Portable PSP build and assets."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "2.0.0-indev+20260924124055"
URL = "https://github.com/nzp-team/nzportable/releases/download/nightly/nzportable-psp.zip"
SIZE = 64412845
SHA256 = "2983183a7d7d6471e8ebf2c5c95290ddd558a1c44d46b9ba6a68e9987f02e89f"
BINARY_SHA256 = "4b916c0b1d9f1607604623240b31c7291fcb9ec1585836d0a2eb3fcbd0e16d57"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(output: Path) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    package = output / "nzportable-psp.zip"
    if not package.exists():
        request = urllib.request.Request(URL, headers={"User-Agent": "Vinix-PSP-test"})
        with tempfile.TemporaryDirectory(dir=output) as directory:
            downloaded = Path(directory) / package.name
            count = 0
            with urllib.request.urlopen(request, timeout=60) as response, downloaded.open("wb") as stream:
                while chunk := response.read(1024 * 1024):
                    count += len(chunk)
                    if count > SIZE:
                        raise ValueError("upstream PSP package exceeds pinned size")
                    stream.write(chunk)
            if count != SIZE or sha256(downloaded) != SHA256:
                raise ValueError("upstream nightly changed; this test requires the pinned NZ:P build")
            downloaded.replace(package)
    if package.stat().st_size != SIZE or sha256(package) != SHA256:
        raise ValueError(f"cached PSP package checksum mismatch: {package}")
    unpacked = output / "unpacked"
    with zipfile.ZipFile(package) as archive:
        entries = archive.infolist()
        if len(entries) != 1310 or len({entry.filename for entry in entries}) != len(entries):
            raise ValueError("unexpected PSP package entry count or duplicate paths")
        if sum(entry.file_size for entry in entries) != 98449920:
            raise ValueError("unexpected PSP package expanded size")
        for entry in entries:
            path = PurePosixPath(entry.filename)
            mode = (entry.external_attr >> 16) & 0o170000
            if path.is_absolute() or ".." in path.parts or "\\" in entry.filename or mode not in (0, 0o040000, 0o100000):
                raise ValueError(f"unsupported PSP package member: {entry.filename}")
            destination = unpacked / path
            if destination.is_symlink() or any(parent.is_symlink() for parent in destination.parents):
                raise ValueError(f"symlink in extraction destination: {destination}")
        archive.extractall(unpacked)
    game = unpacked / "nzportable"
    binary = game / "EBOOT.PBP"
    if (binary.stat().st_size != 1539962 or sha256(binary) != BINARY_SHA256 or
            (game / "nzp/version.txt").read_text().strip() != VERSION):
        raise ValueError("unpacked PSP game does not match the pinned build")
    print(f"Verified NZ:P {VERSION}: {package} ({SHA256})")
    print(f"Unmodified PSP executable: {binary} ({BINARY_SHA256})")
    return game


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ios/nzportable")
    args = parser.parse_args()
    fetch(args.output.resolve())


if __name__ == "__main__":
    main()
