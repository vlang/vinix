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


def root_call(function, *args):
    try:
        return function(*args)
    except verity.InvalidImage as error:
        raise InvalidBundle(str(error)) from error


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
    subprocess.run(args, check=True, stdin=subprocess.DEVNULL)


def sign_image(source: Path, destination: Path, key: Path, certificate: Path, backend: str) -> None:
    if backend == "sbsign":
        command(["sbsign", "--key", str(key), "--cert", str(certificate),
                 "--output", str(destination), str(source)])
    else:
        command(["osslsigncode", "sign", "-h", "sha256", "-certs", str(certificate),
                 "-key", str(key), "-in", str(source), "-out", str(destination)])


def verify_signature(loader: Path, certificate: Path, backend: str) -> None:
    if backend == "sbsign":
        command(["sbverify", "--cert", str(certificate), str(loader)])
    else:
        command(["osslsigncode", "verify", "-CAfile", str(certificate), "-in", str(loader)])


def regular_file(path: Path) -> Path:
    _call("regular_file", path=str(path))
    return path


def verify_bundle(bundle: Path, arch: str, certificate: Path | None, backend: str,
                  developer: bool = False) -> None:
    bundle = bundle.resolve()
    # Reject symlinked parents as well as leaf files, and extra executables or
    # content. A verification result describes this exact generated boot tree.
    files: set[str] = set()
    for path in bundle.rglob("*"):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise InvalidBundle(f"bundle contains a symlink or special file: {path}")
        if path.is_file():
            files.add(path.relative_to(bundle).as_posix())
    loader_relative = f"EFI/BOOT/{ARCHES[arch][2]}"
    loader = regular_file(bundle / loader_relative)
    data = loader.read_bytes()
    field, signature_size = pe_info(data, arch)
    if developer:
        if signature_size:
            raise InvalidBundle("developer bundle unexpectedly contains a PE signature")
    else:
        if certificate is None or not signature_size:
            raise InvalidBundle("signed mode requires a signature and a separately trusted certificate")
        verify_signature(loader, certificate.resolve(), backend)
    config = regular_file(bundle / "boot/limine.conf")
    if data[field:field + 128].decode().lower() != digest(config):
        raise InvalidBundle("configuration differs from the hash enrolled in the loader")
    text = config.read_text(encoding="ascii")
    kernel_match = re.search(r"^    path: boot\(\):/boot/vinix#([0-9a-f]{128})$", text, re.M)
    modules = re.findall(r"^    module_path: boot\(\):/boot/root-([0-9]+)\.tar#([0-9a-f]{128})$", text, re.M)
    cmdline_match = re.search(r"^    cmdline: (.*)$", text, re.M)
    dtb = re.search(r"^    dtb_path: boot\(\):/boot/platform\.dtb#([0-9a-f]{128})$", text, re.M)
    if not kernel_match or not modules or not cmdline_match:
        raise InvalidBundle("configuration is not a verified initramfs profile")
    if [index for index, _ in modules] != [str(index) for index in range(len(modules))]:
        raise InvalidBundle("initramfs modules must have consecutive indexes")
    root_tokens = [token for token in cmdline_match[1].split() if token.startswith(verity.TOKEN_PREFIX)]
    if len(root_tokens) > 1:
        raise InvalidBundle("duplicate verified-root command-line policy")
    root_token = root_tokens[0] if root_tokens else None
    expected = config_text(kernel_match[1], [value for _, value in modules],
                           cmdline_match[1], dtb[1] if dtb else None, root_token)
    if text != expected:
        raise InvalidBundle("unexpected configuration directive or command line")
    hashes = {"boot/vinix": kernel_match[1]}
    hashes.update({f"boot/root-{index}.tar": value for index, value in modules})
    if dtb:
        hashes["boot/platform.dtb"] = dtb[1]
    expected_files = {loader_relative, "boot/limine.conf", *hashes}
    if root_token:
        expected_files.add("boot/verity-root.img")
    if files != expected_files:
        raise InvalidBundle("bundle contains missing or unexpected boot files")
    check_kernel(bundle / "boot/vinix", arch)
    for filename, expected_hash in hashes.items():
        if digest(regular_file(bundle / filename)) != expected_hash:
            raise InvalidBundle(f"boot artifact checksum mismatch: {filename}")
    if root_token:
        _, count, root_digest = root_call(verity.parse_command_line, root_token)
        root_call(verity.verify, regular_file(bundle / "boot/verity-root.img"), count, root_digest)


