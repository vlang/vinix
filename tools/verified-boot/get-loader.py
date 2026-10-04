#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build an unsigned UEFI-only Limine loader from Vinix's pinned source archive."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request


VERSION = "12.8.0"
SOURCE_SHA256 = "6fe2209457cb342ccf102d270ba953153138a191546c7801ed8ee9a6b2dcee4b"
SOURCE_URL = f"https://github.com/limine-bootloader/limine/releases/download/v{VERSION}/limine-{VERSION}.tar.gz"


def run(args, cwd):
    subprocess.run(args, cwd=cwd, check=True, stdin=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("x86_64", "aarch64"), required=True)
    parser.add_argument("--output", type=Path, required=True, help="new directory for the unsigned loader and host tool")
    parser.add_argument("--source-archive", type=Path, help="offline copy of the pinned source archive")
    args = parser.parse_args()
    output = args.output.absolute()
    try:
        if output.exists():
            raise ValueError("output already exists; choose a new directory")
        for name in ("clang", "ld.lld", "llvm-ar", "llvm-objcopy", "make", "patch"):
            if not shutil.which(name):
                raise ValueError(f"required command not found: {name}")
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".vinix-limine-", dir=output.parent) as temporary:
            work = Path(temporary)
            archive = args.source_archive
            if archive is None:
                archive = work / "limine.tar.gz"
                with urllib.request.urlopen(SOURCE_URL) as response, archive.open("wb") as destination:
                    shutil.copyfileobj(response, destination)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != SOURCE_SHA256:
                raise ValueError("Limine source archive SHA-256 mismatch")
            with tarfile.open(archive) as source:
                # The archive is authenticated against a repository-pinned
                # hash before extracting; reject escapes as defence in depth.
                for member in source.getmembers():
                    if member.name.startswith("/") or ".." in Path(member.name).parts or member.issym() or member.islnk():
                        raise ValueError("unsafe source archive entry")
                source.extractall(work)
            source_dir = work / f"limine-{VERSION}"
            if args.arch == "aarch64":
                patch = Path(__file__).resolve().parents[2] / "build-support/limine/12.8.0-vinix-base-revision-2.patch"
                with patch.open("rb") as stream:
                    subprocess.run(["patch", "-p1", "--batch"], cwd=source_dir, stdin=stream, check=True)
            target = "x86-64" if args.arch == "x86_64" else args.arch
            run(["./configure", f"--enable-uefi-{target}", "--disable-uefi-cd", "--disable-bios",
                 "--disable-bios-cd", "--disable-bios-pxe"], source_dir)
            run(["make", "-j4"], source_dir)
            filename = "BOOTX64.EFI" if args.arch == "x86_64" else "BOOTAA64.EFI"
            staged = work / "output"
            staged.mkdir()
            shutil.copyfile(source_dir / "bin" / filename, staged / filename)
            shutil.copy2(source_dir / "bin/limine", staged / "limine")
            staged.rename(output)
        print(f"Built pinned, UNSIGNED Limine {VERSION}: {output / filename}")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()
