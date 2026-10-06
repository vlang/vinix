#!/usr/bin/env python3
"""Fetch the pinned God of War: Chains of Olympus PSP demo, UCUS98713."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import hashlib
from pathlib import Path
import struct
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
# Demo archive linked from PPSSPP's official demos/homebrew documentation.
# These hashes pin the downloaded archive and PBP; they are measured locally.
URL = "https://data.playdreamcreate.com/god-of-war-chains-of-olympus_US.zip"
SIZE = 169451774
SHA256 = "6c1e4cffecf389e5dbcc995564e3d311afcfd9beaa493e6feace642aa57785ea"
BINARY_SIZE = 169451184
BINARY_SHA256 = "7d147100be1127d87351042a22526cc64c3229e9b0a9fb984bcd5e0aa20a1523"
MEMBER = "PSP/GAME/UCUS98713/EBOOT.PBP"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(output: Path) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    package = output / "demo.zip"
    if not package.exists():
        request = urllib.request.Request(URL, headers={"User-Agent": "Vinix-PSP-test"})
        with tempfile.TemporaryDirectory(dir=output) as directory:
            downloaded = Path(directory) / package.name
            count = 0
            with urllib.request.urlopen(request, timeout=60) as response, downloaded.open("wb") as stream:
                while chunk := response.read(1024 * 1024):
                    count += len(chunk)
                    if count > SIZE:
                        raise ValueError("PSP demo exceeds pinned size")
                    stream.write(chunk)
            if count != SIZE or sha256(downloaded) != SHA256:
                raise ValueError("downloaded PSP demo does not match the pinned archive")
            downloaded.replace(package)
    if package.stat().st_size != SIZE or sha256(package) != SHA256:
        raise ValueError(f"cached PSP demo checksum mismatch: {package}")
    unpacked = output / "unpacked"
    with zipfile.ZipFile(package) as archive:
        entries = archive.infolist()
        expected = {"PSP/", "PSP/GAME/", "PSP/GAME/UCUS98713/", MEMBER}
        if (len(entries) != len(expected) or {entry.filename for entry in entries} != expected or
                sum(entry.file_size for entry in entries) != BINARY_SIZE):
            raise ValueError("unexpected PSP demo archive contents")
        for entry in entries:
            destination = unpacked / entry.filename
            mode = (entry.external_attr >> 16) & 0o170000
            if mode not in (0, 0o040000, 0o100000):
                raise ValueError(f"unsupported PSP demo member: {entry.filename}")
            if destination.is_symlink() or any(parent.is_symlink() for parent in destination.parents):
                raise ValueError(f"symlink in extraction destination: {destination}")
        archive.extractall(unpacked)
    binary = unpacked / MEMBER
    if binary.stat().st_size != BINARY_SIZE or sha256(binary) != BINARY_SHA256:
        raise ValueError("unpacked PSP executable does not match the pinned demo")
    with binary.open("rb") as stream:
        header = stream.read(40)
        if header[:8] != b"\0PBP\1\0\1\0":
            raise ValueError("unexpected PSP demo PBP header")
        stream.seek(struct.unpack_from("<I", header, 36)[0])
        if stream.read(8) != b"NPUMDIMG":
            raise ValueError("PSP demo is missing its original NPUMDIMG data")
    print(f"Verified God of War PSP demo UCUS98713: {package} ({SHA256})")
    print(f"Unmodified PSP executable: {binary} ({BINARY_SHA256})")
    return binary.parent


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ios/god-of-war")
    args = parser.parse_args()
    fetch(args.output.resolve())
