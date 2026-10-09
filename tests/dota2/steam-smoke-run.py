#!/usr/bin/env python3
"""Boot Vinix and isolate actual Valve Steam API initialization from Dota."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import time

REPO = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location("dota_guest_vm", Path(__file__).with_name("_guest_vm_native.py"))
_vm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_vm)


def install(source: Path, destination: Path) -> None:
    return _vm.call("steam-install", globals(), source, destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-root", type=Path, default=REPO / "build/dota2/game-test/root")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-steam-smoke")
    parser.add_argument("--library", type=Path, default=REPO / "build/dota2/steamcmd/steamapps/content/app_570/depot_373306/game/bin/linuxsteamrt64/libsteam_api.so")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--mode", choices=("anonymous", "safe", "safe-anonymous", "load"), default="anonymous")
    parser.add_argument("--game-library-priority", action="store_true",
                        help="Use the game's shared libraries first and the launcher's soft limits")
    parser.add_argument("--pin-network-manager", action="store_true",
                        help="Retain the real libnm while testing client unload and reload")
    parser.add_argument("--load-tier0", action="store_true",
                        help="Load actual game tier0 globally before Steam API; implies game library priority")
    parser.add_argument("--ld-debug-bindings", action="store_true",
                        help="Record the guest glibc loader's actual symbol bindings")
    parser.add_argument("--extra-preload", type=Path, action="append", default=[],
                        help="Add a test-only x86-64 library to the guest preloads; repeatable")
    parser.add_argument("--game-env", action="append", default=[], metavar="NAME=VALUE",
                        help="Set a translated target environment variable with QEMU -E; repeatable")
    parser.add_argument("--strace", action="store_true")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    return _vm.call("steam-main", globals(), args, parser)


if __name__ == "__main__":
    main()
