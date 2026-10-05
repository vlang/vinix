#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and check a Limine 12.8 UEFI bundle with an authenticated initramfs root."""

from __future__ import annotations

import argparse
import hashlib
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


def digest(path: Path) -> str:
    result = hashlib.blake2b()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def check_cmdline(value: str, verity_token: str | None = None) -> str:
    # Limine expands ${macros} and accepts multiline configuration. Accept only
    # literal, printable tokens; no shell quoting or config/macros are needed.
    if len(value) > 2048 or not re.fullmatch(r"[A-Za-z0-9_.,=+:/ -]*", value):
        raise InvalidBundle("command line must contain literal ASCII tokens (at most 2048 bytes)")
    # Several existing disk selectors use substring matching, so testing only
    # token prefixes would allow e.g. x=vinix.disk=auto to bypass this profile.
    if any(option in value for option in DISK_OPTIONS):
        raise InvalidBundle("verified initramfs profile forbids disk root and persistence selectors")
    if verity_token:
        root_call(verity.parse_command_line, verity_token)
        tokens = value.split()
        if (not tokens or tokens[-1] != verity_token or tokens.count(verity_token) != 1
                or "vinix.verity" in " ".join(tokens[:-1])):
            raise InvalidBundle("verified root policy must contain exactly one generated final token")
    elif "vinix.verity" in value:
        raise InvalidBundle("verified block roots require the explicit --verity-root options")
    return value.strip()


def root_call(function, *args):
    try:
        return function(*args)
    except verity.InvalidImage as error:
        raise InvalidBundle(str(error)) from error


def pe_info(data: bytes, arch: str) -> tuple[int, int]:
    """Validate the PE and locate Limine's hash field in a mapped section."""
    try:
        if data[:2] != b"MZ":
            raise InvalidBundle("loader is not a PE executable")
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        if data[pe:pe + 4] != b"PE\0\0":
            raise InvalidBundle("invalid PE signature")
        machine, sections = struct.unpack_from("<HH", data, pe + 4)
        optional_size = struct.unpack_from("<H", data, pe + 20)[0]
        optional = pe + 24
        if machine != ARCHES[arch][0] or struct.unpack_from("<H", data, optional)[0] != 0x20B:
            raise InvalidBundle("loader architecture does not match the requested architecture")
        if struct.unpack_from("<H", data, optional + 68)[0] != 10:
            raise InvalidBundle("loader is not an EFI application")
        if optional_size < 152 or struct.unpack_from("<I", data, optional + 108)[0] < 5:
            raise InvalidBundle("PE has no certificate data directory")
        certificate, certificate_size = struct.unpack_from("<II", data, optional + 144)
        if bool(certificate) != bool(certificate_size) or certificate + certificate_size > len(data):
            raise InvalidBundle("invalid PE certificate directory")
        locations = [match.start() for match in re.finditer(re.escape(CONFIG_MARKER), data)]
        if len(locations) != 1:
            raise InvalidBundle("loader must contain exactly one Limine config hash field")
        start = locations[0] + len(CONFIG_MARKER)
        if not re.fullmatch(b"[0-9a-fA-F]{128}", data[start:start + 128]):
            raise InvalidBundle("invalid Limine config hash field")
        mapped = False
        for index in range(sections):
            section = optional + optional_size + index * 40
            size, offset = struct.unpack_from("<II", data, section + 16)
            if offset + size > len(data):
                raise InvalidBundle("truncated PE section")
            if offset <= locations[0] and start + 128 <= offset + size:
                mapped = True
        if not mapped or (certificate and locations[0] < certificate + certificate_size
                          and start + 128 > certificate):
            raise InvalidBundle("Limine config hash field must be in a signed, mapped PE section")
        loader_arch = "x86-64" if arch == "x86_64" else arch
        if f"Limine 12.8.0 ({loader_arch}, UEFI)".encode() not in data:
            raise InvalidBundle("a trusted Limine 12.8.0 loader is required")
        return start, certificate_size
    except (struct.error, IndexError) as error:
        raise InvalidBundle("truncated PE executable") from error


def check_kernel(path: Path, arch: str) -> None:
    with path.open("rb") as stream:
        header = stream.read(64)
    if (len(header) != 64 or header[:6] != b"\x7fELF\x02\x01"
            or struct.unpack_from("<H", header, 18)[0] != ARCHES[arch][1]):
        raise InvalidBundle("kernel must be a little-endian ELF64 image for the requested architecture")


def config_text(kernel_hash: str, module_hashes: list[str], cmdline: str,
                dtb_hash: str | None = None, verity_token: str | None = None) -> str:
    lines = ["timeout: 0", "verbose: yes", "serial: yes", "editor_enabled: no", "hash_mismatch_panic: yes",
             "", "/Vinix verified initramfs", "    protocol: limine",
             f"    path: boot():/boot/vinix#{kernel_hash}",
             f"    cmdline: {check_cmdline(cmdline, verity_token)}", "    resolution: 1024x768x32", "    kaslr: yes"]
    for index, module_hash in enumerate(module_hashes):
        lines.append(f"    module_path: boot():/boot/root-{index}.tar#{module_hash}")
    if dtb_hash:
        lines.append(f"    dtb_path: boot():/boot/platform.dtb#{dtb_hash}")
    return "\n".join(lines) + "\n"


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
    if path.is_symlink() or not path.is_file():
        raise InvalidBundle(f"bundle file is missing, not regular, or a symlink: {path}")
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
