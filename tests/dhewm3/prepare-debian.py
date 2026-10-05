#!/usr/bin/env python3
"""Fetch Debian's ARM64 cloud kernel and minimal userspace, checking SHA256."""
from __future__ import annotations

import argparse
import importlib.util
import json
import lzma
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build-aarch64-dhewm3/debian")
    args = parser.parse_args()
    work = args.output.resolve()
    cache = work / "downloads"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "Packages.xz"
    if not archive.exists():
        temp = archive.with_suffix(".part")
        subprocess.run(["curl", "-fL", "--retry", "3", "-o", str(temp),
                        "https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz"], check=True)
        temp.replace(archive)
    index = cache / "Packages"
    if not index.exists():
        index.write_bytes(lzma.decompress(archive.read_bytes()))
    spec = importlib.util.spec_from_file_location("debian_root", ROOT / "build-support/debian-root.py")
    debs = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = debs
    spec.loader.exec_module(debs)
    packages = debs.parse_index(index)
    by_name = {package.name: package for package in packages}
    meta = by_name["linux-image-cloud-arm64"]
    kernel_name = next(name for group in meta.dependencies for name in group if name.startswith("linux-image-"))
    kernel_package = by_name[kernel_name]
    kernel_root = work / "root"
    kernel_root.mkdir(exist_ok=True)
    kernel_deb = debs.download("https://deb.debian.org/debian", kernel_package, cache)
    debs.extract_deb(kernel_deb, kernel_root)
    subprocess.run([
        sys.executable, str(ROOT / "build-support/debian-root.py"), "--index", str(index),
        "--mirror", "https://deb.debian.org/debian", "--cache", str(cache),
        "--root", str(work / "userland"), "--manifest", str(work / "packages.tsv"),
        "base-files", "busybox-static",
    ], check=True)
    kernel = kernel_root / "boot" / kernel_package.name.replace("linux-image-", "vmlinuz-", 1)
    if not kernel.is_file():
        raise SystemExit(f"Debian package did not contain {kernel.name}")
    (work / "kernel.json").write_text(json.dumps({
        "package": kernel_package.name, "version": kernel_package.version,
        "sha256": kernel_package.sha256, "image": str(kernel),
    }, indent=2) + "\n")
    print(f"Debian kernel: {kernel}\nDebian root: {work / 'userland'}")


if __name__ == "__main__":
    main()
