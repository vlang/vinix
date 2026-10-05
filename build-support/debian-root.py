#!/usr/bin/env python3
"""Stage a Debian package closure into a directory without dpkg.

Resolves the runtime dependency closure of the requested packages from
uncompressed Packages indices, downloads the .deb files from a mirror into a
cache, verifies them, and unpacks their data archives into a root directory.
Versions are not compared: the indices of one release are consistent with
themselves. Maintainer scripts are not run, so anything a postinst generates
(ld.so.cache, the CA bundle, alternatives) must come from elsewhere.
"""

from __future__ import annotations

import argparse
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import hashlib
import io
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile


@dataclass(frozen=True)
class Package:
    name: str
    version: str
    architecture: str
    filename: str
    sha256: str
    size: int
    dependencies: tuple[tuple[str, ...], ...]
    provides: tuple[str, ...]


def dependency_key(specification: str) -> str:
    """Strip the version, architecture qualifiers and multiarch suffix."""
    name = re.split(r"[\s(\[<>=]", specification.strip(), maxsplit=1)[0]
    return name.split(":", 1)[0]


def parse_relations(field: str) -> tuple[tuple[str, ...], ...]:
    relations = []
    for group in field.split(","):
        alternatives = tuple(
            dependency_key(alternative) for alternative in group.split("|")
            if dependency_key(alternative)
        )
        if alternatives:
            relations.append(alternatives)
    return tuple(relations)


def parse_index(path: Path) -> list[Package]:
    packages: list[Package] = []
    for record in path.read_text(encoding="utf-8", errors="replace").split("\n\n"):
        fields: dict[str, str] = {}
        key = ""
        for line in record.splitlines():
            if line[:1].isspace():
                if key:
                    fields[key] += " " + line.strip()
                continue
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            fields[key] = value.strip()
        if "Package" not in fields or "Filename" not in fields:
            continue
        packages.append(
            Package(
                name=fields["Package"],
                version=fields.get("Version", ""),
                architecture=fields.get("Architecture", ""),
                filename=fields["Filename"],
                sha256=fields.get("SHA256", ""),
                size=int(fields.get("Size", "0")),
                dependencies=parse_relations(fields.get("Pre-Depends", ""))
                + parse_relations(fields.get("Depends", "")),
                provides=tuple(
                    dependency_key(item) for item in fields.get("Provides", "").split(",")
                    if dependency_key(item)
                ),
            )
        )
    return packages


def resolve(packages: list[Package], roots: list[str], ignored: set[str]) -> list[Package]:
    by_name: dict[str, Package] = {}
    providers: dict[str, list[Package]] = {}
    for package in packages:
        by_name.setdefault(package.name, package)
        for provision in package.provides:
            providers.setdefault(provision, []).append(package)

    selected: dict[str, Package] = {}
    queue: deque[tuple[str, ...]] = deque((root,) for root in roots)
    while queue:
        alternatives = queue.popleft()
        if any(name in selected or name in ignored for name in alternatives):
            continue
        package = None
        for name in alternatives:
            if name in by_name:
                package = by_name[name]
                break
        if package is None:
            for name in alternatives:
                if name in providers:
                    package = providers[name][0]
                    break
        if package is None:
            raise SystemExit(f"unresolved Debian dependency: {' | '.join(alternatives)}")
        if package.name in selected:
            continue
        selected[package.name] = package
        queue.extend(package.dependencies)
    return sorted(selected.values(), key=lambda item: item.name)


