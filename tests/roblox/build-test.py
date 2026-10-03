#!/usr/bin/env python3
"""Check Roblox launcher provenance and safe shared-runtime publication.

ART, bionic and ATL payload receipt verification have their own Android suite.
These fixtures isolate the integration with those readers and use the real
native ELF validator for the private loader and compatibility library.
"""
from __future__ import annotations

from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(specification)
    assert specification and specification.loader
    specification.loader.exec_module(result)
    return result


BUILDER = module("roblox_builder_test", ROOT / "build-support/roblox/build.py")
ART = module("roblox_art_test", ROOT / "build-support/android/art-runtime.py")


def elf(machine: int = 183) -> bytes:
    header = bytearray(120)
    header[:7] = b"\x7fELF\x02\x01\x01"
    struct.pack_into("<HHI", header, 16, 3, machine, 1)
    struct.pack_into("<Q", header, 32, 64)
    struct.pack_into("<HH", header, 54, 56, 1)
    struct.pack_into("<IIQQQQQQ", header, 64, 1, 5, 0, 0, 0, 120, 120, 16384)
    return bytes(header)


class StagingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="vinix-roblox-staging-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.android = self.directory / "android/staging"
        self.runtime = self.android / BUILDER.PREFIX
        self.build = self.directory / "roblox"
        self.art = {"source_commit": "art-source", "patch_sha256": "art-patch",
                    "bootclasspath": {"verified": True}}
        self.bionic = {"source_commit": "bionic-source", "patch_sha256": "bionic-patch"}
        self.atl = {"source_commit": "atl-source", "builder_sha256": "atl-builder"}
        self.musl = {"libc_so_sha256": "native-libc"}
        self.readers = SimpleNamespace(read_manifest=lambda root: deepcopy(self.art),
                                       read_bionic_manifest=lambda root: deepcopy(self.bionic),
                                       read_atl_manifest=lambda root: deepcopy(self.atl),
                                       validate_atl_art_pair=lambda art, atl: None, _elf=ART._elf)
        patched = patch.object(BUILDER, "art_tools", return_value=self.readers)
        patched.start()
        self.addCleanup(patched.stop)
        patched_musl = patch.object(BUILDER, "musl_tools", return_value=SimpleNamespace(
            read_manifest=lambda root: deepcopy(self.musl)))
        patched_musl.start()
        self.addCleanup(patched_musl.stop)
        self.manifest = {"architecture": "aarch64", "execution": "native", "page_size": 16384,
                         "runtime_prefix": "/" + BUILDER.PREFIX, "art": self.art,
                         "bionic": self.bionic, "atl": self.atl, "musl": self.musl}
        self.write_runtime_manifest()
        self.write("architecture", b"aarch64\n")
        self.write("lib/ld-musl-aarch64.so.1", elf())
        self.write("usr/lib/libvinix-android-compat.so", elf())
        launcher = self.android / "usr/bin/run-android"
        launcher.parent.mkdir(parents=True)
        launcher.write_bytes((ROOT / "build-support/android/run-android").read_bytes())
        launcher.chmod(0o755)

    def write(self, name: str, contents: bytes) -> None:
        path = self.runtime / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)

    def write_runtime_manifest(self) -> None:
        self.write("runtime-manifest.json", (json.dumps(self.manifest) + "\n").encode())

    def stage(self) -> Path:
        return BUILDER.stage_launchers(self.build, self.android)

    def test_stage_contains_only_verified_native_launchers(self) -> None:
        stage = self.stage()
        expected = {"usr/bin/run-roblox", "usr/bin/run-roblox-client", BUILDER.RECEIPT}
        self.assertEqual({p.relative_to(stage).as_posix() for p in stage.rglob("*") if p.is_file()}, expected)
        manifest = BUILDER.validate_stage(stage, self.android)
        self.assertEqual(manifest["architecture"], "aarch64")
        self.assertEqual(manifest["execution"], "native")
        self.assertEqual(manifest["page_size"], 16384)
        self.assertFalse(manifest["apk_bundled"])
        for name in BUILDER.COMMANDS:
            self.assertEqual((stage / "usr/bin" / name).read_bytes(), (BUILDER.SUPPORT / name).read_bytes())

    def test_invalid_shared_runtime_keeps_previous_launchers(self) -> None:
        stage = self.stage()
        previous = (stage / BUILDER.RECEIPT).read_bytes()
        self.manifest["architecture"] = "x86_64"
        self.write_runtime_manifest()
        with self.assertRaisesRegex(RuntimeError, "native ARM64"):
            self.stage()
        self.assertEqual((stage / BUILDER.RECEIPT).read_bytes(), previous)

    def test_changed_runtime_generation_requires_restage(self) -> None:
        stage = self.stage()
        self.manifest["generation"] = "updated runtime"
        self.write_runtime_manifest()
        with self.assertRaisesRegex(RuntimeError, "rebuild the Roblox layer"):
            BUILDER.validate_stage(stage, self.android)
        self.assertEqual(BUILDER.validate_stage(self.stage(), self.android)["android_runtime_manifest_sha256"],
                         BUILDER.digest(self.runtime / "runtime-manifest.json"))

    def test_framework_receipt_mismatch_is_rejected(self) -> None:
        self.manifest["atl"] = {"source_commit": "stale-framework"}
        self.write_runtime_manifest()
        with self.assertRaisesRegex(RuntimeError, "native ARM64"):
            self.stage()

    def test_missing_or_stale_android_launcher_is_rejected(self) -> None:
        launcher = self.android / "usr/bin/run-android"
        launcher.write_text("#!/bin/sh\nexit 0\n")
        with self.assertRaisesRegex(RuntimeError, "stale launcher"):
            self.stage()
        launcher.unlink()
        with self.assertRaisesRegex(RuntimeError, "Build the native Android runtime"):
            self.stage()

    def test_foreign_loader_and_compatibility_library_are_rejected(self) -> None:
        for relative in ("lib/ld-musl-aarch64.so.1", "usr/lib/libvinix-android-compat.so"):
            self.write(relative, elf(62))
            with self.assertRaisesRegex(RuntimeError, "native ARM64 ELF"):
                self.stage()
            self.write(relative, elf())

    def test_corrupt_or_nonexecutable_launcher_is_rejected(self) -> None:
        stage = self.stage()
        launcher = stage / "usr/bin/run-roblox"
        launcher.write_text("#!/bin/sh\nexit 0\n")
        with self.assertRaisesRegex(RuntimeError, "launcher is stale"):
            BUILDER.validate_stage(stage, self.android)
        launcher.write_bytes((BUILDER.SUPPORT / "run-roblox").read_bytes())
        launcher.chmod(0o644)
        with self.assertRaisesRegex(RuntimeError, "not executable"):
            BUILDER.validate_stage(stage, self.android)

    def test_alternate_runtime_payload_is_rejected(self) -> None:
        stage = self.stage()
        translator = stage / "usr/bin/qemu-x86_64"
        translator.write_bytes(elf())
        with self.assertRaisesRegex(RuntimeError, "only its native APK launchers"):
            BUILDER.validate_stage(stage, self.android)

    def test_publish_failure_restores_previous_stage(self) -> None:
        stage = self.stage()
        previous = (stage / BUILDER.RECEIPT).read_bytes()
        with patch.object(Path, "replace", side_effect=OSError("publication failed")):
            with self.assertRaisesRegex(OSError, "publication failed"):
                self.stage()
        self.assertEqual((stage / BUILDER.RECEIPT).read_bytes(), previous)
        BUILDER.validate_stage(stage, self.android)

    def test_shared_runtime_cannot_be_replaced_by_launcher_stage(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "separate from the shared Android"):
            BUILDER.stage_launchers(self.android.parent, self.android)
        self.assertTrue((self.runtime / "runtime-manifest.json").is_file())


if __name__ == "__main__":
    unittest.main()
