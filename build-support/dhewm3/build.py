#!/usr/bin/env python3
"""Build one ARM64/musl dhewm3 binary for Vinix and the Linux comparison."""
from __future__ import annotations

import concurrent.futures
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path(os.environ.get("VINIX_DHEWM3_BUILD_DIR", ROOT / "build-aarch64-dhewm3")).resolve()
X11 = Path(os.environ.get("VINIX_X11_BUILD_DIR", ROOT / "build-aarch64-x11")).resolve()
TAG = "1.5.5"
COMMIT = "455b88e8dff2be822f08eb498f51b383e851fa38"
MIRROR = "https://dl-cdn.alpinelinux.org/alpine/v3.21"
DEMO_URL = "https://files.holarse-linuxgaming.de/native/Spiele/Doom%203/Demo/doom3-linux-1.1.1286-demo.x86.run"
DEMO_MD5 = "70c2c63ef1190158f1ebd6c255b22d8e"


import importlib.util as _import_util
_bindings_spec = _import_util.spec_from_file_location("dhewm_build_bindings", ROOT / "build-support/android/_boot_native.py")
_bindings = _import_util.module_from_spec(_bindings_spec)
_bindings_spec.loader.exec_module(_bindings)
_controller = _bindings._host.Controller(Path(__file__).with_name("build_query.v"), "VINIX_DHEWM_BUILD_QUERY",
                                        process=_bindings._build_process)


def _query(operation, **values):
    return _bindings.query_call(_controller, {"operation": operation}, globals(), values=values)


def download(url: str, path: Path) -> None:
    return _query("download", url=url, path=path)


_native_download = download


def _pool(**kwargs):
    return concurrent.futures.ThreadPoolExecutor(**kwargs)


def _fetch(downloads, line):
    return _query("fetch", downloads=downloads, line=line)


def main() -> None:
    return _query("main")


if __name__ == "__main__":
    main()
