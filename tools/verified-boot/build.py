#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and check a Limine 12.8 UEFI bundle with an authenticated initramfs root."""

from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import tarfile
from runpy import run_path


CONFIG_MARKER = b"++CONFIG_B2SUM_SIGNATURE++"
ARCHES = {"x86_64": (0x8664, 62, "BOOTX64.EFI"), "aarch64": (0xAA64, 183, "BOOTAA64.EFI")}
DISK_OPTIONS = ("vinix.disk=", "vinix.qemu_persist=", "vinix.qemu_root=",
                "vinix.apple_ans=", "vinix.ans_rw=", "vinix.persist=", "vinix.root", "root=")
_verity_spec = importlib.util.spec_from_file_location(
    "vinix_verified_root", Path(__file__).resolve().parent.parent / "verified-root/build.py")
verity = importlib.util.module_from_spec(_verity_spec)
_verity_spec.loader.exec_module(verity)


class InvalidBundle(ValueError):
    pass


_native_spec = importlib.util.spec_from_file_location("vinix_boot_policy_native", Path(__file__).with_name("_native.py"))
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def _call(operation, **fields):
    try:
        return _native.request(operation, **fields)
    except ValueError as error:
        raise InvalidBundle(str(error)) from error


def digest(path: Path) -> str:
    return _call("digest", path=str(path))


def check_cmdline(value: str, verity_token: str | None = None) -> str:
    # Limine expands ${macros} and accepts multiline configuration. Accept only
    # literal, printable tokens; no shell quoting or config/macros are needed.
    if not isinstance(value, str):
        if len(value) > 2048:
            raise InvalidBundle("command line must contain literal ASCII tokens (at most 2048 bytes)")
        re.fullmatch("", value)  # Preserve the Python buffer/type boundary.
    return _call("check_cmdline", value=value, verity_token=verity_token or "")


_bundle_binding = run_path(str(Path(__file__).resolve().parents[1] / "_package_store_native.py"))
_bundle_Popen = subprocess.Popen
_bundle_controller = _bundle_binding["_host"].Controller(Path(__file__).with_name("bundle_query.v"), "VINIX_BOOT_BUNDLE_QUERY",
    process=lambda *args, **kwargs: _bundle_Popen(*args, start_new_session=True, **kwargs))


def _bundle_call(operation, arguments):
    return _bundle_binding["call"](operation, arguments, globals(), controller=_bundle_controller)


def _bundle_iterator(operation, iterator):
    def values():
        while True:
            packet = _bundle_call(operation, (iterator,))
            if packet["done"]:
                return
            yield packet["value"]
    generator = values()
    generator.__name__ = "<genexpr>"
    generator.__qualname__ = "build_bundle.<locals>.<genexpr>"
    return generator


def _bundle_three(value):
    first, second, third = value
    return first, second, third


def root_call(function, *args):
    return _bundle_call('root_call', (function, *args))


def pe_info(data: bytes, arch: str) -> tuple[int, int]:
    return tuple(_call("pe_info", data=memoryview(data).hex(), arch=arch))


def check_kernel(path: Path, arch: str) -> None:
    _call("check_kernel", path=str(path), arch=arch)


def config_text(kernel_hash: str, module_hashes: list[str], cmdline: str,
                dtb_hash: str | None = None, verity_token: str | None = None) -> str:
    checked = check_cmdline(cmdline, verity_token)
    return _call("config_text", kernel_hash=f"{kernel_hash}",
                 module_hashes=[f"{value}" for value in module_hashes], cmdline=checked,
                 dtb_hash=f"{dtb_hash}" if dtb_hash else "", verity_token=verity_token or "")


def command(args: list[str]) -> None:
    return _bundle_call('command', (args,))


def sign_image(source: Path, destination: Path, key: Path, certificate: Path, backend: str) -> None:
    return _bundle_call('sign_image', (source, destination, key, certificate, backend))


def verify_signature(loader: Path, certificate: Path, backend: str) -> None:
    return _bundle_call('verify_signature', (loader, certificate, backend))


def regular_file(path: Path) -> Path:
    _call("regular_file", path=str(path))
    return path


def verify_bundle(bundle: Path, arch: str, certificate: Path | None, backend: str,
                  developer: bool = False) -> None:
    return _bundle_call('verify_bundle', (bundle, arch, certificate, backend, developer))


def build_bundle(args: argparse.Namespace) -> None:
    return _bundle_call('build_bundle', (args,))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="operation", required=True)
    build = commands.add_parser("build", help="create a new UEFI boot tree")
    build.add_argument("--loader", type=Path, required=True, help="trusted unsigned Limine 12.8.0 EFI loader")
    build.add_argument("--kernel", type=Path, required=True)
    build.add_argument("--initramfs", type=Path, action="append", required=True,
                       help="root archive and optional overlays, in application order")
    build.add_argument("--dtb", type=Path)
    build.add_argument("--output", type=Path, required=True)
    build.add_argument("--key", type=Path, help="PEM private signing key; never copied to the output")
    build.add_argument("--cmdline", default="")
    build.add_argument("--verity-root", type=Path, help="block-root image with appended SHA-256 tree")
    build.add_argument("--verity-device", help="exact guest /dev block-device path for the image")
    build.add_argument("--verity-data-blocks", type=int, help="separately trusted count from verified-root build")
    build.add_argument("--verity-root-hash", help="separately trusted SHA-256 root from verified-root build")
    verify = commands.add_parser("verify", help="check signatures, enrolled policy, and every boot artifact")
    verify.add_argument("bundle", type=Path)
    for subcommand in (build, verify):
        subcommand.add_argument("--arch", choices=ARCHES, required=True)
        subcommand.add_argument("--certificate", type=Path,
                                help="trusted PEM signing certificate supplied separately from the bundle")
        subcommand.add_argument("--backend", choices=("sbsign", "osslsigncode"), default="sbsign")
        subcommand.add_argument("--developer-unsigned", action="store_true",
                                help="explicitly allow unauthenticated development output")
    args = parser.parse_args()
    try:
        if args.operation == "build":
            build_bundle(args)
        else:
            verify_bundle(args.bundle, args.arch, args.certificate, args.backend, args.developer_unsigned)
            print("Bundle verified." if not args.developer_unsigned else
                  "Developer bundle checksums verified; boot is UNAUTHENTICATED.")
    except (InvalidBundle, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"ERROR: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
