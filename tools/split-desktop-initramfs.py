#!/usr/bin/env python3
"""Split a desktop initramfs into a QEMU base and persistent /root seed."""

from __future__ import annotations

import argparse
import copy
import fcntl
import gzip
import json
import os
from pathlib import Path, PurePosixPath
import tarfile
import tempfile


FORMAT_VERSION = 1


def normalized_parts(name: str) -> tuple[str, ...]:
    while name.startswith("./"):
        name = name[2:]
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe archive member: {name}")
    return tuple(part for part in path.parts if part not in ("", "."))


def source_identity(source: Path) -> dict[str, object]:
    status = source.stat()
    return {
        "format": FORMAT_VERSION,
        "source": str(source.resolve()),
        "device": status.st_dev,
        "inode": status.st_ino,
        "size": status.st_size,
        "mtime_ns": status.st_mtime_ns,
    }


def cache_matches(
    manifest: Path, identity: dict[str, object], outputs: tuple[Path, ...]
) -> bool:
    if not all(path.is_file() and path.stat().st_size > 0 for path in outputs):
        return False
    try:
        return json.loads(manifest.read_text(encoding="utf-8")) == identity
    except (OSError, json.JSONDecodeError):
        return False


def temporary_path(destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(
        prefix=f".{destination.name}.", dir=destination.parent
    )
    os.close(descriptor)
    return Path(name)


def clone_member(member: tarfile.TarInfo, name: str) -> tarfile.TarInfo:
    cloned = copy.copy(member)
    cloned.name = name
    if cloned.islnk():
        target_parts = normalized_parts(cloned.linkname)
        if target_parts[:1] == ("root",):
            cloned.linkname = "/".join(target_parts[1:])
    return cloned


def split_archive(source_path: Path, base_path: Path, seed_path: Path) -> tuple[int, int]:
    base_temp = temporary_path(base_path)
    seed_temp = temporary_path(seed_path)
    root_members = 0
    root_bytes = 0
    root_directory_seen = False
    try:
        with tarfile.open(source_path, "r:") as source, tarfile.open(
            base_temp, "w:", format=tarfile.USTAR_FORMAT
        ) as base, seed_temp.open("wb") as compressed_output, gzip.GzipFile(
            filename="",
            mode="wb",
            compresslevel=1,
            fileobj=compressed_output,
            mtime=0,
        ) as gzip_output, tarfile.open(
            fileobj=gzip_output, mode="w|", format=tarfile.USTAR_FORMAT
        ) as seed:
            for member in source:
                parts = normalized_parts(member.name)
                payload = source.extractfile(member) if member.isfile() else None
                if parts[:1] != ("root",):
                    base.addfile(copy.copy(member), payload)
                    continue
                if len(parts) == 1:
                    root_directory_seen = True
                    base.addfile(copy.copy(member))
                    continue

                relative_name = "/".join(parts[1:])
                seed_member = clone_member(member, relative_name)
                seed.addfile(seed_member, payload)
                root_members += 1
                root_bytes += member.size

            if not root_directory_seen:
                root = tarfile.TarInfo("./root/")
                root.type = tarfile.DIRTYPE
                root.mode = 0o755
                root.uid = 0
                root.gid = 0
                base.addfile(root)

        os.replace(base_temp, base_path)
        os.replace(seed_temp, seed_path)
    except Exception:
        base_temp.unlink(missing_ok=True)
        seed_temp.unlink(missing_ok=True)
        raise
    return root_members, root_bytes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("base_output", type=Path)
    parser.add_argument("root_seed_output", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()

    if not args.source.is_file():
        parser.error(f"desktop initramfs is missing: {args.source}")
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    lock_path = args.manifest.with_name(f".{args.manifest.name}.lock")
    with lock_path.open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        identity = source_identity(args.source)
        outputs = (args.base_output, args.root_seed_output)
        if cache_matches(args.manifest, identity, outputs):
            print(f"QEMU storage images are current: {args.base_output}")
            return 0

        members, payload_bytes = split_archive(
            args.source, args.base_output, args.root_seed_output
        )
        manifest_temp = temporary_path(args.manifest)
        try:
            manifest_temp.write_text(
                json.dumps(identity, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            os.replace(manifest_temp, args.manifest)
        except Exception:
            manifest_temp.unlink(missing_ok=True)
            raise
        print(
            f"Split desktop initramfs: {args.base_output} plus "
            f"{args.root_seed_output} ({members} root entries, {payload_bytes} bytes)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
