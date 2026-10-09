#!/usr/bin/env python3
"""Start Roblox's Windows Player on Vinix through Wine and record how far it gets.

The client is fetched from Roblox's own deployment CDN, the way its installer
does, and laid out in a Wine prefix. Vinix then boots under QEMU/HVF with a
test init that starts RobloxPlayerBeta.exe on a private Xvfb display. The
serial transcript, Wine's log, Roblox's own logs and the frames the guest
uploads are kept below --work.

Requires scripts/build-x86-translation-aarch64.sh, the X11 and userland layers and a
kernel. Nothing proprietary is stored in the repository.
"""
from __future__ import annotations

import argparse
import runpy
import hashlib
import http.server
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import struct
import subprocess
import tarfile
import threading
import time
import urllib.request
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
VERSION_URL = "https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer"
CDN = "https://setup.rbxcdn.com"
# Where the installer unpacks each deployment package below the version
# directory. A package it does not know is refused rather than guessed at.
PACKAGES = {
    "RobloxApp.zip": "",
    "WebView2.zip": "",
    "shaders.zip": "shaders",
    "ssl.zip": "ssl",
    "content-avatar.zip": "content/avatar",
    "content-configs.zip": "content/configs",
    "content-fonts.zip": "content/fonts",
    "content-models.zip": "content/models",
    "content-sky.zip": "content/sky",
    "content-sounds.zip": "content/sounds",
    "content-textures2.zip": "content/textures",
    "content-textures3.zip": "PlatformContent/pc/textures",
    "content-terrain.zip": "PlatformContent/pc/terrain",
    "content-platform-fonts.zip": "PlatformContent/pc/fonts",
    "content-platform-dictionaries.zip": "PlatformContent/pc/shared_compression_dictionaries",
    "extracontent-places.zip": "ExtraContent/places",
    "extracontent-luapackages.zip": "ExtraContent/LuaPackages",
    "extracontent-translations.zip": "ExtraContent/translations",
    "extracontent-models.zip": "ExtraContent/models",
    "extracontent-textures.zip": "ExtraContent/textures",
}
# The Edge runtime installer and the bootstrapper are not part of the client.
SKIPPED = ("WebView2RuntimeInstaller.zip", "RobloxPlayerInstaller.exe")
APP_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<Settings>
\t<ContentFolder>content</ContentFolder>
\t<BaseUrl>http://www.roblox.com</BaseUrl>
</Settings>
"""
TOOLS = ("sh", "cat", "mkdir", "chmod", "sleep", "uname", "grep", "ps", "tail", "head", "ls",
         "wget", "kill", "rm", "ln", "find", "sed", "cut", "wc", "tr", "date", "cp", "mv", "env")
# Layers of the translation stage this test has no use for.
UNUSED = ("root/.wine-word2013-x86_64", "root/.wine-office2010-x86_64", "root/word2013-media",
          "root/office2010-media", "root/.wine-x86_32", "usr/libexec/vinix-i386")
FAILURES = (b"KERNEL PANIC", b"ROBLOX-WINDOWS-FAIL")


_native = runpy.run_path(str(Path(__file__).with_name("_native.py")))

def _host(operation, *arguments):
    return _native["host"](operation, globals(), *arguments)

def _guest(operation, *arguments):
    return _native["guest"](operation, globals(), *arguments)

def _reader(source):
    reader = lambda: source.read(1024 * 1024)
    reader.__qualname__ = "md5.<locals>.<lambda>"
    return reader

def _checks(markers, transcript):
    checks = (marker in transcript for marker in markers)
    checks.__qualname__ = "run_guest.<locals>.<genexpr>"
    return checks

def _handler(directory):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            return _host("upload", self, directory)
        def log_message(self, *_):
            pass
    Handler.__qualname__ = "serve_uploads.<locals>.Handler"
    Handler.do_POST.__qualname__ = "serve_uploads.<locals>.Handler.do_POST"
    Handler.log_message.__qualname__ = "serve_uploads.<locals>.Handler.log_message"
    return Handler


def download(url: str, target: Path) -> None:
    return _host('download', url, target)


def md5(path: Path) -> str:
    return _host('md5', path)


def fetch(work: Path, version: str | None) -> tuple[str, Path]:
    """Download one deployment's packages, checking each against its manifest."""
    return _host('fetch', work, version)


def stage(downloads: Path, client: Path) -> None:
    """Unpack the packages into the layout the Windows installer produces."""
    return _host('stage', downloads, client)


def copy_layer(source: Path, dest: Path, skip: tuple[str, ...] = (), base: Path | None = None) -> None:
    return _host('copy_layer', source, dest, skip, base)


def prepare(args, work: Path, client: Path, version: str) -> Path:
    return _host('prepare', args, work, client, version)


def xwd_to_png(source: Path, target: Path) -> bool:
    """Convert Xvfb's 24-bit framebuffer dump; report whether anything is drawn."""
    return _host('xwd_to_png', source, target)


def serve_uploads(directory: Path, port: int) -> http.server.ThreadingHTTPServer:
    """Take what the guest posts: its framebuffer and Roblox's log files."""
    return _host('serve_uploads', directory, port)


def stop(pid: int, master: int) -> None:
    return _guest('stop', pid, master)


def run_guest(args, work: Path, root: Path) -> bytes:
    return _guest('run_guest', args, work, root)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=ROOT, help="checkout holding the layers and scripts/run-aarch64.sh")
    parser.add_argument("--kernel-dir", type=Path, help="kernel directory holding bin/vinix")
    parser.add_argument("--translation", type=Path,
                        help="stage of scripts/build-x86-translation-aarch64.sh; the checkout's otherwise")
    parser.add_argument("--work", type=Path, default=ROOT / "build/roblox-windows")
    parser.add_argument("--version", help="deployment to test, e.g. version-02c37bc51a384b8f; the current one otherwise")
    parser.add_argument("--winedebug", default="fixme-all,err+all", help="WINEDEBUG for the client")
    parser.add_argument("--arguments", default="", help="arguments for RobloxPlayerBeta.exe")
    parser.add_argument("--seconds", type=int, default=300, help="how long the guest watches the client")
    parser.add_argument("--timeout", type=int, default=1500, help="host limit for the whole boot")
    parser.add_argument("--strace", action="store_true",
                        help="report the system calls the translator could not serve, not Wine's log")
    parser.add_argument("--shell", action="store_true",
                        help="give the guest a shell on its console instead of starting the client")
    parser.add_argument("--mem", type=int, default=12288)
    parser.add_argument("--cpus", type=int, default=4)
    parser.add_argument("--port", type=int, default=18791, help="host port the guest uploads to")
    args = parser.parse_args()
    return _host("main", args)


if __name__ == "__main__":
    main()
