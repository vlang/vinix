#!/usr/bin/env python3
"""Verify and install source-built ARM64 Android overlays for Vinix."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import tempfile
import xml.etree.ElementTree as ET
import zipfile


MANIFEST = "art-runtime-manifest.json"
PATCH = Path(__file__).with_name("art16k.patch")
SOURCE_COMMIT = "e78bf68917bcaaf58fef3960cd88793b3b7f39cc"
SOURCE_SHA256 = "2efcaf77d1c3e08dc738b7d1d38ad789b0a0fc729612fb67169d0b2c250b61d7"
SOURCE_SHA512 = (
    "75ef56d63dfc7661a7928191441d4672d612b6a8d27c3957764d324e4f622a42c132c345"
    "40f6a89556b1971964df8be2eced0b8a599d5a793ab3039cfb9c48a2"
)
PAGE_SIZE = 16384
LIBART = "usr/lib/art/libart.so"
# Match build-art.sh's complete native output. Omitting a library would leave
# Alpine's original 4 KiB module installed beside the patched runtime.
ART_ELFS = frozenset({"usr/lib/art/" + name + ".so" for name in (
    "libandroidfw", "libart", "libart-compiler", "libart-dexlayout", "libartbase",
    "libartpalette", "libbacktrace", "libbase", "libcutils", "libdexfile", "liblog",
    "libnativebridge", "libprofile", "libsigchain", "libunwind", "libutils", "libziparchive",
)}) | frozenset({"usr/lib/java/dex/art/natives/" + name + ".so" for name in (
    "libjavacore", "libnativehelper", "libopenjdk", "libopenjdkjvm",
)}) | {"usr/bin/dalvikvm", "usr/bin/dex2oat"}
# The source builder emits only native files. The later bootclasspath step
# adds these JARs and its compiler receipt to the same overlay.
ART_BOOT_JARS = frozenset({"usr/lib/java/dex/art/" + name for name in (
    "core-oj-hostdex.jar", "core-libart-hostdex.jar",
)})
ANDROIDFW_HEADER = "usr/include/androidfw/androidfw_c_api.h"
ANDROIDFW_LIBRARY = "usr/lib/art/libandroidfw.so"
ART_HEADERS = frozenset({ANDROIDFW_HEADER})
BIONIC_MANIFEST = "bionic-runtime-manifest.json"
BIONIC_PATCH = Path(__file__).with_name("bionic16k.patch")
BIONIC_SOURCE_COMMIT = "ee37eb21c91409fe0eed833d0a5a0aa6b931bb7b"
BIONIC_SOURCE_SHA256 = "b1b2fa762485c1f33e71c0de6a4cbf4ca7006cfaec9c4c9cc20949393cbf49ef"
BIONIC_SOURCE_SHA512 = (
    "713f3a7c147e06781eb60f352d2c801b1b661e52bd33aa627ec1bbcb3587f15af3339"
    "3f8068d9e341f6869777ac008bee6c8ef8a26f0826049a9fa226dcdbeac"
)
BIONIC_LIBRARIES = frozenset({
    "usr/lib/libc_bio.so", "usr/lib/libc_bio.so.0",
    "usr/lib/libdl_bio.so", "usr/lib/libdl_bio.so.0", "usr/lib/libdl_bio.so.0.0.1",
    "usr/lib/libpthread_bio.so", "usr/lib/libpthread_bio.so.0",
    "usr/lib/libstdc++_bio.so", "usr/lib/libstdc++_bio.so.0",
})
ATL_MANIFEST = "atl-runtime-manifest.json"
ATL_PATCH = Path(__file__).with_name("atl-configuration.patch")
ATL_SOURCE_COMMIT = "aa80e7405436fb4b442b7c90abefd2d526f8543a"
ATL_SOURCE_SHA256 = "20c1ce3890d416099fd446d299eb58069ee41d38c1a412e2e331b91c07aca9f1"
ATL_SOURCE_SHA512 = (
    "3e274fd63f3eec25fd83efddc8c5135c494bb978c0a481a75ca703779e63a85ffe8d"
    "50047d73a29fdf68a4fb08c0c283339517afe8f82214e289b64037e88221"
)
ATL_DEX_DIRECTORY = "usr/lib/java/dex/android_translation_layer"
ATL_JARS = frozenset({ATL_DEX_DIRECTORY + "/" + name for name in (
    "api-impl.jar", "gstub.jar", "ghax.jar")})
ATL_ELFS = frozenset({
    "usr/bin/android-translation-layer", "usr/lib/libandroid.so", "usr/lib/libandroid.so.0",
    "usr/libexec/vinix-android/atl-configuration-test",
    ATL_DEX_DIRECTORY + "/natives/libtranslation_layer_main.so",
})
ATL_RESOURCES = ATL_DEX_DIRECTORY + "/framework-res.apk"
ATL_FONTS = "usr/share/atl/system/etc/fonts.xml"
ATL_REQUIRED = ATL_ELFS | ATL_JARS | {ATL_RESOURCES, ATL_FONTS}
ATL_CORE_CLASSES_SHA256 = "f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42"


def _boot_tools():
    specification = importlib.util.spec_from_file_location(
        "art_bootclasspath", Path(__file__).with_name("art-bootclasspath.py"))
    boot = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(boot)
    return boot


def _digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def configuration_probe_digest() -> str:
    """Bind ATL's native fixture provenance to all maintained V inputs."""
    support = Path(__file__).parent
    inputs = (support / "atlconfiguration/core.v", support / "atl-configuration-v-abi.h",
              support / "compile-v-atl-configuration.py", support.parent / "compile-v-module.py",
              support.parent / "find-v.sh")
    result = hashlib.sha256()
    for source in inputs:
        result.update(str(source.relative_to(support.parent)).encode() + b"\0")
        result.update(source.read_bytes())
    return result.hexdigest()


