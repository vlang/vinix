#!/usr/bin/env python3
"""Boot the AArch64 QEMU machine and enforce a hosted-application bring-up result."""

from __future__ import annotations

import argparse
import errno
import os
from pathlib import Path
import platform
import pty
import select
import signal
import socket
import sys
import time


# The bring-up boot drives a staged browser; the package boot installs one from
# the Alpine repositories first. They report separately because a machine
# without a network can still run the first.
BRING_UP = {
    "init": "tests/browsers/chromium-init.sh",
    "pass": b"VINIX CHROMIUM TEST: PASS",
    "fail": (b"VINIX CHROMIUM TEST: FAIL",),
    # Headless is run and reported but not required: it produces no DOM on
    # Vinix yet, while the graphical path — the one the desktop uses — renders
    # the whole browser. Requiring it would fail a run in which the browser
    # demonstrably works.
    "features": (
        b"VINIX CHROMIUM PASS: version",
        b"VINIX CHROMIUM PASS: the hosted display has a framebuffer",
        b"VINIX CHROMIUM PASS: browser window mapped",
        b"VINIX CHROMIUM PASS: the bridge reports drawing",
    ),
}
FIREFOX = {
    "init": "tests/browsers/firefox-init.sh",
    "pass": b"VINIX FIREFOX TEST: PASS",
    "fail": (b"VINIX FIREFOX TEST: FAIL",),
    "features": (
        b"VINIX FIREFOX PASS: the hosted display has a framebuffer",
        b"VINIX FIREFOX PASS: browser window mapped",
        b"VINIX FIREFOX PASS: the page was drawn",
    ),
}
# The desktop profile is the arrangement users actually see: the compositor
# hosting the browser's surface in an ordinary window. The other browser
# profiles run the same X11 bridge without a compositor, so a regression in the
# hosting path — where the browser was found to be starved by a compositor
# recomposing the screen twenty times a second for a picture that had not
# changed — passes them unnoticed.
DESKTOP = {
    "init": "tests/browsers/desktop-init.sh",
    "pass": b"VINIX DESKTOP FIREFOX TEST: PASS",
    "fail": (b"VINIX DESKTOP FIREFOX TEST: FAIL",),
    "features": (
        b"VINIX DESKTOP FIREFOX PASS: the hosted display has a framebuffer",
        b"VINIX DESKTOP FIREFOX PASS: browser window mapped",
        b"VINIX DESKTOP FIREFOX PASS: the page was drawn",
    ),
}
# LibreOffice is the same hosting path as the browsers, driven by a much
# heavier client: VCL builds a UNO service manager and reads its configuration
# registry before it maps a window at all, so the deadlines here are longer and
# the two halves — the window, then the page — are reported separately.
LIBREOFFICE = {
    "init": "tests/office/libreoffice-init.sh",
    "pass": b"VINIX LIBREOFFICE TEST: PASS",
    "fail": (b"VINIX LIBREOFFICE TEST: FAIL",),
    "features": (
        b"VINIX LIBREOFFICE PASS: the hosted display has a framebuffer",
        b"VINIX LIBREOFFICE PASS: Writer window mapped",
        b"VINIX LIBREOFFICE PASS: the document was drawn",
    ),
}
PACKAGE = {
    "init": "tests/browsers/pkg-init.sh",
    "pass": b"VINIX CHROMIUM PACKAGE TEST: PASS",
    "fail": (b"VINIX CHROMIUM PACKAGE TEST: FAIL",),
    "features": (
        b"VINIX CHROMIUM PASS: the image ships the launcher but not the browser",
        b"VINIX CHROMIUM PASS: pkg installed Chromium and its runtime",
        b"VINIX CHROMIUM PASS: the installed browser runs",
    ),
}
# First-run setup is the compositor's own flow rather than a hosted app: the
# registration screen, the app picker that follows it, and the Terminal that
# installs the chosen apps.
# Steam is Valve's x86 client on the translators. The boot checks the glibc
# runtime and the translators first, then waits for the updater to install
# the client and map its first window on the hosted X11 display.
STEAM = {
    "init": "tests/steam/steam-init.sh",
    "pass": b"VINIX STEAM TEST: PASS",
    "fail": (b"VINIX STEAM TEST: FAIL",),
    "features": (
        b"VINIX STEAM PASS: translated glibc runtime",
        b"VINIX STEAM PASS: System V semaphore wake",
        b"VINIX STEAM PASS: the hosted display has a framebuffer",
        b"VINIX STEAM PASS: client window mapped",
    ),
    "persist_size_mb": 12288,
}
FIRST_RUN = {
    "init": "tests/desktop/first-run-apps-init.sh",
    "pass": b"VINIX FIRST RUN TEST: PASS",
    "fail": (b"VINIX FIRST RUN TEST: FAIL",),
    "features": (
        b"VINIX FIRST RUN PASS: registration created the user",
        b"VINIX FIRST RUN PASS: the app picker follows registration",
        b"VINIX FIRST RUN PASS: the picker finished and the desktop started",
        b"VINIX FIRST RUN PASS: the Terminal installed the chosen apps",
    ),
}
COMMON_FAIL_MARKERS = (b"FATAL EXCEPTION", b"KERNEL PANIC")


