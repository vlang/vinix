#!/usr/bin/env python3
"""Checks for native ART payload provenance, ELF ABI, and safe replacement."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import io
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
from argparse import Namespace
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("art_runtime", ROOT / "build-support/android/art-runtime.py")
art = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(art)


def elf(machine: int = 183, offset: int = 0) -> bytes:
    size = max(256, offset + 128)
    data = bytearray(size)
    data[:16] = b"\x7fELF\x02\x01\x01" + bytes(9)
    struct.pack_into("<HHIQQQIHHHHHH", data, 16,
                     3, machine, 1, 0x400080, 64, 0, 0, 64, 56, 1, 0, 0, 0)
    struct.pack_into("<IIQQQQQQ", data, 64,
                     1, 5, offset, 0x400000, 0, size - offset, size - offset, 16384)
    return bytes(data)


def dex(callsites: int = 0) -> bytes:
    descriptor = b"Landroid/os/Build;"
    string = bytes([len(descriptor)]) + descriptor + b"\0"
    map_offset = 152 + len(string)
    data = bytearray(map_offset + 16)
    data[:8] = b"dex\n038\0"
    struct.pack_into("<III", data, 32, len(data), 112, 0x12345678)
    struct.pack_into("<I", data, 52, map_offset)
    struct.pack_into("<II", data, 56, 1, 112)
    struct.pack_into("<II", data, 64, 1, 116)
    struct.pack_into("<II", data, 96, 1, 120)
    struct.pack_into("<I", data, 112, 152)
    data[152:map_offset] = string
    struct.pack_into("<IHHII", data, map_offset, 1, 7, 0, callsites, 0)
    return bytes(data)


def archive(files: dict[str, bytes]) -> bytes:
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as output:
        for name, data in files.items():
            output.writestr(name, data)
    return stream.getvalue()


class RuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.overlay = self.root / "overlay"
        self.runtime = self.root / "runtime"
        self.overlay.mkdir()
        self.manifest = {
            "format": 1, "architecture": "aarch64", "page_size": 16384,
            "source_commit": art.SOURCE_COMMIT, "source_sha512": art.SOURCE_SHA512,
            "source_sha256": art.SOURCE_SHA256,
            "patch_sha256": hashlib.sha256(art.PATCH.read_bytes()).hexdigest(),
            "build_flags": ["-DART_PAGE_SIZE=16384"], "files": [],
        }
        self.payload(art.LIBART, elf())
        for name in sorted(art.ART_ELFS - {art.LIBART}):
            self.payload(name, elf())

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def payload(self, name: str, contents: bytes, mode: int = 0o755) -> Path:
        path = self.overlay / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        path.chmod(mode)
        record = {"path": name, "size": len(contents), "sha256": hashlib.sha256(contents).hexdigest()}
        self.manifest["files"] = [item for item in self.manifest["files"] if item["path"] != name]
        self.manifest["files"].append(record)
        self.write_manifest()
        return path

    def write_manifest(self) -> None:
        (self.overlay / art.MANIFEST).write_text(json.dumps(self.manifest))

    def reject(self) -> None:
        self.write_manifest()
        with self.assertRaises((RuntimeError, FileNotFoundError)):
            art.read_manifest(self.overlay)

    def test_verified_native_payload_and_jar_install_without_mutating_old_alias(self) -> None:
        self.payload("usr/lib/java/dex/art/core-oj-hostdex.jar", b"PK\x03\x04test-dex", 0o644)
        target = self.runtime / art.LIBART
        target.parent.mkdir(parents=True)
        target.write_bytes(b"original 4 KiB ART")
        alias = self.runtime / "unchanged-art-alias.so"
        os.link(target, alias)
        verified = art.read_manifest(self.overlay)
        self.assertEqual(art.apply(self.overlay, self.runtime, verified), verified)
        self.assertEqual(target.read_bytes(), elf())
        self.assertEqual(alias.read_bytes(), b"original 4 KiB ART")
        self.assertNotEqual(target.stat().st_ino, alias.stat().st_ino)
        jar = self.runtime / "usr/lib/java/dex/art/core-oj-hostdex.jar"
        self.assertEqual(jar.read_bytes(), b"PK\x03\x04test-dex")
        self.assertEqual(jar.stat().st_mode & 0o777, 0o644)
        self.assertEqual(list(self.runtime.rglob(".vinix-art-*")), [])

    def test_rejects_legacy_page_size_architecture_source_or_patch(self) -> None:
        for key, value in (("page_size", 4096), ("architecture", "x86_64"),
                           ("source_commit", "b" * 40), ("source_sha512", "b" * 128),
                           ("source_sha256", "b" * 64),
                           ("patch_sha256", "b" * 64), ("build_flags", [])):
            with self.subTest(key=key):
                previous = self.manifest[key]
                self.manifest[key] = value
                self.reject()
                self.manifest[key] = previous

    def test_rejects_hash_and_size_mismatch(self) -> None:
        original = self.manifest["files"][0].copy()
        for key, value in (("sha256", "b" * 64), ("size", original["size"] + 1), ("size", True)):
            with self.subTest(key=key):
                self.manifest["files"][0] = {**original, key: value}
                self.reject()

    def test_rejects_foreign_or_incongruent_elf_with_valid_file_hash(self) -> None:
        for contents in (elf(machine=62), elf(offset=4096), b"\x7fELF\x02\x01\x01", b"not an ELF"):
            with self.subTest(contents=contents[:16]):
                self.payload(art.LIBART, contents)
                self.reject()

    def test_requires_every_native_output_before_replacing_existing_runtime(self) -> None:
        original = self.manifest["files"].copy()
        old = self.runtime / art.LIBART
        old.parent.mkdir(parents=True)
        old.write_bytes(b"existing 4 KiB package runtime")
        for name in sorted(art.ART_ELFS):
            with self.subTest(name=name):
                # The physical overlay file remains present. Its omitted
                # manifest record must not permit a partial replacement.
                self.manifest["files"] = [record for record in original if record["path"] != name]
                self.write_manifest()
                with self.assertRaisesRegex(RuntimeError, "missing required native outputs"):
                    art.apply(self.overlay, self.runtime, self.manifest)
                self.assertEqual(old.read_bytes(), b"existing 4 KiB package runtime")
        self.manifest["files"] = original
        self.write_manifest()
        self.assertEqual(art.read_manifest(self.overlay), self.manifest)

    def test_requires_native_elf_for_runtime_tools_and_support_libraries(self) -> None:
        for name in ("usr/bin/dalvikvm", "usr/lib/art/libartbase.so",
                     "usr/lib/java/dex/art/natives/libjavacore.so"):
            for contents in (b"not an ELF", elf(machine=62), elf(offset=4096)):
                with self.subTest(name=name, contents=contents[:16]):
                    self.payload(name, contents)
                    self.reject()
                    self.payload(name, elf())

    def test_rejects_outputs_outside_the_native_builder_and_optional_boot_jars(self) -> None:
        self.payload("usr/lib/art/unverified-extra.so", elf())
        with self.assertRaisesRegex(RuntimeError, "unexpected outputs"):
            art.read_manifest(self.overlay)

    def test_requires_libart_and_unique_relative_usr_paths(self) -> None:
        original = self.manifest["files"][0].copy()
        for name in ("../usr/lib/art/libart.so", "/usr/lib/art/libart.so", "usr/../lib.so",
                     "usr//lib/art/libart.so", "usr/./lib/art/libart.so", "opt/libart.so"):
            with self.subTest(name=name):
                self.manifest["files"] = [{**original, "path": name}]
                self.reject()
        self.manifest["files"] = [original, original.copy()]
        self.reject()
        self.manifest["files"] = []
        self.reject()
        self.payload("usr/lib/art/libartbase.so", elf())
        self.reject()

    def test_rejects_overlay_symlink_file_or_parent(self) -> None:
        path = self.overlay / art.LIBART
        path.unlink()
        outside = self.root / "outside.so"
        outside.write_bytes(elf())
        path.symlink_to(outside)
        self.reject()
        path.unlink()
        parent = path.parent
        outside_directory = self.root / "outside"
        parent.rename(outside_directory)
        (outside_directory / "libart.so").write_bytes(elf())
        parent.symlink_to(outside_directory)
        self.reject()

    def test_rejects_manifest_or_source_changed_before_apply(self) -> None:
        verified = art.read_manifest(self.overlay)
        self.manifest["page_size"] = 4096
        self.write_manifest()
        with self.assertRaises(RuntimeError):
            art.apply(self.overlay, self.runtime, verified)
        self.assertFalse(self.runtime.exists())
        self.manifest["page_size"] = 16384
        self.write_manifest()
        (self.overlay / art.LIBART).write_bytes(b"changed")
        with self.assertRaises(RuntimeError):
            art.apply(self.overlay, self.runtime, verified)
        self.assertFalse(self.runtime.exists())

    def test_checks_all_destination_parents_before_any_replacement(self) -> None:
        self.payload("usr/bin/dalvikvm", elf())
        old = self.runtime / art.LIBART
        old.parent.mkdir(parents=True)
        old.write_bytes(b"untouched")
        outside = self.root / "outside"
        outside.mkdir()
        (self.runtime / "usr/bin").symlink_to(outside)
        with self.assertRaises(RuntimeError):
            art.apply(self.overlay, self.runtime, art.read_manifest(self.overlay))
        self.assertEqual(old.read_bytes(), b"untouched")
        self.assertEqual(list(outside.iterdir()), [])


class BionicTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.overlay = self.root / "overlay"
        self.runtime = self.root / "runtime"
        self.overlay.mkdir()
        self.manifest = {
            "format": 1, "architecture": "aarch64", "page_size": 16384,
            "source_commit": art.BIONIC_SOURCE_COMMIT,
            "source_sha512": art.BIONIC_SOURCE_SHA512,
            "source_sha256": art.BIONIC_SOURCE_SHA256,
            "patch_sha256": hashlib.sha256(art.BIONIC_PATCH.read_bytes()).hexdigest(),
            "build_flags": ["-DBIONIC_PAGE_SIZE=16384"], "files": [],
        }
        for name in sorted(art.BIONIC_LIBRARIES):
            self.payload(name, elf())

    def tearDown(self) -> None:
        self.temporary.cleanup()

    payload = RuntimeTests.payload

    def write_manifest(self) -> None:
        (self.overlay / art.BIONIC_MANIFEST).write_text(json.dumps(self.manifest))

    def reject(self) -> None:
        self.write_manifest()
        with self.assertRaises(RuntimeError):
            art.read_bionic_manifest(self.overlay)

    def test_replaces_every_soname_alias_without_overwriting_package_hardlinks(self) -> None:
        old = self.root / "old-library.so"
        old.write_bytes(b"old 4 KiB bionic loader")
        for name in art.BIONIC_LIBRARIES:
            target = self.runtime / name
            target.parent.mkdir(parents=True, exist_ok=True)
            os.link(old, target)
        verified = art.read_bionic_manifest(self.overlay)
        self.assertEqual(art.apply_bionic(self.overlay, self.runtime, verified), verified)
        for name in art.BIONIC_LIBRARIES:
            self.assertEqual((self.runtime / name).read_bytes(), elf())
            self.assertNotEqual((self.runtime / name).stat().st_ino, old.stat().st_ino)
        self.assertEqual(old.read_bytes(), b"old 4 KiB bionic loader")

    def test_rejects_legacy_or_other_source_patch_flags(self) -> None:
        for key, value in (("page_size", 4096), ("architecture", "x86_64"),
                           ("source_commit", art.SOURCE_COMMIT), ("source_sha256", "b" * 64),
                           ("source_sha512", "b" * 128), ("patch_sha256", "b" * 64),
                           ("build_flags", ["-DART_PAGE_SIZE=16384"])):
            with self.subTest(key=key):
                old = self.manifest[key]
                self.manifest[key] = value
                self.reject()
                self.manifest[key] = old

    def test_requires_all_aliases_and_rejects_unexpected_nonelf_payloads(self) -> None:
        original = self.manifest["files"].copy()
        self.manifest["files"] = original[:-1]
        self.reject()
        self.manifest["files"] = original
        self.payload("usr/lib/additional.so", elf())
        self.reject()
        self.manifest["files"] = original
        self.payload("usr/lib/libc_bio.so", b"PK\x03\x04not-an-ELF")
        self.reject()

    def test_rejects_foreign_incongruent_or_stale_alias_elf(self) -> None:
        for contents in (elf(machine=62), elf(offset=4096), elf() + b"stale alias"):
            with self.subTest(contents=contents[:16]):
                self.payload("usr/lib/libdl_bio.so.0", contents)
                self.reject()

    def test_rejects_checksum_changes_and_symlink_escape_before_installing(self) -> None:
        verified = art.read_bionic_manifest(self.overlay)
        path = self.overlay / "usr/lib/libc_bio.so"
        path.write_bytes(b"changed after verification")
        with self.assertRaises(RuntimeError):
            art.apply_bionic(self.overlay, self.runtime, verified)
        self.assertFalse(self.runtime.exists())
        path.unlink()
        outside = self.root / "outside.so"
        outside.write_bytes(elf())
        path.symlink_to(outside)
        self.reject()

    def test_rejects_duplicate_or_escaping_paths(self) -> None:
        original = self.manifest["files"].copy()
        self.manifest["files"] = original + [original[0].copy()]
        self.reject()
        for name in ("../usr/lib/libc_bio.so", "/usr/lib/libc_bio.so", "usr/../libc_bio.so"):
            self.manifest["files"] = [{**original[0], "path": name}, *original[1:]]
            self.reject()


class AtlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.overlay = self.root / "overlay"
        self.runtime = self.root / "runtime"
        self.overlay.mkdir()
        boot = art._boot_tools()
        support = ROOT / "build-support/android"
        self.manifest = {
            "format": 1, "architecture": "aarch64", "page_size": 16384,
            "source_commit": art.ATL_SOURCE_COMMIT, "source_sha256": art.ATL_SOURCE_SHA256,
            "source_sha512": art.ATL_SOURCE_SHA512,
            "build_flags": ["--buildtype=release", "-Wl,-z,max-page-size=65536"],
            "builder_sha256": art._digest(support / "build-atl.sh"),
            "dex_adapter_sha256": art._digest(support / "atl-dex.py"),
            "dex_compiler_sha256": boot.INPUTS[2]["sha256"],
            "java_core_classes_sha256": art.ATL_CORE_CLASSES_SHA256,
            "dex_compiler_arguments": boot.COMPILER_ARGUMENTS,
            "dex_compiler": "D8 8.3.37 (build official)", "files": [],
        }
        for name in art.ATL_ELFS:
            self.payload(name, elf())
        for name in art.ATL_JARS:
            self.payload(name, archive({"classes.dex": dex()}))
        self.payload(art.ATL_RESOURCES, archive({"AndroidManifest.xml": b"manifest", "resources.arsc": b"resources"}))
        self.payload(art.ATL_FONTS, b"<familyset><family><font>Roboto-Regular.ttf</font></family></familyset>")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def payload(self, name: str, contents: bytes, mode: int = 0o755) -> Path:
        path = RuntimeTests.payload(self, name, contents, mode)
        record = self.manifest["files"][-1]
        record["kind"] = "elf" if contents.startswith(b"\x7fELF") else "dex" if name.endswith(".jar") else "data"
        if name.endswith(".jar"):
            record.update(class_count=1, bootstrap_callsites=0)
        self.write_manifest()
        return path

    def write_manifest(self) -> None:
        (self.overlay / art.ATL_MANIFEST).write_text(json.dumps(self.manifest))

    def reject(self) -> None:
        self.write_manifest()
        with self.assertRaises(RuntimeError):
            art.read_atl_manifest(self.overlay)

    def test_installs_one_coherent_native_framework_without_mutating_old_alias(self) -> None:
        name = "usr/lib/libandroid.so.0"
        old = self.runtime / name
        old.parent.mkdir(parents=True)
        old.write_bytes(b"old framework")
        alias = self.root / "old-package-library.so"
        os.link(old, alias)
        verified = art.read_atl_manifest(self.overlay)
        self.assertEqual(art.apply_atl(self.overlay, self.runtime, verified), verified)
        self.assertEqual(alias.read_bytes(), b"old framework")
        for record in verified["files"]:
            self.assertEqual((self.runtime / record["path"]).read_bytes(), (self.overlay / record["path"]).read_bytes())

    def test_rejects_wrong_source_builder_compiler_flags_or_inputs(self) -> None:
        for key, value in (("page_size", 4096), ("architecture", "x86_64"),
                           ("source_commit", "b" * 40), ("source_sha256", "b" * 64),
                           ("source_sha512", "b" * 128), ("builder_sha256", "b" * 64),
                           ("dex_adapter_sha256", "b" * 64), ("dex_compiler_sha256", "b" * 64),
                           ("java_core_classes_sha256", "b" * 64), ("dex_compiler_arguments", []),
                           ("build_flags", []), ("dex_compiler", "D8 other")):
            with self.subTest(key=key):
                old = self.manifest[key]
                self.manifest[key] = value
                self.reject()
                self.manifest[key] = old

    def test_requires_every_framework_component(self) -> None:
        original = self.manifest["files"]
        for name in art.ATL_REQUIRED:
            with self.subTest(name=name):
                self.manifest["files"] = [record for record in original if record["path"] != name]
                self.reject()
        self.manifest["files"] = original

    def test_rejects_non_native_elf_or_mismatched_soname(self) -> None:
        for contents in (elf(machine=62), elf(offset=4096), b"not an ELF", elf() + b"stale alias"):
            with self.subTest(contents=contents[:16]):
                self.payload("usr/lib/libandroid.so", contents)
                self.reject()

    def test_rejects_checksum_consistent_jar_with_bootstrap_calls_or_false_class_receipt(self) -> None:
        name = art.ATL_DEX_DIRECTORY + "/api-impl.jar"
        self.payload(name, archive({"classes.dex": dex(callsites=1)}))
        self.reject()
        self.payload(name, archive({"classes.dex": dex()}))
        self.manifest["files"][-1]["class_count"] = 2
        self.reject()
        self.payload(name, b"not a JAR")
        self.reject()

    def test_rejects_incomplete_resource_apk_and_font_map(self) -> None:
        self.payload(art.ATL_RESOURCES, archive({"AndroidManifest.xml": b"manifest"}))
        self.reject()
        self.payload(art.ATL_RESOURCES, archive({"AndroidManifest.xml": b"manifest", "resources.arsc": b"resources"}))
        for contents in (b"<bad>", b"<familyset/>", b"<wrong><family/></wrong>"):
            self.payload(art.ATL_FONTS, contents)
            self.reject()

    def stage_android(self) -> tuple[Path, int]:
        specification = importlib.util.spec_from_file_location(
            "android_builder", ROOT / "build-support/android/build.py")
        builder = importlib.util.module_from_spec(specification)
        assert specification.loader is not None
        specification.loader.exec_module(builder)
        args = Namespace(build_dir=self.root / "build", art_runtime=self.root / "art",
                         bionic_runtime=self.root / "bionic", atl_runtime=self.overlay,
                         with_calculator=False)
        for directory in (args.build_dir, args.art_runtime, args.bionic_runtime):
            directory.mkdir(exist_ok=True)
        art_manifest = {"bootclasspath": {"verified": True}}
        bionic_manifest = {"verified": True}

        def install_art(source: Path, runtime: Path, manifest: dict) -> None:
            for name in ("lib/ld-musl-aarch64.so.1", art.LIBART):
                path = runtime / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(elf())

        def run(command: list[str], **options) -> None:
            if "-o" in command:
                Path(command[command.index("-o") + 1]).write_bytes(elf())

        # ART and bionic payload verification have their own tests above. This
        # stages the real ATL fixture while isolating unrelated build tools.
        tools = SimpleNamespace(
            MANIFEST=art.MANIFEST, BIONIC_MANIFEST=art.BIONIC_MANIFEST, ATL_MANIFEST=art.ATL_MANIFEST,
            read_manifest=lambda root: art_manifest,
            read_bionic_manifest=lambda root: bionic_manifest,
            read_atl_manifest=art.read_atl_manifest,
            apply=install_art, apply_bionic=lambda *arguments: None, apply_atl=art.apply_atl,
        )
        lock = {"architecture": "aarch64", "mirror": "https://example.invalid", "packages": []}
        with (patch.object(builder, "art_tools", return_value=tools),
              patch.object(builder.shutil, "which", return_value="isolated-test-compiler"),
              patch.object(builder.subprocess, "run", side_effect=run) as commands):
            staging = builder.stage(args, lock, args.build_dir / "downloads")
        return staging / builder.PREFIX.lstrip("/"), commands.call_count

    def test_builder_stages_coherent_atl_and_rejects_stale_cached_framework(self) -> None:
        runtime, calls = self.stage_android()
        self.assertGreater(calls, 0)
        for record in self.manifest["files"]:
            self.assertEqual((runtime / record["path"]).read_bytes(), (self.overlay / record["path"]).read_bytes())
        receipt = json.loads((runtime / "runtime-manifest.json").read_text())
        self.assertEqual(receipt["atl"], art.read_atl_manifest(self.overlay))
        self.assertEqual(self.stage_android()[1], 0)
        (runtime / art.ATL_DEX_DIRECTORY / "api-impl.jar").write_bytes(b"stale framework")
        self.assertGreater(self.stage_android()[1], 0)
        self.assertEqual(art.read_atl_manifest(runtime), art.read_atl_manifest(self.overlay))
        self.payload(art.ATL_FONTS, b"<familyset><family><font>NewFont.ttf</font></family></familyset>")
        self.assertGreater(self.stage_android()[1], 0)
        receipt = json.loads((runtime / "runtime-manifest.json").read_text())
        self.assertEqual(receipt["atl"], art.read_atl_manifest(self.overlay))
        self.assertEqual((runtime / art.ATL_FONTS).read_bytes(), (self.overlay / art.ATL_FONTS).read_bytes())

    def test_invalid_atl_input_does_not_replace_existing_staging(self) -> None:
        runtime, _ = self.stage_android()
        sentinel = runtime / "existing-staging"
        sentinel.write_text("retain on invalid source")
        (self.overlay / art.ATL_DEX_DIRECTORY / "api-impl.jar").write_bytes(b"invalid source")
        with self.assertRaises(RuntimeError):
            self.stage_android()
        self.assertEqual(sentinel.read_text(), "retain on invalid source")
        self.assertEqual(art.read_atl_manifest(runtime), self.manifest)


if __name__ == "__main__":
    unittest.main()