def _regular(path: Path) -> None:
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise RuntimeError(f"ART overlay file is missing or unreadable: {path}") from error
    if not stat.S_ISREG(mode):
        raise RuntimeError(f"ART overlay file is not a regular file: {path}")


def _relative(name: object) -> Path:
    if not isinstance(name, str):
        raise RuntimeError("ART overlay path must be a string")
    relative = PurePosixPath(name)
    if ("\x00" in name or relative.is_absolute() or len(relative.parts) < 2 or relative.parts[0] != "usr"
            or ".." in relative.parts or str(relative) != name):
        raise RuntimeError(f"unsafe ART overlay path: {name}")
    return Path(*relative.parts)


def _inside(root: Path, relative: Path) -> Path:
    path = root / relative
    # Reject symlink parents as well as files: an overlay must not supply or
    # write through aliases into a different part of the staging filesystem.
    parent = root
    for part in relative.parts[:-1]:
        parent = parent / part
        if parent.is_symlink():
            raise RuntimeError(f"ART overlay has a symlink parent: {parent}")
    if not path.parent.resolve().is_relative_to(root.resolve()):
        raise RuntimeError(f"ART overlay path escapes its root: {path}")
    return path


def _elf(path: Path, required: bool = False) -> None:
    size = path.stat().st_size
    with path.open("rb") as stream:
        header = stream.read(64)
        if header[:4] != b"\x7fELF":
            if required:
                raise RuntimeError(f"Android runtime payload is not an ELF: {path}")
            return
        if (len(header) != 64 or header[:7] != b"\x7fELF\x02\x01\x01"
                or struct.unpack_from("<H", header, 18)[0] != 183
                or struct.unpack_from("<I", header, 20)[0] != 1):
            raise RuntimeError(f"ART overlay is not a native ARM64 ELF: {path}")
        offset = struct.unpack_from("<Q", header, 32)[0]
        entry_size, count = struct.unpack_from("<HH", header, 54)
        if entry_size != 56 or count == 0 or offset > size or count * entry_size > size - offset:
            raise RuntimeError(f"ART overlay has invalid ELF program headers: {path}")
        stream.seek(offset)
        headers = stream.read(count * entry_size)
        loads = 0
        for index in range(count):
            kind, _, file_offset, address, _, file_size, memory_size, _ = struct.unpack_from(
                "<IIQQQQQQ", headers, index * entry_size)
            if kind != 1:
                continue
            loads += 1
            if (file_size > memory_size or file_offset > size or file_size > size - file_offset
                    or memory_size > (1 << 64) - 1 - address
                    or address % PAGE_SIZE != file_offset % PAGE_SIZE):
                raise RuntimeError(f"ART overlay ELF cannot load with 16 KiB pages: {path}")
        if loads == 0:
            raise RuntimeError(f"ART overlay ELF has no loadable segments: {path}")


