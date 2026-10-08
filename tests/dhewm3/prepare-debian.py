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


_bindings_spec = importlib.util.spec_from_file_location("debian_prepare_bindings", ROOT / "build-support/android/_boot_native.py")
_bindings = importlib.util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(ROOT / "build-support/dhewm3/prepare_query.v", "VINIX_DHEWM_DEBIAN_QUERY",
                                        process=_bindings._build_process)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build-aarch64-dhewm3/debian")
    args = parser.parse_args()
    return _bindings.query_call(_controller, {"operation": "main"}, globals(), values={"args": args})


if __name__ == "__main__":
    main()
