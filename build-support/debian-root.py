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
import importlib.util
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


_bindings_spec = importlib.util.spec_from_file_location("debian_bindings", Path(__file__).parent / "android/_boot_native.py")
_bindings = importlib.util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(Path(__file__).with_name("debian_query.v"), "VINIX_DEBIAN_QUERY",
                                        process=_bindings._build_process)


def _query(operation, **values):
    return _bindings.query_call(_controller, {"operation": operation}, globals(), values=values)


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
    return _query("dependency_key", specification=specification)


def parse_relations(field: str) -> tuple[tuple[str, ...], ...]:
    return _query("parse_relations", field=field)


def parse_index(path: Path) -> list[Package]:
    return _query("parse_index", path=path)


def resolve(packages: list[Package], roots: list[str], ignored: set[str]) -> list[Package]:
    return _query("resolve", packages=packages, roots=roots, ignored=ignored)


def download(mirror: str, package: Package, cache: Path) -> Path:
    return _query("download", mirror=mirror, package=package, cache=cache)


def file_sha256(path: Path) -> str:
    return _query("file_sha256", path=path)


def ar_members(data: bytes):
    """Yield (name, payload) for every member of a .deb (a BSD/GNU ar archive)."""
    offset, initial = 8, True
    while True:
        member = _query("ar_next", data=data, offset=offset, initial=initial)
        if member is None:
            return
        name, payload, offset = member
        initial = False
        yield name, payload


def extract_deb(deb: Path, root: Path) -> None:
    return _query("extract_deb", deb=deb, root=root)


_native_dependency_key, _native_parse_relations, _native_parse_index = dependency_key, parse_relations, parse_index
_native_resolve, _native_file_sha256 = resolve, file_sha256
_native_ar_members, _native_extract_deb = ar_members, extract_deb


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

    return _query("main", arguments=arguments)


if __name__ == "__main__":
    raise SystemExit(main())