def _validate(overlay: Path, manifest: dict, bionic: bool = False, atl: bool = False) -> None:
    label = "ATL" if atl else "Bionic" if bionic else "ART"
    commit = ATL_SOURCE_COMMIT if atl else BIONIC_SOURCE_COMMIT if bionic else SOURCE_COMMIT
    sha256 = ATL_SOURCE_SHA256 if atl else BIONIC_SOURCE_SHA256 if bionic else SOURCE_SHA256
    sha512 = ATL_SOURCE_SHA512 if atl else BIONIC_SOURCE_SHA512 if bionic else SOURCE_SHA512
    patch = ATL_PATCH if atl else BIONIC_PATCH if bionic else PATCH
    flag = "-Wl,-z,max-page-size=65536" if atl else "-DBIONIC_PAGE_SIZE=16384" if bionic else "-DART_PAGE_SIZE=16384"
    if not isinstance(manifest, dict):
        raise RuntimeError(f"{label} runtime manifest must be an object")
    if (type(manifest.get("format")) is not int or manifest["format"] != 1
            or manifest.get("architecture") != "aarch64"
            or manifest.get("page_size") != PAGE_SIZE):
        raise RuntimeError(f"{label} runtime must be format 1, native ARM64, and built for 16 KiB pages")
    if (manifest.get("source_commit") != commit
            or manifest.get("source_sha512") != sha512
            or manifest.get("source_sha256") != sha256):
        raise RuntimeError(f"{label} runtime source does not match the pinned source archive")
    if manifest.get("patch_sha256") != _digest(patch):
        raise RuntimeError(f"{label} runtime was built with a different Vinix patch; rebuild {label}")
    if not bionic and manifest.get("androidfw_configuration_api") != 1:
        raise RuntimeError(f"{label} runtime lacks the native androidfw configuration API")
    flags = manifest.get("build_flags")
    if (not isinstance(flags, list) or not all(isinstance(flag, str) for flag in flags)
            or flag not in flags):
        raise RuntimeError(f"{label} runtime manifest is missing its 16 KiB compiler flag")
    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        raise RuntimeError("ART runtime manifest has no files")
    seen = set()
    for record in files:
        if not isinstance(record, dict):
            raise RuntimeError("ART runtime file record must be an object")
        relative = _relative(record.get("path"))
        name = relative.as_posix()
        if name in seen:
            raise RuntimeError(f"duplicate ART runtime file: {name}")
        seen.add(name)
        if (type(record.get("size")) is not int or record["size"] < 0
                or not isinstance(record.get("sha256"), str)
                or re.fullmatch(r"[0-9a-f]{64}", record["sha256"]) is None):
            raise RuntimeError(f"invalid ART runtime file size or hash: {name}")
        path = _inside(overlay, relative)
        _regular(path)
        if path.stat().st_size != record["size"] or _digest(path) != record["sha256"]:
            raise RuntimeError(f"ART runtime file checksum mismatch: {name}")
        _elf(path, required=bionic or name in (ATL_ELFS if atl else ART_ELFS))
        if atl:
            with path.open("rb") as contents:
                magic = contents.read(4)
            kind = "elf" if magic == b"\x7fELF" else "dex" if name.endswith(".jar") else "data"
            if record.get("kind") != kind:
                raise RuntimeError(f"ATL runtime file kind does not match its payload: {name}")
    if atl:
        _validate_atl_payloads(overlay, manifest, seen)
    elif bionic:
        if seen != BIONIC_LIBRARIES:
            raise RuntimeError("Bionic runtime must contain all nine loader libraries and SONAME aliases")
        records = {record["path"]: record for record in files}
        for name in seen:
            canonical = name.split(".so", 1)[0] + ".so"
            if any(records[name][key] != records[canonical][key] for key in ("sha256", "size")):
                raise RuntimeError(f"Bionic SONAME alias differs from its canonical library: {name}")
    else:
        missing = (ART_ELFS | ART_HEADERS) - seen
        unexpected = seen - (ART_ELFS | ART_HEADERS | ART_BOOT_JARS)
        if missing:
            raise RuntimeError("ART runtime is missing required native outputs: "
                               + ", ".join(sorted(missing)))
        if unexpected:
            raise RuntimeError("ART runtime has unexpected outputs: "
                               + ", ".join(sorted(unexpected)))
    if not bionic and not atl and "bootclasspath" in manifest:
        _boot_tools().validate_provenance(overlay, manifest["bootclasspath"], manifest["files"])