def _native(operation, *arguments):
    import importlib.util
    spec = importlib.util.spec_from_file_location("browser_native_controller", Path(__file__).with_name("_native.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    globals()["_native"] = lambda operation, *arguments: module.call(operation, globals(), *arguments)
    return _native(operation, *arguments)


def _checks(markers, recent):
    return (marker in recent for marker in markers)


def available_port() -> str:
    return _native("available_port")


def exit_code(status: int) -> int:
    return _native("exit_code", status)


def stop_child(pid: int, master: int) -> None:
    return _native("stop_child", pid, master)


def run_vm(root: Path, guest_init: Path, initramfs: Path, state_dir: Path,
           memory_mb: int, timeout: int, build: bool, profile: dict) -> int:
    return _native("run_vm", root, guest_init, initramfs, state_dir,
                   memory_mb, timeout, build, profile)


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--firefox", action="store_true",
                        help="drive Firefox instead of Chromium")
    parser.add_argument("--desktop", action="store_true",
                        help="drive Firefox inside a compositor-managed window")
    parser.add_argument("--package", action="store_true",
                        help="install Chromium with pkg instead of driving a staged one")
    parser.add_argument("--libreoffice", action="store_true",
                        help="drive LibreOffice Writer instead of a browser")
    parser.add_argument("--first-run", action="store_true",
                        help="drive first-run registration and the app picker")
    parser.add_argument("--steam", action="store_true",
                        help="drive Valve's Steam client through the x86 translators")
    parser.add_argument("--init", type=Path)
    parser.add_argument("--initramfs", type=Path,
                        default=root / "build-support/init-aarch64/initramfs-desktop.tar")
    parser.add_argument("--state-dir", type=Path,
                        default=root / "build/browser-vm")
    parser.add_argument("--mem", type=int)
    # A package boot fetches a quarter of a gigabyte through QEMU's user
    # networking and unpacks it on an emulated CPU; the browser boots are the
    # quick ones.
    parser.add_argument("--timeout", type=int, default=0,
                        help="seconds to allow (default: 1800, or 5400 with --package)")
    parser.add_argument("--build", action="store_true",
                        help="rebuild the kernel before booting")
    arguments = parser.parse_args()
    if arguments.timeout < 0:
        parser.error("--timeout must be positive")
    if arguments.package and arguments.firefox:
        parser.error("--package installs Chromium; it cannot be combined with --firefox")
    if arguments.desktop and (arguments.package or arguments.firefox):
        parser.error("--desktop drives its own browser; it cannot be combined with another profile")
    if arguments.libreoffice and (arguments.desktop or arguments.package
                                  or arguments.firefox):
        parser.error("--libreoffice drives the office suite; it cannot be combined with another profile")
    if arguments.first_run and (arguments.libreoffice or arguments.desktop
                                or arguments.package or arguments.firefox):
        parser.error("--first-run drives setup itself; it cannot be combined with another profile")
    if arguments.steam and (arguments.first_run or arguments.libreoffice
                            or arguments.desktop or arguments.package
                            or arguments.firefox):
        parser.error("--steam drives Steam; it cannot be combined with another profile")
    profile = (STEAM if arguments.steam
               else FIRST_RUN if arguments.first_run
               else LIBREOFFICE if arguments.libreoffice
               else DESKTOP if arguments.desktop else PACKAGE if arguments.package
               else FIREFOX if arguments.firefox else BRING_UP)
    timeout = arguments.timeout or (5400 if arguments.package else 1800)
    guest_init = arguments.init or (root / profile["init"])
    memory_mb = arguments.mem if arguments.mem is not None else (32768 if arguments.steam else 8192)
    return run_vm(root, guest_init.resolve(), arguments.initramfs.resolve(),
                  arguments.state_dir.resolve(), memory_mb, timeout,
                  arguments.build, profile)


if __name__ == "__main__":
    raise SystemExit(main())
