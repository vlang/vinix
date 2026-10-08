#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Host policy regressions; optional real PE-signature integration, never mocked."""

import argparse
import importlib.util
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verified_boot", ROOT / "tools/verified-boot/build.py")
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


def elf(arch):
    data = bytearray(64)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 18, boot.ARCHES[arch][1])
    return data


def pe(arch="x86_64"):
    """A mapped PE header for parser tests only; this is never signed/booted."""
    data = bytearray(2048)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 128)
    data[128:132] = b"PE\0\0"
    struct.pack_into("<HH", data, 132, boot.ARCHES[arch][0], 1)
    struct.pack_into("<H", data, 148, 240)
    struct.pack_into("<H", data, 152, 0x20B)
    struct.pack_into("<H", data, 220, 10)
    struct.pack_into("<I", data, 260, 16)
    struct.pack_into("<II", data, 408, 1024, 512)
    data[512:512 + len(boot.CONFIG_MARKER)] = boot.CONFIG_MARKER
    field = 512 + len(boot.CONFIG_MARKER)
    data[field:field + 128] = b"0" * 128
    label = f"Limine 12.8.0 ({'x86-64' if arch == 'x86_64' else arch}, UEFI)".encode()
    data[800:800 + len(label)] = label
    return data


class Policy(unittest.TestCase):
    def test_bundle_enforces_all_artifacts_and_root_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            (work / "loader").write_bytes(pe())
            (work / "kernel").write_bytes(elf("x86_64"))
            (work / "root").write_bytes(b"first archive")
            (work / "overlay").write_bytes(b"second archive")
            output = work / "bundle"
            args = argparse.Namespace(arch="x86_64", loader=work / "loader", kernel=work / "kernel",
                                      initramfs=[work / "root", work / "overlay"], output=output,
                                      cmdline="quiet", dtb=None, developer_unsigned=True,
                                      key=None, certificate=None, backend="sbsign")
            boot.build_bundle(args)
            boot.verify_bundle(output, "x86_64", None, "sbsign", True)
            with self.assertRaises(boot.InvalidBundle):
                boot.verify_bundle(output, "x86_64", None, "sbsign")
            with self.assertRaises(boot.InvalidBundle):
                boot.build_bundle(args)
            for filename in ("boot/vinix", "boot/root-0.tar", "boot/root-1.tar", "boot/limine.conf"):
                path = output / filename
                original = path.read_bytes()
                path.write_bytes(original + b"tamper")
                with self.subTest(filename=filename), self.assertRaises(boot.InvalidBundle):
                    boot.verify_bundle(output, "x86_64", None, "sbsign", True)
                path.write_bytes(original)
            (output / "EFI/BOOT/extra.efi").write_bytes(b"unexpected loader")
            with self.assertRaises(boot.InvalidBundle):
                boot.verify_bundle(output, "x86_64", None, "sbsign", True)
            (output / "EFI/BOOT/extra.efi").unlink()
            path = output / "boot/root-1.tar"
            path.unlink()
            path.symlink_to(work / "overlay")
            with self.assertRaises(boot.InvalidBundle):
                boot.verify_bundle(output, "x86_64", None, "sbsign", True)

    def test_block_root_binds_geometry_and_all_hash_levels(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            (work / "loader").write_bytes(pe())
            (work / "kernel").write_bytes(elf("x86_64"))
            (work / "bootstrap").write_bytes(b"authenticated bootstrap archive")
            (work / "data").write_bytes(b"x" * (129 * 4096))
            metadata = boot.verity.build(work / "data", work / "root-image")
            options = dict(arch="x86_64", loader=work / "loader", kernel=work / "kernel",
                           initramfs=[work / "bootstrap"], output=work / "bundle", cmdline="quiet",
                           dtb=None, developer_unsigned=True, key=None, certificate=None,
                           backend="sbsign", verity_root=work / "root-image", verity_device="/dev/vda",
                           verity_data_blocks=metadata["data_blocks"], verity_root_hash=metadata["root_hash"])
            boot.build_bundle(argparse.Namespace(**options))
            boot.verify_bundle(work / "bundle", "x86_64", None, "sbsign", True)
            token = boot.verity.command_line("/dev/vda", 129, metadata["root_hash"])
            config = work / "bundle/boot/limine.conf"
            self.assertIn(f"cmdline: quiet {token}\n", config.read_text())
            image = work / "bundle/boot/verity-root.img"
            original = image.read_bytes()
            for offset in (0, 129 * 4096, 130 * 4096, len(original) - 1):
                corrupt = bytearray(original)
                corrupt[offset] ^= 1
                image.write_bytes(corrupt)
                with self.subTest(offset=offset), self.assertRaises(boot.InvalidBundle):
                    boot.verify_bundle(work / "bundle", "x86_64", None, "sbsign", True)
            image.write_bytes(original)
            image.write_bytes(original[:-1])
            with self.assertRaises(boot.InvalidBundle):
                boot.verify_bundle(work / "bundle", "x86_64", None, "sbsign", True)
            image.write_bytes(original)
            for key in ("verity_root", "verity_device", "verity_data_blocks", "verity_root_hash"):
                incomplete = {**options, "output": work / "incomplete", key: None}
                with self.subTest(missing=key), self.assertRaises(boot.InvalidBundle):
                    boot.build_bundle(argparse.Namespace(**incomplete))
            for key, value in (("verity_data_blocks", 128), ("verity_root_hash", "0" * 64)):
                wrong = {**options, "output": work / "wrong", key: value}
                with self.subTest(key=key), self.assertRaises(boot.InvalidBundle):
                    boot.build_bundle(argparse.Namespace(**wrong))
            for value in (f"{token} {token}", f"x={token} {token}", f"{token} quiet"):
                with self.subTest(cmdline=value), self.assertRaises(boot.InvalidBundle):
                    boot.check_cmdline(value, token)


def integration(args):
    if not shutil.which("openssl"):
        raise RuntimeError("openssl is required")
    if not shutil.which("osslsigncode" if args.backend == "osslsigncode" else "sbsign"):
        raise RuntimeError("real signing tools are required")
    with tempfile.TemporaryDirectory(prefix="vinix-pe-signatures-") as temporary:
        work = Path(temporary)
        for identity in ("trusted", "other"):
            subprocess.run(["openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes",
                            "-sha256", "-subj", f"/CN=Vinix test {identity}", "-days", "1",
                            "-addext", "extendedKeyUsage=codeSigning",
                            "-keyout", str(work / f"{identity}.key"), "-out", str(work / f"{identity}.crt")],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for arch in boot.ARCHES:
            loader = getattr(args, arch + "_loader")
            if not loader:
                continue
            (work / "kernel").write_bytes(elf(arch))
            (work / "root").write_bytes(b"root archive bytes authenticated before unpacking")
            output = work / arch
            options = argparse.Namespace(arch=arch, loader=loader, kernel=work / "kernel",
                                         initramfs=[work / "root"], output=output, cmdline="quiet",
                                         dtb=None, developer_unsigned=False, key=work / "trusted.key",
                                         certificate=work / "trusted.crt", backend=args.backend)
            boot.build_bundle(options)
            image = output / f"EFI/BOOT/{boot.ARCHES[arch][2]}"
            with unittest.TestCase().assertRaises(subprocess.CalledProcessError):
                boot.verify_bundle(output, arch, work / "other.crt", args.backend)
            original = image.read_bytes()
            field, _ = boot.pe_info(original, arch)
            corrupted = bytearray(original)
            corrupted[field] = ord("a") if corrupted[field] != ord("a") else ord("b")
            image.write_bytes(corrupted)
            with unittest.TestCase().assertRaises(subprocess.CalledProcessError):
                boot.verify_bundle(output, arch, work / "trusted.crt", args.backend)
            image.write_bytes(original)
            for filename in ("boot/limine.conf", "boot/vinix", "boot/root-0.tar"):
                path = output / filename
                original_artifact = path.read_bytes()
                path.write_bytes(original_artifact + b"tamper")
                with unittest.TestCase().assertRaises(boot.InvalidBundle):
                    boot.verify_bundle(output, arch, work / "trusted.crt", args.backend)
                path.write_bytes(original_artifact)
            boot.verify_bundle(output, arch, work / "trusted.crt", args.backend)
            print(f"PASS {arch}: real PE signature, wrong certificate, signed-field tampering, config/kernel/initramfs tampering")
            (work / "block-data").write_bytes(b"verified block contents".ljust(8192, b"\0"))
            metadata = boot.verity.build(work / "block-data", work / f"block-image-{arch}")
            options.output = work / f"block-root-{arch}"
            options.verity_root = work / f"block-image-{arch}"
            options.verity_device = "/dev/vda"
            options.verity_data_blocks = metadata["data_blocks"]
            options.verity_root_hash = metadata["root_hash"]
            boot.build_bundle(options)
            boot.verify_bundle(options.output, arch, work / "trusted.crt", args.backend)
            root = options.output / "boot/verity-root.img"
            original_root = root.read_bytes()
            corrupt = bytearray(original_root)
            corrupt[0] ^= 1
            root.write_bytes(corrupt)
            with unittest.TestCase().assertRaises(boot.InvalidBundle):
                boot.verify_bundle(options.output, arch, work / "trusted.crt", args.backend)
            root.write_bytes(original_root)
            print(f"PASS {arch}: real PE signature authenticates block-root geometry and digest; tampered block image rejected")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--x86_64-loader", type=Path)
    parser.add_argument("--aarch64-loader", type=Path)
    parser.add_argument("--backend", choices=("sbsign", "osslsigncode"), default="sbsign")
    args = parser.parse_args()
    native = subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                             str(ROOT / "tools/verified-boot/bootpolicy/core_test.v")])
    if native.returncode:
        sys.exit(native.returncode)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(Policy)
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        sys.exit(1)
    if args.x86_64_loader or args.aarch64_loader:
        integration(args)
    else:
        print("Real PE-signature integration skipped: supply --x86_64-loader and/or --aarch64-loader.")