def _validate_atl_payloads(overlay: Path, manifest: dict, seen: set[str]) -> None:
    if ATL_REQUIRED != seen:
        raise RuntimeError("ATL runtime is missing part of its coherent native/framework/resource output")
    boot = _boot_tools()
    if ("--buildtype=release" not in manifest["build_flags"]
            or manifest.get("androidfw_patch_sha256") != _digest(PATCH)
            or any(not isinstance(manifest.get(key), str)
                   or re.fullmatch(r"[0-9a-f]{64}", manifest[key]) is None
                   for key in ("androidfw_header_sha256", "androidfw_library_sha256"))
            or manifest.get("configuration_probe_sha256") != configuration_probe_digest()
            or manifest.get("builder_sha256") != _digest(Path(__file__).with_name("build-atl.sh"))
            or manifest.get("dex_adapter_sha256") != _digest(Path(__file__).with_name("atl-dex.py"))
            or manifest.get("dex_compiler_sha256") != boot.INPUTS[2]["sha256"]
            or manifest.get("java_core_classes_sha256") != ATL_CORE_CLASSES_SHA256
            or manifest.get("dex_compiler_arguments") != boot.COMPILER_ARGUMENTS
            or not isinstance(manifest.get("dex_compiler"), str)
            or not manifest["dex_compiler"].startswith("D8 8.3.37 (build ")):
        raise RuntimeError("ATL runtime does not match the pinned builder and Java compiler inputs")
    records = {record["path"]: record for record in manifest["files"]}
    for key in ("size", "sha256"):
        if records["usr/lib/libandroid.so"][key] != records["usr/lib/libandroid.so.0"][key]:
            raise RuntimeError("ATL libandroid SONAME alias differs from its canonical library")
    for name in seen:
        if not name.endswith(".jar"):
            continue
        try:
            classes, callsites = boot.jar_info(_inside(overlay, _relative(name)))
        except (ValueError, UnicodeError, zipfile.BadZipFile) as error:
            raise RuntimeError(f"ATL runtime has an invalid framework DEX JAR: {name}") from error
        if not classes or callsites != 0:
            raise RuntimeError(f"ATL framework retained unsupported Java bootstrap calls: {name}")
        for key, measured in (("class_count", len(classes)), ("bootstrap_callsites", callsites)):
            if type(records[name].get(key)) is not int or records[name][key] != measured:
                raise RuntimeError(f"ATL framework DEX does not match its compiler receipt: {name}")
    try:
        with zipfile.ZipFile(overlay / ATL_RESOURCES) as resources:
            if not {"AndroidManifest.xml", "resources.arsc"} <= set(resources.namelist()):
                raise RuntimeError("ATL framework resources APK is incomplete")
        fonts = ET.parse(overlay / ATL_FONTS).getroot()
        font = fonts.find("family/font")
        if fonts.tag != "familyset" or font is None or not font.text or not font.text.strip():
            raise RuntimeError("ATL Android font map is incomplete")
    except (ET.ParseError, zipfile.BadZipFile) as error:
        raise RuntimeError("ATL framework resources or Android font map are invalid") from error


