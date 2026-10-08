#!/usr/bin/env python3
"""Verify and install source-built ARM64 Android overlays for Vinix."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
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


_native_spec = importlib.util.spec_from_file_location("vinix_android_native", Path(__file__).with_name("_native.py"))
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def _boot_tools():
    specification = importlib.util.spec_from_file_location(
        "art_bootclasspath", Path(__file__).with_name("art-bootclasspath.py"))
    boot = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(boot)
    return boot


def _digest(path: Path) -> str:
    return _native.request("digest", path=str(path))


def configuration_probe_digest() -> str:
    """Bind ATL's native fixture provenance to all maintained V inputs."""
    return _native.request("configuration_probe_digest", support=str(Path(__file__).parent))


def _regular(path: Path) -> None:
    _native.request("regular", path=str(path))


def _relative(name: object) -> Path:
    return Path(_native.request("relative", name=name))


def _inside(root: Path, relative: Path) -> Path:
    return Path(_native.request("inside", root=str(root), path=str(relative)))


def _elf(path: Path, required: bool = False) -> None:
    _native.request("elf", path=str(path), required=bool(required))


def _record_fields(record):
    if not isinstance(record, dict):
        return None
    return {key: record[key] for key in ("path", "size", "sha256", "kind", "class_count", "bootstrap_callsites")
            if key in record}


def _runtime_fields(manifest):
    """Marshal observed metadata only; opaque extension fields remain Python-owned."""
    if not isinstance(manifest, dict):
        return None
    fields = {key: manifest[key] for key in (
        "format", "architecture", "page_size", "source_commit", "source_sha256", "source_sha512",
        "patch_sha256", "androidfw_configuration_api", "build_flags", "files", "androidfw_patch_sha256",
        "androidfw_header_sha256", "androidfw_library_sha256", "configuration_probe_sha256", "builder_sha256",
        "dex_adapter_sha256", "dex_compiler_sha256", "java_core_classes_sha256", "dex_compiler_arguments",
        "dex_compiler") if key in manifest}
    if isinstance(fields.get("files"), list):
        fields["files"] = [_record_fields(record) for record in fields["files"]]
    return fields


def _validate(overlay: Path, manifest: dict, bionic: bool = False, atl: bool = False) -> None:
    fields = _runtime_fields(manifest)
    seen = set(_native.request("validate_runtime", overlay=str(overlay),
                              support=str(Path(__file__).parent), manifest=fields,
                              bionic=bool(bionic), atl=bool(atl)))
    if atl:
        _validate_atl_payloads(overlay, manifest, seen)
    elif bionic:
        _native.request("validate_bionic_aliases", manifest=fields, seen=list(seen))
    if not bionic and not atl and "bootclasspath" in manifest:
        _boot_tools().validate_provenance(overlay, manifest["bootclasspath"], manifest["files"])


def _validate_atl_payloads(overlay: Path, manifest: dict, seen: set[str]) -> None:
    _native.request("validate_atl_required", seen=list(seen))
    boot = _boot_tools()
    _native.request("validate_atl_metadata", support=str(Path(__file__).parent),
                    manifest=_runtime_fields(manifest), seen=list(seen))
    records = {record["path"]: record for record in manifest["files"]}
    for name in seen:
        if not name.endswith(".jar"):
            continue
        try:
            classes, callsites = boot.jar_info(_inside(overlay, _relative(name)))
        except (ValueError, UnicodeError, zipfile.BadZipFile) as error:
            raise RuntimeError(f"ATL runtime has an invalid framework DEX JAR: {name}") from error
        _native.request("validate_atl_dex_receipt", name=name, record=_record_fields(records[name]),
                        classes=len(classes), callsites=callsites)
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
    path = Path(_native.request("manifest_path", overlay=str(overlay),
                                bionic=bool(bionic), atl=bool(atl)))
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
    _native.request("install_runtime", overlay=str(overlay), runtime=str(runtime),
                    manifest=_runtime_fields(manifest), bionic=bool(bionic), atl=bool(atl))
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
