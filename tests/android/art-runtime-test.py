#!/usr/bin/env python3
"""Checks for native ART payload provenance, ELF ABI, and safe replacement."""
from __future__ import annotations

import atexit
import hashlib
import importlib.util
import json
import os
import io
from pathlib import Path
import shutil
import struct
import subprocess
import sys
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


class BionicTests(unittest.TestCase):
    pass


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
            "patch_sha256": art._digest(art.ATL_PATCH),
            "androidfw_patch_sha256": art._digest(art.PATCH),
            "androidfw_configuration_api": 1,
            "androidfw_header_sha256": "a" * 64,
            "androidfw_library_sha256": "c" * 64,
            "configuration_probe_sha256": art.configuration_probe_digest(),
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

    def test_androidfw_pair_requires_exact_header_library_patch_and_api(self) -> None:
        dependency = {"androidfw_configuration_api": 1, "patch_sha256": art._digest(art.PATCH),
                      "files": [{"path": art.ANDROIDFW_HEADER, "sha256": "a" * 64},
                                {"path": art.ANDROIDFW_LIBRARY, "sha256": "c" * 64}]}
        art.validate_atl_art_pair(dependency, self.manifest)
        for key in ("androidfw_configuration_api", "patch_sha256"):
            changed = {**dependency, key: "changed"}
            with self.assertRaises(RuntimeError):
                art.validate_atl_art_pair(changed, self.manifest)
        for index in range(2):
            changed = {**dependency, "files": [record.copy() for record in dependency["files"]]}
            changed["files"][index]["sha256"] = "b" * 64
            with self.assertRaises(RuntimeError):
                art.validate_atl_art_pair(changed, self.manifest)

    def test_rejects_wrong_source_builder_compiler_flags_or_inputs(self) -> None:
        for key, value in (("page_size", 4096), ("architecture", "x86_64"),
                           ("source_commit", "b" * 40), ("source_sha256", "b" * 64),
                           ("source_sha512", "b" * 128), ("builder_sha256", "b" * 64),
                           ("patch_sha256", "b" * 64), ("androidfw_patch_sha256", "b" * 64),
                           ("androidfw_configuration_api", 0),
                           ("androidfw_header_sha256", "invalid"), ("androidfw_library_sha256", "invalid"),
                           ("configuration_probe_sha256", "b" * 64),
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
            if command[0] == "sh":
                return builder.subprocess.CompletedProcess(command, 0, stdout="fixture V compiler\n")
            if len(command) > 2 and command[1].endswith("/compile-v-runtime.py"):
                Path(command[2]).write_bytes(elf())
            if "-o" in command:
                Path(command[command.index("-o") + 1]).write_bytes(elf())

        # ART and bionic payload verification have their own tests above. This
        # stages the real ATL fixture while isolating unrelated build tools.
        tools = SimpleNamespace(
            MANIFEST=art.MANIFEST, BIONIC_MANIFEST=art.BIONIC_MANIFEST, ATL_MANIFEST=art.ATL_MANIFEST,
            read_manifest=lambda root: art_manifest,
            read_bionic_manifest=lambda root: bionic_manifest,
            read_atl_manifest=lambda root: art._read_manifest(root, atl=True),
            validate_atl_art_pair=lambda *arguments: None,
            apply=install_art, apply_bionic=lambda *arguments: None, apply_atl=art.apply_atl,
        )
        lock = {"architecture": "aarch64", "mirror": "https://example.invalid", "packages": []}
        with (patch.object(builder, "art_tools", return_value=tools),
              patch.object(builder, "musl_tools", return_value=SimpleNamespace(
                  read_manifest=lambda root: {"verified": True})),
              patch.object(builder.shutil, "which", return_value="isolated-test-compiler"),
              patch.object(builder.subprocess, "run", side_effect=run) as commands):
            staging = builder.stage(args, lock, args.build_dir / "downloads")
        build_calls = sum(call.args[0][0] != "sh" for call in commands.call_args_list)
        return staging / builder.PREFIX.lstrip("/"), build_calls

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
        self.assertEqual(art._read_manifest(runtime, atl=True), art.read_atl_manifest(self.overlay))
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
        self.assertEqual(art._read_manifest(runtime, atl=True), self.manifest)


_NATIVE_FIXTURE = None
_NATIVE_ENVIRONMENT = None


def _native_fixture(self):
    global _NATIVE_FIXTURE, _NATIVE_ENVIRONMENT
    if _NATIVE_FIXTURE is None:
        directory = Path(tempfile.mkdtemp(prefix="vinix-runtime-fixture-controller-"))
        try:
            binary = os.environ.get("VINIX_RUNTIME_FIXTURE_BINARY")
            if not binary:
                binary = str(directory / "fixture")
                subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                str(ROOT / "tests/android/art-runtime-test.v"),
                                "--install-fixture", binary], check=True)
            (directory / "cases").mkdir()
            environment = dict(os.environ, VINIX_RUNTIME_FIXTURE_WORK=str(directory / "cases"),
                               VINIX_RUNTIME_FIXTURE_PYTHON=sys.executable,
                               VINIX_ANDROID_HOST_QUERY=str(art._native._binary()))
        except BaseException:
            shutil.rmtree(directory)
            raise
        atexit.register(shutil.rmtree, directory)
        _NATIVE_FIXTURE, _NATIVE_ENVIRONMENT = binary, environment
    subprocess.run([_NATIVE_FIXTURE, ".".join(self.id().split(".")[-2:])],
                   check=True, env=_NATIVE_ENVIRONMENT)


for _class, _names in json.loads((ROOT / "tests/android/runtimefixture/cases.json").read_text())["groups"].items():
    for _name in _names:
        setattr(globals()[_class], _name, _native_fixture)


if __name__ == "__main__":
    unittest.main()
