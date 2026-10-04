#!/usr/bin/env python3
"""Cache an ISO9660 disk containing a QEMU initramfs of any size."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


FORMAT_VERSION = 1


def source_identity(source: Path) -> dict[str, object]:
    status = source.stat()
    return {
        "format": FORMAT_VERSION,
        "source": str(source),
        "device": status.st_dev,
        "inode": status.st_ino,
        "size": status.st_size,
        "mtime_ns": status.st_mtime_ns,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    if not source.is_file():
        parser.error(f"not a regular file: {source}")
    output = args.output.absolute()
    if source == output:
        parser.error("source and ISO output must differ")
    xorriso = shutil.which("xorriso")
    if xorriso is None:
        parser.error("xorriso is required to build the QEMU module ISO")
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = output.with_name(f"{output.name}.json")
    lock_path = output.with_name(f".{output.name}.lock")

    with lock_path.open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        identity = source_identity(source)
        if output.is_file() and output.stat().st_size > source.stat().st_size:
            try:
                if json.loads(manifest.read_text(encoding="utf-8")) == identity:
                    print(output)
                    return
            except (OSError, ValueError):
                pass

        print(f"==> Building ISO9660 QEMU module disk from {source.name}...", file=os.sys.stderr)
        with tempfile.TemporaryDirectory(prefix=f".{output.name}.", dir=output.parent) as temporary:
            iso = Path(temporary) / "module.iso"
            result = subprocess.run(
                [
                    xorriso, "-as", "mkisofs", "-iso-level", "3", "-R", "-r", "-J",
                    "-graft-points", "-o", str(iso), f"boot/initramfs.tar={source}",
                ],
                text=True,
                capture_output=True,
            )
            if result.returncode != 0:
                raise RuntimeError(f"xorriso failed:\n{result.stderr}")
            if source_identity(source) != identity:
                raise RuntimeError("QEMU initramfs changed while building the ISO")
            if iso.stat().st_size <= source.stat().st_size:
                raise RuntimeError("QEMU module ISO is smaller than its initramfs")
            new_manifest = Path(temporary) / "manifest.json"
            new_manifest.write_text(json.dumps(identity, sort_keys=True) + "\n", encoding="utf-8")
            os.replace(iso, output)
            os.replace(new_manifest, manifest)
        print(output)


if __name__ == "__main__":
    main()
