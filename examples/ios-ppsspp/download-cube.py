#!/usr/bin/env python3
"""Fetch an unchanged, pinned PSP cube demo from PPSSPP's upstream tests."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import hashlib
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
COMMIT = "f93c29855718a587360976e793f5b41a88ef7e68"
URL = f"https://raw.githubusercontent.com/hrydgard/pspautotests/{COMMIT}/demos/cube.pbp"
SHA256 = "4018ec0da8a88a1600380661bcd4461c09c4c69bc45139ec626a754f0eec3fc0"
SIZE = 50600


def verified(data: bytes) -> bool:
    return len(data) == SIZE and hashlib.sha256(data).hexdigest() == SHA256 and data[:4] == b"\0PBP"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/ios/ppsspp/cube.pbp")
    args = parser.parse_args()
    output = args.output
    if not output.is_file() or not verified(output.read_bytes()):
        request = urllib.request.Request(URL, headers={"User-Agent": "Vinix-iOS-probe"})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(SIZE + 1)
        if not verified(data):
            raise ValueError("upstream PSP cube does not match its pinned size/hash/header")
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=output.parent) as directory:
            downloaded = Path(directory) / "cube.pbp"
            downloaded.write_bytes(data)
            downloaded.replace(output)
    print(f"Verified upstream PSP cube: {output} ({SHA256})")


if __name__ == "__main__":
    main()
