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
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("verified_boot", ROOT / "tools/verified-boot/build.py")
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


_LITERAL_CACHE = {}

_PE_VALUES = ("x86_64", "x86-64", "Limine 12.8.0 (", ", UEFI)")

_SLOT_KEYS = {
    "InvalidBundle": "InvalidBundle",
    "ARCHES": "ARCHES",
    "CONFIG_MARKER": "CONFIG_MARKER",
    "Namespace": "Namespace",
    "TemporaryDirectory": "TemporaryDirectory",
    "add": "add",
    "assertIn": "assertIn",
    "assertRaises": "assertRaises",
    "build": "build",
    "build_bundle": "build_bundle",
    "check_cmdline": "check_cmdline",
    "command_line": "command_line",
    "encode": "encode",
    "eq": "eq",
    "getitem": "getitem",
    "join": "join",
    "mul": "mul",
    "pack_into": "pack_into",
    "read_bytes": "read_bytes",
    "read_text": "read_text",
    "setitem": "setitem",
    "sub": "sub",
    "subTest": "subTest",
    "symlink_to": "symlink_to",
    "truediv": "truediv",
    "unlink": "unlink",
    "verify_bundle": "verify_bundle",
    "verity": "verity",
    "write_bytes": "write_bytes",
    "xor": "xor",
}

_controller = boot._bundle_binding['_host'].Controller(ROOT / "tests/verified-boot/policy-query.v",
                                                  "VINIX_BOOT_TEST_QUERY",
                                                  process=boot._bundle_controller.process)


def _query(operation, *arguments):
    locals_pin = {}
    return boot._bundle_binding['call'](operation, (locals_pin, *arguments), globals(), controller=_controller)



def _format(value):
    try:
        return f"{value}"
    except BaseException:
        value = None
        raise


def _dict_display(value):
    try:
        return {**value}
    except BaseException:
        value = None
        raise


def elf(arch):
    return _query("elf", arch)


def pe(arch="x86_64"):
    """A mapped PE header for parser tests only; this is never signed/booted."""
    return _query("pe", arch)


class Policy(unittest.TestCase):
    def test_bundle_enforces_all_artifacts_and_root_profile(self):
        return _query("bundle", self)

    def test_block_root_binds_geometry_and_all_hash_levels(self):
        return _query("block_root", self)


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
