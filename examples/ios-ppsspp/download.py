#!/usr/bin/env python3
"""Fetch the publisher's pinned iOS IPA and unpack it for compatibility testing."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import plistlib
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "1.20.4"
NAME = f"PPSSPP-iOS-v{VERSION}.ipa"
URL = f"https://github.com/hrydgard/ppsspp/releases/download/v{VERSION}/{NAME}"
SHA256 = "822c7042311ff47710c9148c8edb5aab649cf85ce6ba96b9e8190feb91f45a51"
SIZE = 31124277
BINARY_SHA256 = "7c9456c3cdee44dc48eefde5454bffa7e0965a32aa32858a181a06fbffeacf6c"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(output):
    output.mkdir(parents=True, exist_ok=True)
    ipa = output / NAME
    if not ipa.exists():
        request = urllib.request.Request(URL, headers={"User-Agent": "Vinix-iOS-probe"})
        with tempfile.NamedTemporaryFile(dir=output) as temp:
            with urllib.request.urlopen(request, timeout=60) as response:
                count = 0
                while chunk := response.read(1024 * 1024):
                    count += len(chunk)
                    if count > SIZE:
                        raise ValueError("upstream IPA exceeds pinned size")
                    temp.write(chunk)
            temp.flush()
            downloaded = Path(temp.name)
            if count != SIZE or sha256(downloaded) != SHA256:
                raise ValueError("downloaded IPA does not match the pinned release")
            ipa.write_bytes(downloaded.read_bytes())
    if ipa.stat().st_size != SIZE or sha256(ipa) != SHA256:
        raise ValueError(f"cached IPA checksum mismatch: {ipa}")
    unpacked = output / "unpacked"
    with zipfile.ZipFile(ipa) as archive:
        members = archive.infolist()
        names = [entry.filename for entry in members]
        if len(names) > 10000 or len(set(names)) != len(names):
            raise ValueError("invalid IPA member count or duplicate paths")
        if sum(entry.file_size for entry in members) > 1024 * 1024 * 1024:
            raise ValueError("IPA contents exceed limit")
        for entry in members:
            path = PurePosixPath(entry.filename)
            mode = (entry.external_attr >> 16) & 0o170000
            if (path.is_absolute() or ".." in path.parts or "\\" in entry.filename
                    or mode not in (0, 0o040000, 0o100000)
                    or entry.file_size > 512 * 1024 * 1024):
                raise ValueError(f"unsupported IPA member: {entry.filename}")
            destination = unpacked / path
            # Refuse pre-existing symlinks in an output directory, too.
            if destination.is_symlink() or any(p.is_symlink() for p in destination.parents):
                raise ValueError(f"symlink in extraction destination: {destination}")
        archive.extractall(unpacked)
    bundle = unpacked / "Payload/PPSSPP.app"
    info = plistlib.loads((bundle / "Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != "org.ppsspp.ppsspp"
            or info.get("CFBundleExecutable") != "PPSSPP"
            or info.get("CFBundleShortVersionString") != VERSION
            or sha256(bundle / "PPSSPP") != BINARY_SHA256):
        raise ValueError("unpacked app does not match the pinned iOS binary")
    print(f"Verified PPSSPP {VERSION} iOS IPA: {ipa}")
    print(f"Unmodified upstream executable: {bundle / 'PPSSPP'}")
    return bundle


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ios/ppsspp")
    args = parser.parse_args()
    fetch(args.output.resolve())