def build_bundle(args: argparse.Namespace) -> None:
    cmdline = check_cmdline(args.cmdline)
    root_image = getattr(args, "verity_root", None)
    root_device = getattr(args, "verity_device", None)
    root_count = getattr(args, "verity_data_blocks", None)
    root_digest = getattr(args, "verity_root_hash", None)
    root_token = None
    if any(value is not None for value in (root_image, root_device, root_count, root_digest)):
        if any(value is None for value in (root_image, root_device, root_count, root_digest)):
            raise InvalidBundle("verified block root requires --verity-root, --verity-device, "
                                "--verity-data-blocks and --verity-root-hash")
        root_token = root_call(verity.command_line, root_device, root_count, root_digest)
        cmdline = check_cmdline(f"{cmdline} {root_token}".strip(), root_token)
    output = args.output.absolute()
    if output.exists():
        raise InvalidBundle("output already exists; choose a new bundle directory")
    if not args.developer_unsigned and (args.key is None or args.certificate is None):
        raise InvalidBundle("signed mode requires --key and --certificate")
    if args.developer_unsigned and (args.key is not None or args.certificate is not None):
        raise InvalidBundle("developer mode cannot also specify signing credentials")
    loader_data = args.loader.read_bytes()
    field, signature_size = pe_info(loader_data, args.arch)
    if signature_size:
        raise InvalidBundle("loader input must be unsigned: enrollment must happen before signing")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".vinix-verified-", dir=output.parent) as temporary:
        staging = Path(temporary)
        boot = staging / "boot"
        efi = staging / "EFI/BOOT"
        boot.mkdir()
        efi.mkdir(parents=True)
        shutil.copyfile(args.kernel, boot / "vinix")
        check_kernel(boot / "vinix", args.arch)
        for index, source in enumerate(args.initramfs):
            shutil.copyfile(source, boot / f"root-{index}.tar")
        if root_image:
            shutil.copyfile(root_image, boot / "verity-root.img")
            root_call(verity.verify, boot / "verity-root.img", root_count, root_digest)
        dtb_hash = None
        if args.dtb:
            shutil.copyfile(args.dtb, boot / "platform.dtb")
            dtb_hash = digest(boot / "platform.dtb")
        config = boot / "limine.conf"
        config.write_text(config_text(digest(boot / "vinix"),
                                     [digest(boot / f"root-{index}.tar")
                                      for index in range(len(args.initramfs))], cmdline, dtb_hash, root_token),
                          encoding="ascii")
        # This is Limine's enroll-config format. Patching this field BEFORE
        # Authenticode signing puts the config hash inside the firmware's
        # authenticated executable, rather than beside it in a mutable file.
        enrolled = bytearray(loader_data)
        enrolled[field:field + 128] = digest(config).encode("ascii")
        loader = efi / ARCHES[args.arch][2]
        if args.developer_unsigned:
            loader.write_bytes(enrolled)
        else:
            unsigned = staging / "enrolled.efi"
            unsigned.write_bytes(enrolled)
            sign_image(unsigned, loader, args.key.resolve(), args.certificate.resolve(), args.backend)
            unsigned.unlink()
        verify_bundle(staging, args.arch, args.certificate, args.backend, args.developer_unsigned)
        os.rename(staging, output)
    mode = "UNAUTHENTICATED developer bundle" if args.developer_unsigned else "signed UEFI bundle"
    print(f"Created {mode}: {output}")
    if not args.developer_unsigned:
        print("Boot authentication requires UEFI Secure Boot enabled with this certificate trusted in firmware.")


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
