#!/usr/bin/env python3
"""Cross-build OpenGothic for ARM64/musl and stage an isolated Vulkan runtime."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import functools
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
from runpy import run_path

ROOT = Path(__file__).resolve().parents[2]
COMMIT = "26b7159230834780fc6a8fc9aa0d060863cb443f"
HEADERS = "3c65a01745e4a1134d32b9c2c456472212dba16d"
REWISE = "c3d3b68903a90ec53ff7b0a4ae704adc6302814b"
MIRROR = "https://dl-cdn.alpinelinux.org/alpine/v3.21"
DEMO_URL = "https://www.worldofgothic.de/download.php?id=122"
DEMO_SHA256 = "380d2ae52e4e2eac3beea55e729eb7eb2ea04ffa13521cd22e9fe22fcbe96353"
# Applied to the pinned Tempest renderer in this order; see README.md.
PATCHES = ("active-descriptors.patch", "sampled-attachments.patch")


_binding = run_path(str(ROOT / "tools/_package_store_native.py"))
_controller = _binding["_host"].Controller(Path(__file__).with_name("build_query.v"), "VINIX_OPENGOTHIC_QUERY")


def _call(operation, arguments):
    return _binding["call"](operation, arguments, globals(), controller=_controller)


def _fetch(downloads, line):
    return _call("fetch", [downloads, line])


def run(*args, **kwargs):
    return _call("run", [args, kwargs])


def apply_patch(source: Path, name: str):
    return _call("apply_patch", [source, name])


def download(url: str, path: Path):
    return _call("download", [url, path])


def checkout(url: str, path: Path, commit: str, submodules=False):
    return _call("checkout", [url, path, commit, submodules])


def copy_file(source: Path, target: Path):
    return _call("copy_file", [source, target])


def stage_game(installation: Path, game: Path):
    """Copy the directories OpenGothic reads from a Gothic II installation."""
    return _call("stage_game", [installation, game])


def main():
    return _call("main", [])


if __name__ == "__main__":
    main()
