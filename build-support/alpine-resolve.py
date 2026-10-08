#!/usr/bin/env python3
"""Resolve an Alpine runtime dependency closure from unpacked APKINDEX files."""

from __future__ import annotations

import argparse
import importlib.util
import re
from collections import deque
from dataclasses import dataclass
from pathlib import Path


_bindings_spec = importlib.util.spec_from_file_location("alpine_bindings", Path(__file__).parent / "android/_boot_native.py")
_bindings = importlib.util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(Path(__file__).with_name("alpine_query.v"), "VINIX_ALPINE_QUERY",
                                        process=_bindings._build_process)


def _query(operation, **values):
    return _bindings.query_call(_controller, {"operation": operation}, globals(), values=values)


@dataclass(frozen=True)
class Package:
    name: str
    version: str
    dependencies: tuple[str, ...]
    provides: tuple[str, ...]
    repository: str


def parse_index(path: Path, repository: str) -> list[Package]:
    return [Package(name=row["name"], version=row["version"], dependencies=tuple(row["dependencies"]),
                    provides=tuple(row["provides"]), repository=repository)
            for row in _query("parse_index", path=path)]


def dependency_key(specification: str) -> str:
    return _query("dependency_key", specification=specification)


_native_dependency_key = dependency_key


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

    return _query("main", args=args)


if __name__ == "__main__":
    raise SystemExit(main())
