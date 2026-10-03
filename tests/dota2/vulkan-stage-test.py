#!/usr/bin/env python3
"""Offline regressions for the private Dota libc family and staging cache."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("dota2_vulkan_stage", REPO / "build-support/dota2/vulkan-stage.py")
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


def deb_bytes(files, links=None):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w:gz") as archive:
        for name, contents in files.items():
            member = tarfile.TarInfo("./" + name)
            member.size, member.mode = len(contents), 0o755
            archive.addfile(member, io.BytesIO(contents))
        for name, target in (links or {}).items():
            member = tarfile.TarInfo("./" + name)
            member.type, member.linkname, member.mode = tarfile.SYMTYPE, target, 0o777
            archive.addfile(member)
    payload = data.getvalue()
    header = (f"{'data.tar.gz/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(payload):<10}`\n").encode()
    return b"!<arch>\n" + header + payload + (b"\n" if len(payload) & 1 else b"")


class StageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.steam = self.base / "steam"
        self.source = self.steam / "staging/usr/libexec/vinix-steam/root"
        self.source.mkdir(parents=True)
        self.build = self.base / "build"
        self.cache = self.build / "downloads"
        self.cache.mkdir(parents=True)
        self.root = self.build / "staging/usr/libexec/vinix-dota2/root"
        self.write(self.source / "lib64/ld-linux-x86-64.so.2", b"old loader")
        for name in stage.GLIBC_LIBRARIES[1:]:
            self.write(self.source / "lib/x86_64-linux-gnu" / name, b"old " + name.encode())
        self.write(self.source / "usr/lib/x86_64-linux-gnu/libLLVM-15.so.1", b"keep LLVM")
        self.write(self.source / "usr/lib/x86_64-linux-gnu/libfreetype.so.6", b"keep FreeType")
        self.write(self.source / "usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so", b"keep robust shim")
        self.pin = stage.load_glibc_pin()
        family = {"usr/lib/x86_64-linux-gnu/" + name: b"new " + name.encode()
                  for name in stage.GLIBC_LIBRARIES}
        family["usr/lib/x86_64-linux-gnu/gconv/test.so"] = b"new gconv"
        family["usr/share/doc/libc6/copyright"] = b"package copyright"
        contents = deb_bytes(family, {"usr/lib64/ld-linux-x86-64.so.2":
                                      "../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"})
        self.pin = {**self.pin, "sha256": hashlib.sha256(contents).hexdigest(), "size": len(contents)}
        (self.cache / Path(self.pin["filename"]).name).write_bytes(contents)
        packages = {
            "libvulkan1": {"usr/lib/x86_64-linux-gnu/libvulkan.so.1": b"old Vulkan loader"},
            "mesa-vulkan-drivers": {"usr/lib/x86_64-linux-gnu/libvulkan_lvp.so": b"keep Mesa",
                "usr/share/vulkan/icd.d/lvp_icd.x86_64.json": b'{"ICD":{"library_path":"old"}}'},
            "vulkan-tools": {"usr/bin/vulkaninfo": b"vulkaninfo", "usr/bin/vkcube": b"vkcube"},
            "libpipewire-0.3-0": {}, "libopenal1": {}, "libnm0": {},
            "ca-certificates": {"usr/share/ca-certificates/mozilla/public.crt": b"PUBLIC CERTIFICATE\n"},
        }
        self.mesa_version = stage.lavapipe_inputs()["debian_version"]
        records = []
        for name, files in packages.items():
            filename = name + "_1_amd64.deb"
            data = deb_bytes(files)
            (self.cache / filename).write_bytes(data)
            version = self.mesa_version if name == "mesa-vulkan-drivers" else "1"
            records.append(f"Package: {name}\nVersion: {version}\nArchitecture: amd64\n"
                           f"Filename: pool/{filename}\nSize: {len(data)}\n"
                           f"SHA256: {hashlib.sha256(data).hexdigest()}\n")
        self.write(self.steam / "downloads/bookworm_amd64_Packages", "\n".join(records).encode())
        self.write(self.steam / "amd64-packages", b"libc6\told\tamd64\told.deb\n")
        self.write(self.steam / "i386-packages", b"libc6\told\ti386\told.deb\n")
        self.before = stage.package_files(self.source)

    @staticmethod
    def write(path, contents):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)

    def run_stage(self, extra=()):
        def compile_library(command, **kwargs):
            self.assertEqual(command[0], "clang", "cached fixture must never fetch the network")
            self.write(Path(command[command.index("-o") + 1]), b"compiled private shim")
        self.lavapipe_bases = []
        def build_lavapipe(base, work):
            # The real build links Bookworm's libc; record what it would see.
            self.lavapipe_bases.append((base / "lib/x86_64-linux-gnu/libc.so.6").read_bytes())
            self.assertEqual(work, (self.build / "mesa").resolve())
            library = self.base / "lavapipe/libvulkan_lvp.so"
            self.write(library, b"patched Lavapipe")
            return library
        arguments = [str(stage.__file__), "--steam-build", str(self.steam), "--build", str(self.build), *extra]
        with patch.object(sys, "argv", arguments), patch.object(stage, "load_glibc_pin", return_value=self.pin), \
                patch.object(stage.subprocess, "run", side_effect=compile_library), \
                patch.object(stage, "build_lavapipe", side_effect=build_lavapipe), \
                patch.object(stage.sys, "platform", "linux"), redirect_stdout(io.StringIO()):
            stage.main()
        self.assertEqual(stage.package_files(self.source), self.before)

    def test_full_package_and_legacy_paths_share_one_libc_family(self):
        self.run_stage()
        self.assertTrue(stage.glibc_package_valid(self.root, self.pin))
        for name in stage.GLIBC_LIBRARIES:
            canonical = self.root / "usr/lib/x86_64-linux-gnu" / name
            self.assertEqual(canonical.read_bytes(), b"new " + name.encode())
            legacy = self.root / ("lib64/" + name if name.startswith("ld-linux") else "lib/x86_64-linux-gnu/" + name)
            self.assertTrue(legacy.is_symlink())
            self.assertEqual(legacy.resolve(), canonical.resolve())
        self.assertEqual((self.root / "usr/lib/x86_64-linux-gnu/libLLVM-15.so.1").read_bytes(), b"keep LLVM")
        self.assertEqual((self.root / "usr/lib/x86_64-linux-gnu/libvulkan_lvp.so").read_bytes(), b"patched Lavapipe")
        self.assertEqual((self.root / "usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so").read_bytes(), b"keep robust shim")
        self.assertEqual((self.root / "usr/share/doc/libc6/copyright").read_bytes(), b"package copyright")

    def test_cached_mixed_loader_is_rebuilt_and_restores_alias(self):
        self.run_stage()
        with patch.object(stage, "clone_tree", wraps=stage.clone_tree) as clone:
            self.run_stage()
            clone.assert_not_called()
        loader = self.root / "lib64/ld-linux-x86-64.so.2"
        loader.unlink()
        loader.write_bytes(b"old loader copied back")
        self.assertFalse(stage.glibc_package_valid(self.root, self.pin))
        with patch.object(stage, "clone_tree", wraps=stage.clone_tree) as clone:
            self.run_stage()
            clone.assert_called_once()
        self.assertTrue(stage.glibc_package_valid(self.root, self.pin))

    def test_changed_libm_and_gconv_invalidate_cached_full_package(self):
        for name in ("usr/lib/x86_64-linux-gnu/libm.so.6", "usr/lib/x86_64-linux-gnu/gconv/test.so"):
            self.run_stage()
            (self.root / name).write_bytes(b"wrong package version")
            self.assertFalse(stage.glibc_package_valid(self.root, self.pin))
        self.run_stage()
        self.assertTrue(stage.glibc_package_valid(self.root, self.pin))

    def test_wrong_legacy_libc_and_missing_marker_are_not_cache_hits(self):
        self.run_stage()
        libc = self.root / "lib/x86_64-linux-gnu/libc.so.6"
        libc.unlink()
        libc.write_bytes(b"old libc")
        self.assertFalse(stage.glibc_package_valid(self.root, self.pin))
        self.run_stage()
        (self.root / stage.GLIBC_MARKER).unlink()
        self.assertFalse(stage.glibc_package_valid(self.root, self.pin))

    def test_generation_tracks_alias_policy_package_pin_and_builder(self):
        self.run_stage()
        stamp = self.root / ".vinix-dota2-vulkan-generation"
        old = stamp.read_text()
        with patch.object(stage, "GLIBC_ALIAS_POLICY", "next-reviewed-policy"):
            self.run_stage()
            self.assertNotEqual(stamp.read_text(), old)
        self.run_stage()
        self.assertEqual(stamp.read_text(), old)
        self.pin = {**self.pin, "version": "2.41-next-reviewed-pin"}
        self.run_stage()
        self.assertNotEqual(stamp.read_text(), old)
        old = stamp.read_text()
        self.assertEqual(json.loads((self.root / stage.GLIBC_MARKER).read_text())["package"], self.pin)
        original_digest = stage.file_sha256
        def changed_builder(path):
            return "a" * 64 if path == Path(stage.__file__) else original_digest(path)
        with patch.object(stage, "file_sha256", side_effect=changed_builder):
            self.run_stage()
            self.assertNotEqual(stamp.read_text(), old)

    def test_baseline_option_keeps_the_steam_libc_without_overlay(self):
        self.run_stage(["--keep-steam-libc"])
        self.assertEqual((self.root / "lib64/ld-linux-x86-64.so.2").read_bytes(), b"old loader")
        self.assertEqual((self.root / "lib/x86_64-linux-gnu/libc.so.6").read_bytes(), b"old libc.so.6")
        self.assertFalse((self.root / stage.GLIBC_MARKER).exists())

    def test_patched_lavapipe_links_bookworm_libc_and_replaces_only_its_driver(self):
        self.run_stage()
        self.assertEqual(self.lavapipe_bases, [b"old libc.so.6"])
        self.assertTrue(stage.lavapipe_valid(self.root, stage.lavapipe_inputs()))
        icd = json.loads((self.root / "usr/share/vulkan/icd.d/lvp_icd.x86_64.json").read_text())
        self.assertEqual(icd["ICD"]["library_path"],
                         "/usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so")
        self.assertEqual((self.root / "usr/lib/x86_64-linux-gnu/libvulkan.so.1").read_bytes(), b"old Vulkan loader")

    def test_replaced_lavapipe_is_not_a_cache_hit(self):
        self.run_stage()
        self.run_stage()
        self.assertEqual(self.lavapipe_bases, [])
        (self.root / stage.LAVAPIPE_LIBRARY).write_bytes(b"keep Mesa")
        self.assertFalse(stage.lavapipe_valid(self.root, stage.lavapipe_inputs()))
        self.run_stage()
        self.assertEqual((self.root / stage.LAVAPIPE_LIBRARY).read_bytes(), b"patched Lavapipe")

    def test_baseline_option_keeps_debian_lavapipe(self):
        self.run_stage(["--debian-lavapipe"])
        self.assertEqual(self.lavapipe_bases, [])
        self.assertEqual((self.root / stage.LAVAPIPE_LIBRARY).read_bytes(), b"keep Mesa")
        self.assertFalse((self.root / stage.LAVAPIPE_MARKER).exists())
        stamp = (self.root / ".vinix-dota2-vulkan-generation").read_text()
        self.run_stage()
        self.assertNotEqual((self.root / ".vinix-dota2-vulkan-generation").read_text(), stamp)
        self.assertEqual((self.root / stage.LAVAPIPE_LIBRARY).read_bytes(), b"patched Lavapipe")

    def test_other_debian_mesa_version_is_rejected(self):
        with patch.object(stage, "lavapipe_inputs",
                          return_value={**stage.lavapipe_inputs(), "debian_version": "22.3.6-1+deb12u3"}), \
                self.assertRaisesRegex(SystemExit, "pinned to 22.3.6-1\\+deb12u3"):
            self.run_stage()
        self.assertFalse(self.root.exists())

    def test_corrupt_cached_package_fails_before_cloning_payload_into_root(self):
        spec = importlib.util.spec_from_file_location("test_debian_root", REPO / "build-support/debian-root.py")
        resolver = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = resolver
        spec.loader.exec_module(resolver)
        archive = self.cache / Path(self.pin["filename"]).name
        archive.write_bytes(b"bad cached archive")
        with patch.object(resolver, "download", return_value=archive), self.assertRaisesRegex(SystemExit, "checksum or size mismatch"):
            stage.stage_glibc_package(resolver, self.pin, self.cache, self.source)
        self.assertEqual(stage.package_files(self.source), self.before)

    def test_pin_rejects_wrong_architecture(self):
        pin = self.base / "wrong-pin.json"
        pin.write_text(json.dumps({**self.pin, "architecture": "i386"}))
        with self.assertRaisesRegex(SystemExit, "pinned amd64 libc6"):
            stage.load_glibc_pin(pin)

    def test_partial_libc_family_fails_before_changing_the_source(self):
        spec = importlib.util.spec_from_file_location("test_debian_root_partial", REPO / "build-support/debian-root.py")
        resolver = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = resolver
        spec.loader.exec_module(resolver)
        data = deb_bytes({"usr/lib/x86_64-linux-gnu/libc.so.6": b"only libc"})
        archive = self.cache / Path(self.pin["filename"]).name
        archive.write_bytes(data)
        pin = {**self.pin, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        with self.assertRaisesRegex(SystemExit, "complete usrmerged amd64 family"):
            stage.stage_glibc_package(resolver, pin, self.cache, self.source)
        self.assertEqual(stage.package_files(self.source), self.before)


if __name__ == "__main__":
    unittest.main()