def _read_manifest(overlay: Path, bionic: bool = False, atl: bool = False) -> dict:
    label = "ATL" if atl else "Bionic" if bionic else "ART"
    overlay = Path(overlay)
    if overlay.is_symlink() or not overlay.is_dir():
        raise RuntimeError(f"{label} runtime overlay must be a directory: {overlay}")
    path = overlay / (ATL_MANIFEST if atl else BIONIC_MANIFEST if bionic else MANIFEST)
    _regular(path)
    try:
        manifest = json.loads(path.read_text())
    except (ValueError, UnicodeError) as error:
        raise RuntimeError(f"invalid {label} runtime manifest: {path}") from error
    _validate(overlay, manifest, bionic, atl)
    return manifest


def _apply(overlay: Path, runtime: Path, manifest: dict, bionic: bool = False, atl: bool = False) -> dict:
    """Copy verified payloads, replacing rather than overwriting old hardlinks."""
    overlay, runtime = Path(overlay), Path(runtime)
    if _read_manifest(overlay, bionic, atl) != manifest:
        raise RuntimeError("ART runtime manifest changed between verification and installation")
    if runtime.is_symlink():
        raise RuntimeError(f"ART destination must not be a symlink: {runtime}")
    runtime.mkdir(parents=True, exist_ok=True)
    # Check every destination before publishing any files.
    destinations = [_inside(runtime, _relative(record["path"])) for record in manifest["files"]]
    for record, target in zip(manifest["files"], destinations):
        source = _inside(overlay, _relative(record["path"]))
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(prefix=".vinix-art-", dir=target.parent,
                                             delete=False) as output:
                temporary = Path(output.name)
                with source.open("rb") as contents:
                    shutil.copyfileobj(contents, output)
            if temporary.stat().st_size != record["size"] or _digest(temporary) != record["sha256"]:
                raise RuntimeError(f"ART runtime file changed during installation: {record['path']}")
            _elf(temporary, required=bionic or record["path"] in (ATL_ELFS if atl else ART_ELFS))
            temporary.chmod(stat.S_IMODE(source.stat().st_mode) & 0o777)
            os.replace(temporary, target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return manifest


def read_manifest(overlay: Path) -> dict:
    return _read_manifest(overlay)


def apply(overlay: Path, runtime: Path, manifest: dict) -> dict:
    return _apply(overlay, runtime, manifest)


def read_bionic_manifest(overlay: Path) -> dict:
    return _read_manifest(overlay, bionic=True)


def apply_bionic(overlay: Path, runtime: Path, manifest: dict) -> dict:
    return _apply(overlay, runtime, manifest, bionic=True)


def read_atl_manifest(overlay: Path) -> dict:
    manifest = _read_manifest(overlay, atl=True)
    if (overlay / MANIFEST).exists():
        validate_atl_art_pair(read_manifest(overlay), manifest)
    return manifest


def validate_atl_art_pair(art_manifest: dict, atl_manifest: dict) -> None:
    """Require ATL's compile header and linked provider from the selected ART."""
    records = {record.get("path"): record for record in art_manifest.get("files", [])}
    if (art_manifest.get("androidfw_configuration_api") != 1
            or atl_manifest.get("androidfw_configuration_api") != 1
            or atl_manifest.get("androidfw_patch_sha256") != art_manifest.get("patch_sha256")
            or any(atl_manifest.get(key) != records.get(name, {}).get("sha256")
                   for key, name in (("androidfw_header_sha256", ANDROIDFW_HEADER),
                                     ("androidfw_library_sha256", ANDROIDFW_LIBRARY)))):
        raise RuntimeError("ATL's androidfw header and linked provider differ from the selected ART; rebuild ATL")


def apply_atl(overlay: Path, runtime: Path, manifest: dict) -> dict:
    return _apply(overlay, runtime, manifest, atl=True)
