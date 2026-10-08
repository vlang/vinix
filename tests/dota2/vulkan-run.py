#!/usr/bin/env python3
"""Boot actual ARM64 Vinix and exercise translated glibc lavapipe/X11."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from runpy import run_path
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tarfile
import time

_native_request = run_path(str(Path(__file__).with_name("_native.py")))["request"]

REPO = Path(__file__).resolve().parents[2]
BASE64_LINE = 76

import importlib.util
_spec = importlib.util.spec_from_file_location("dota2_vulkan_vm_native", Path(__file__).with_name("_vulkan_vm_native.py"))
_vm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_vm)


def decode_capture(transcript: bytes) -> bytes:
    return bytes.fromhex(_native_request("capture", transcript))

def copy_layer(source: Path, target: Path) -> None:
    return _vm.call('copy_layer', globals(), source, target)


def complete_native_closure(root: Path) -> None:
    return _vm.call('complete_native_closure', globals(), root)


def install_native_translator(staging: Path, root: Path) -> None:
    return _vm.call('install_native_translator', globals(), staging, root)


def retain_software_gl(source: Path, guest: Path) -> None:
    return _vm.call('retain_software_gl', globals(), source, guest)


def prepare(args, work: Path) -> Path:
    return _vm.call('prepare', globals(), args, work)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staging", type=Path, default=REPO / "build/dota2-vulkan/staging")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-vulkan/test")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--venus", action="store_true",
                        help="boot on KekVM's GPU and render with the staged x86-64 Venus driver")
    args = parser.parse_args()
    return _vm.call("boot", globals(), args)


if __name__ == "__main__":
    main()
