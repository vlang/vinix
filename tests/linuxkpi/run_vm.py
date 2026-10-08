#!/usr/bin/env python3
"""Boot a disposable x86-64 guest and require native LinuxKPI test markers."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time
import json
import sys
from _guest_native import workflow

ROOT = Path(__file__).resolve().parents[2]
_manifest_source = (ROOT / "tests/agx-fake-g17/agxhost/linux_guest_data.v").read_text()
_manifest = _manifest_source.split("const linux_guest_manifest = r\'", 1)[1].split("\'\n", 1)[0]
globals().update(json.loads(_manifest))
del _manifest, _manifest_source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--firmware", type=Path)
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--limine-dir", type=Path, help="copy an existing bootloader cache; the ISO builder verifies its pinned hashes")
    parser.add_argument("--cpu", default="max")
    parser.add_argument("--no-linuxkpi", action="store_true", help="check a default kernel without the API layer")
    parser.add_argument("--mmap-lease-test", action="store_true", help="require the opt-in native mapping lifetime fixture")
    parser.add_argument("--pci-topology-test", action="store_true", help="require the opt-in native PCI topology fixture")
    parser.add_argument("--timeout", type=int, default=90)
    args = parser.parse_args()
    return workflow(ROOT, args, globals())


if __name__ == "__main__":
    raise SystemExit(main())