def download(mirror: str, package: Package, cache: Path) -> Path:
    target = cache / Path(package.filename).name
    if target.is_file() and (not package.sha256 or file_sha256(target) == package.sha256):
        return target
    url = f"{mirror.rstrip('/')}/{package.filename}"
    print(f"  downloading {package.architecture}/{target.name}", file=sys.stderr)
    partial = target.with_name(target.name + ".partial")
    subprocess.run(
        ["curl", "--fail", "--location", "--retry", "3", "--retry-all-errors",
         "--connect-timeout", "15", "--speed-limit", "1024", "--speed-time", "30",
         "--continue-at", "-", "--silent", "--show-error", "--output", str(partial), url],
        check=True,
    )
    if package.sha256 and file_sha256(partial) != package.sha256:
        partial.unlink()
        raise SystemExit(f"checksum mismatch downloading {url}")
    partial.replace(target)
    return target


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ar_members(data: bytes):
    """Yield (name, payload) for every member of a .deb (a BSD/GNU ar archive)."""
    if not data.startswith(b"!<arch>\n"):
        raise SystemExit("not an ar archive")
    offset = 8
    while offset + 60 <= len(data):
        header = data[offset:offset + 60]
        name = header[0:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        payload = data[offset + 60:offset + 60 + size]
        yield name, payload
        offset += 60 + size + (size & 1)


def extract_deb(deb: Path, root: Path) -> None:
    for name, payload in ar_members(deb.read_bytes()):
        if not name.startswith("data.tar"):
            continue
        with tarfile.open(fileobj=io.BytesIO(payload), mode="r:*") as archive:
            for member in archive.getmembers():
                relative = os.path.normpath(member.name)
                if relative.startswith("..") or os.path.isabs(relative):
                    raise SystemExit(f"{deb.name}: refusing to unpack {member.name}")
                destination = root / relative
                if member.isdir():
                    destination.mkdir(parents=True, exist_ok=True)
                    continue
                destination.parent.mkdir(parents=True, exist_ok=True)
                if destination.is_symlink() or destination.exists():
                    destination.unlink()
                if member.issym():
                    destination.symlink_to(member.linkname)
                elif member.islnk():
                    source = root / os.path.normpath(member.linkname)
                    destination.write_bytes(source.read_bytes())
                    destination.chmod(source.stat().st_mode & 0o7777)
                elif member.isfile():
                    stream = archive.extractfile(member)
                    assert stream is not None
                    with destination.open("wb") as output:
                        while True:
                            chunk = stream.read(1 << 20)
                            if not chunk:
                                break
                            output.write(chunk)
                    destination.chmod(member.mode & 0o7777)
        return
    raise SystemExit(f"{deb.name}: no data archive")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", action="append", type=Path, required=True,
                        help="an uncompressed Packages index (repeatable)")
    parser.add_argument("--mirror", required=True,
                        help="the archive root the Filename fields are relative to")
    parser.add_argument("--cache", type=Path, required=True, help="download directory")
    parser.add_argument("--root", type=Path, required=True, help="unpack destination")
    parser.add_argument("--ignore", action="append", default=[],
                        help="a dependency to treat as satisfied (repeatable)")
    parser.add_argument("--manifest", type=Path,
                        help="write the selected package list here")
    parser.add_argument("--resolve-only", action="store_true",
                        help="print the closure and do nothing else")
    parser.add_argument("packages", nargs="+")
    arguments = parser.parse_args()

    packages: list[Package] = []
    for index in arguments.index:
        packages.extend(parse_index(index))
    selected = resolve(packages, arguments.packages, set(arguments.ignore))

    lines = [f"{package.name}\t{package.version}\t{package.architecture}\t{package.filename}"
             for package in selected]
    if arguments.resolve_only:
        print("\n".join(lines))
        return 0
    if arguments.manifest is not None:
        arguments.manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")

    arguments.cache.mkdir(parents=True, exist_ok=True)
    arguments.root.mkdir(parents=True, exist_ok=True)
    total = sum(package.size for package in selected)
    print(f"  {len(selected)} packages, {total / (1 << 20):.0f} MiB of archives", file=sys.stderr)
    # Each package has an independent cache path. Fetching them together keeps
    # a slow mirror connection from stalling the entire multiarch build.
    with ThreadPoolExecutor(max_workers=6) as downloads:
        archives = list(downloads.map(
            lambda package: download(arguments.mirror, package, arguments.cache),
            selected,
        ))
    for package, deb in zip(selected, archives):
        extract_deb(deb, arguments.root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
