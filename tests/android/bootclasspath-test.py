#!/usr/bin/env python3
"""Verify boot DEX reconstruction and preservation of library resources."""
from __future__ import annotations

import hashlib
import importlib.util
import copy
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bootclasspath", ROOT / "build-support/android/art-bootclasspath.py")
boot = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(boot)


def dex(descriptor: str = "Ljava/time/Example;", callsites: int = 0) -> bytes:
    string = bytes([len(descriptor)]) + descriptor.encode() + b"\0"
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


def many_classes(count: int, callsites: int = 0) -> bytes:
    string_offset, type_offset = 112, 112 + count * 4
    class_offset = type_offset + count * 4
    data = bytearray(class_offset + count * 32)
    for index in range(count):
        descriptor = f"Ljava/time/Test{index};"
        struct.pack_into("<I", data, string_offset + index * 4, len(data))
        struct.pack_into("<I", data, type_offset + index * 4, index)
        struct.pack_into("<I", data, class_offset + index * 32, index)
        data.extend(bytes([len(descriptor)]) + descriptor.encode() + b"\0")
    data.extend(bytes((-len(data)) % 4))
    map_offset = len(data)
    data.extend(struct.pack("<IHHII", 1, 7, 0, callsites, 0))
    data[:8] = b"dex\n038\0"
    struct.pack_into("<III", data, 32, len(data), 112, 0x12345678)
    struct.pack_into("<I", data, 52, map_offset)
    struct.pack_into("<II", data, 56, count, string_offset)
    struct.pack_into("<II", data, 64, count, type_offset)
    struct.pack_into("<II", data, 96, count, class_offset)
    return bytes(data)


class BootclasspathTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_reads_real_dex_class_descriptor_and_bootstrap_count(self) -> None:
        self.assertEqual(boot.dex_info(dex(callsites=3)), ({"java/time/Example.class"}, 3))
        self.assertEqual(boot.dex_info(dex()), ({"java/time/Example.class"}, 0))

    def test_rejects_invalid_or_escaping_dex_data(self) -> None:
        for data in (dex()[:100], dex()[:-1], dex("L../Escape;"), dex("L/Absolute;")):
            with self.subTest(data=data[:8]):
                with self.assertRaises(RuntimeError):
                    boot.dex_info(data)
        data = bytearray(dex())
        struct.pack_into("<I", data, 120, 8)
        with self.assertRaises(RuntimeError):
            boot.dex_info(bytes(data))

    def test_reconstructs_only_required_classfiles_and_rejects_missing_input(self) -> None:
        source = self.root / "all.jar"
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr("java/time/Example.class", b"class-bytecode")
            archive.writestr("java/time/Other.class", b"other-bytecode")
        result = self.root / "subset.jar"
        boot.class_subset(source, {"java/time/Example.class"}, result)
        with zipfile.ZipFile(result) as archive:
            self.assertEqual(archive.namelist(), ["java/time/Example.class"])
            self.assertEqual(archive.read("java/time/Example.class"), b"class-bytecode")
        with self.assertRaises(RuntimeError):
            boot.class_subset(source, {"java/time/Missing.class"}, result)

    def test_jar_replacement_preserves_resources_and_is_deterministic(self) -> None:
        original = self.root / "original.jar"
        with zipfile.ZipFile(original, "w") as archive:
            archive.writestr("classes.dex", dex(callsites=3))
            archive.writestr("classes2.dex", dex("Ljava/time/Old;"))
            archive.writestr("android/icu/icu-data.dat", b"unchanged ICU binary data")
            archive.writestr("META-INF/LICENSE", b"license")
        original_bytes = original.read_bytes()
        output = self.root / "dex"
        output.mkdir()
        (output / "classes.dex").write_bytes(dex())
        (output / "classes2.dex").write_bytes(dex("Ljava/time/GeneratedLambda;"))
        first, second = self.root / "one.jar", self.root / "two.jar"
        boot.package_jar(original, output, first)
        boot.package_jar(original, output, second)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        self.assertEqual(original.read_bytes(), original_bytes)
        with zipfile.ZipFile(first) as archive:
            self.assertEqual(archive.read("android/icu/icu-data.dat"), b"unchanged ICU binary data")
            self.assertEqual(archive.read("META-INF/LICENSE"), b"license")
        self.assertEqual(boot.jar_info(first),
                         ({"java/time/Example.class", "java/time/GeneratedLambda.class"}, 0))

    def test_rejects_duplicate_classes_across_multidex(self) -> None:
        path = self.root / "bad.jar"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("classes.dex", dex())
            archive.writestr("classes2.dex", dex())
        with self.assertRaises(RuntimeError):
            boot.jar_info(path)

    def test_rejects_corrupted_pinned_download_without_network(self) -> None:
        path = self.root / "cached.jar"
        path.write_bytes(b"verified tool")
        record = {"filename": path.name, "url": "https://example.invalid/tool.jar",
                  "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        with patch.object(boot.subprocess, "run") as run:
            self.assertEqual(boot.download(record, self.root), path)
            path.write_bytes(b"corrupted tool")
            with self.assertRaises(RuntimeError):
                boot.download(record, self.root)
            run.assert_not_called()

    def provenance(self) -> dict:
        records = []
        for name, original in boot.BOOT_ORIGINAL.items():
            path = self.root / boot.BOOT_DIRECTORY / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("classes.dex", many_classes(original["classes_before"] + 1))
            records.append({"path": str(path.relative_to(self.root)), **original,
                            "sha256": boot.digest(path), "size": path.stat().st_size,
                            "classes_after": original["classes_before"] + 1,
                            "bootstrap_callsites_after": 0})
        return {"format": 1, "inputs": list(boot.INPUTS), "compiler_arguments": boot.COMPILER_ARGUMENTS,
                "compiler": "D8 8.3.37 (build official)", "input_key": "a" * 64, "files": records}

    def test_validates_real_dex_counts_and_pinned_compiler_receipt(self) -> None:
        manifest = self.provenance()
        payloads = [{key: record[key] for key in ("path", "size", "sha256")}
                    for record in manifest["files"]]
        boot.validate_provenance(self.root, manifest, payloads)
        for key, value in (("inputs", []), ("compiler_arguments", ["--min-api", "35"]),
                           ("compiler", "D8 8.0.0 (build other)"), ("input_key", "bad"), ("files", [])):
            with self.subTest(key=key):
                bad = {**manifest, key: value}
                with self.assertRaises(RuntimeError):
                    boot.validate_provenance(self.root, bad, payloads)
        payloads[0]["sha256"] = "b" * 64
        with self.assertRaises(RuntimeError):
            boot.validate_provenance(self.root, manifest, payloads)

    def test_rejects_library_receipt_that_lies_about_original_or_output_dex(self) -> None:
        manifest = self.provenance()
        for key, value in (("original_sha256", "b" * 64), ("classes_before", 1),
                           ("classes_after", 99999), ("bootstrap_callsites_after", 0.0),
                           ("bootstrap_callsites_before", 0), ("sha256", "b" * 64),
                           ("path", "usr/lib/java/dex/art/../escape.jar"), ("path", [])):
            with self.subTest(key=key):
                bad = copy.deepcopy(manifest)
                bad["files"][0][key] = value
                with self.assertRaises(RuntimeError):
                    boot.validate_provenance(self.root, bad)
        bad = copy.deepcopy(manifest)
        bad["files"][1] = bad["files"][0].copy()
        with self.assertRaises(RuntimeError):
            boot.validate_provenance(self.root, bad)

    def test_rejects_checksum_consistent_dex_with_bootstrap_calls(self) -> None:
        manifest = self.provenance()
        record = manifest["files"][0]
        path = self.root / record["path"]
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("classes.dex", many_classes(record["classes_after"], callsites=1))
        record.update(sha256=boot.digest(path), size=path.stat().st_size)
        with self.assertRaises(RuntimeError):
            boot.validate_provenance(self.root, manifest)


if __name__ == "__main__":
    unittest.main()
