#!/usr/bin/env python3
"""Resolve an Alpine runtime dependency closure from unpacked APKINDEX files."""

from __future__ import annotations

import argparse
import re
from collections import deque
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Package:
    name: str
    version: str
    dependencies: tuple[str, ...]
    provides: tuple[str, ...]
    repository: str


def parse_index(path: Path, repository: str) -> list[Package]:
    packages: list[Package] = []
    for record in path.read_text(encoding="utf-8").split("\n\n"):
        fields: dict[str, str] = {}
        for line in record.splitlines():
            if len(line) >= 2 and line[1] == ":":
                fields[line[0]] = line[2:]
        if "P" not in fields or "V" not in fields:
            continue
        packages.append(
            Package(
                name=fields["P"],
                version=fields["V"],
                dependencies=tuple(fields.get("D", "").split()),
                provides=tuple(fields.get("p", "").split()),
                repository=repository,
            )
        )
    return packages


def dependency_key(specification: str) -> str:
    return re.split(r"[<>=~]", specification, maxsplit=1)[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--index",
        action="append",
        nargs=2,
        metavar=("REPOSITORY", "APKINDEX"),
        required=True,
    )
    parser.add_argument("packages", nargs="+")
    args = parser.parse_args()

    packages: list[Package] = []
    for repository, index in args.index:
        packages.extend(parse_index(Path(index), repository))

    by_name: dict[str, Package] = {}
    providers: dict[str, Package] = {}
    for package in packages:
        # Index order is repository preference order (main before community).
        by_name.setdefault(package.name, package)
        providers.setdefault(package.name, package)
        for provision in package.provides:
            providers.setdefault(dependency_key(provision), package)

    ignored = {
        "/bin/sh",
        "cmd:sh",
        "cmd:busybox",
    }
    queue = deque(args.packages)
    selected: dict[str, Package] = {}
    while queue:
        requested = dependency_key(queue.popleft())
        if not requested or requested.startswith("!") or requested in ignored:
            continue
        package = by_name.get(requested) or providers.get(requested)
        if package is None:
            raise SystemExit(f"unresolved Alpine dependency: {requested}")
        if package.name in selected:
            continue
        selected[package.name] = package
        queue.extend(package.dependencies)

    for package in sorted(selected.values(), key=lambda item: item.name):
        print(f"{package.repository}\t{package.name}-{package.version}.apk")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
