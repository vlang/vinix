#!/usr/bin/env python3
"""Stage a pinned, private Android Translation Layer runtime for Vinix."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent
LOCK = SUPPORT / "packages.lock.json"
MIRROR = "https://dl-cdn.alpinelinux.org/alpine/edge"
PREFIX = "/opt/vinix-android-aarch64"
ARCHITECTURE = "aarch64"
REPOSITORIES = ("main", "community", "testing")
ROOT_PACKAGES = ("android-translation-layer", "font-dejavu", "font-noto", "ca-certificates-bundle")
CALCULATOR = {
    "filename": "Arity-1.1.apk",
    "url": "https://storage.googleapis.com/google-code-archive-source/v2/code.google.com/arity-calculator/source-archive.zip",
    "archive_member": "arity-calculator/rel/Arity-1.1.apk",
    "archive_sha256": "1b39e4f968e7d21602ea166f73a1b36c35213b78e9e3e06b74053cfdc98dfbe2",
    "sha256": "1928e65ced8cbe78be2ff3cb4c321e9e75d138e8e30ea1368fbb772a86827d1d",
    "version": "1.1",
    "license": "Apache-2.0",
    "activity": "calculator/Calculator",
}
REQUIRED = ("lib/ld-musl-aarch64.so.1", "usr/bin/android-translation-layer",
            "usr/lib/art/libart.so", "usr/lib/java/dex/android_translation_layer/api-impl.jar",
            "usr/lib/java/dex/android_translation_layer/framework-res.apk",
            "usr/lib/java/dex/android_translation_layer/natives/libtranslation_layer_main.so",
            "usr/lib/libvinix-android-compat.so", "art-runtime-manifest.json",
            "bionic-runtime-manifest.json", "atl-runtime-manifest.json",
            "runtime-manifest.json", "architecture")


def art_tools():
    spec = importlib.util.spec_from_file_location("vinix_art_runtime", SUPPORT / "art-runtime.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, target: Path, expected: str | None = None) -> str:
    if target.exists():
        actual = sha256(target)
        if expected is None or actual == expected:
            return actual
        raise RuntimeError(f"cached download checksum mismatch: {target}")
    print(f"  downloading {target.name}", flush=True)
    temporary = target.with_suffix(target.suffix + ".part")
    try:
        # curl provides retries and Alpine's normal HTTPS certificate check.
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                        "--retry", "3", "--output", str(temporary), url], check=True)
        actual = sha256(temporary)
        if expected is not None and actual != expected:
            raise RuntimeError(f"download checksum mismatch: {url}")
        temporary.replace(target)
        return actual
    finally:
        temporary.unlink(missing_ok=True)


def make_lock(downloads: Path, mirror: str) -> dict:
    indexes = []
    for repository in REPOSITORIES:
        archive = downloads / f"{repository}_APKINDEX.tar.gz"
        archive.unlink(missing_ok=True)
        digest = download(f"{mirror}/{repository}/{ARCHITECTURE}/APKINDEX.tar.gz", archive)
        index = downloads / f"{repository}_APKINDEX"
        with tarfile.open(archive) as source:
            member = source.extractfile("APKINDEX")
            if member is None:
                raise RuntimeError(f"APKINDEX missing from {archive}")
            index.write_bytes(member.read())
        indexes.append({"repository": repository, "sha256": digest})
    command = ["python3", str(ROOT / "build-support/alpine-resolve.py")]
    for repository in REPOSITORIES:
        command += ["--index", repository, str(downloads / f"{repository}_APKINDEX")]
    lines = subprocess.check_output(command + list(ROOT_PACKAGES), text=True).splitlines()
    records = []
    for line in lines:
        repository, filename = line.split("\t")
        # Package versions include the Alpine revision (name-version-rN.apk).
        name, version, revision = filename[:-4].rsplit("-", 2)
        records.append({"repository": repository, "filename": filename,
                        "name": name, "version": f"{version}-{revision}"})
    def fetch(record: dict) -> dict:
        record["sha256"] = download(f"{mirror}/{record['repository']}/{ARCHITECTURE}/{record['filename']}",
                                    downloads / record["filename"])
        return record
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        records = list(pool.map(fetch, records))
    return {"format": 1, "architecture": ARCHITECTURE, "mirror": mirror,
            "root_packages": list(ROOT_PACKAGES), "indexes": indexes, "packages": records}


def extract_apk(archive: Path, target: Path) -> None:
    # APK v2 is several concatenated gzip/tar streams: signatures, control,
    # payload. ignore_zeros keeps reading past each stream's end markers.
    with tarfile.open(archive, mode="r:gz", ignore_zeros=True) as source:
        for member in source:
            path = PurePosixPath(member.name)
            if not path.parts or path.parts[0].startswith("."):
                continue
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError(f"unsafe APK payload path: {member.name}")
            if not (member.isdir() or member.isfile() or member.issym() or member.islnk()):
                continue
            if member.issym():
                if member.linkname.startswith("/"):
                    member.linkname = os.path.relpath(target / member.linkname.lstrip("/"),
                                                     (target / member.name).parent)
                destination = (target / member.name).parent / member.linkname
                if not Path(os.path.abspath(destination)).is_relative_to(target):
                    raise RuntimeError(f"unsafe APK symlink: {member.name}")
            if member.islnk() and (member.linkname.startswith("/") or
                                  ".." in PurePosixPath(member.linkname).parts):
                raise RuntimeError(f"unsafe APK hardlink: {member.name}")
            destination = target / member.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.parent.resolve().is_relative_to(target):
                raise RuntimeError(f"APK payload parent escapes prefix: {member.name}")
            if member.isdir():
                destination.mkdir(exist_ok=True)
            else:
                if destination.exists() or destination.is_symlink():
                    destination.unlink()
                if member.issym():
                    destination.symlink_to(member.linkname)
                elif member.islnk():
                    existing = (target / member.linkname).resolve(strict=True)
                    if not existing.is_relative_to(target):
                        raise RuntimeError(f"APK hardlink escapes prefix: {member.name}")
                    os.link(existing, destination)
                else:
                    contents = source.extractfile(member)
                    if contents is None:
                        raise RuntimeError(f"APK file has no payload: {member.name}")
                    with contents, destination.open("wb") as output:
                        shutil.copyfileobj(contents, output)
                    destination.chmod(member.mode & 0o777)


def materialize_library_links(runtime: Path) -> None:
    # Vinix's loader does not reliably follow aliases when opening DSOs.
    for directory in (runtime / "lib", runtime / "usr/lib"):
        for link in sorted(directory.rglob("*")):
            if link.is_symlink() and (".so" in link.name or link.name.startswith("ld-musl-")):
                source = link.resolve(strict=True)
                if not source.is_relative_to(runtime):
                    raise RuntimeError(f"runtime library symlink escapes prefix: {link}")
                link.unlink()
                os.link(source, link)


def relocate_configuration(runtime: Path) -> None:
    # Fontconfig embeds /usr/share/fonts and includes relative conf.d files.
    # Rewrite its own paths to the matching fonts/config in this runtime.
    for config in (runtime / "etc/fonts").rglob("*.conf"):
        if config.is_symlink():
            continue
        text = config.read_text()
        text = text.replace("/usr/share/fonts", PREFIX + "/usr/share/fonts")
        text = text.replace("/usr/local/share/fonts", PREFIX + "/usr/local/share/fonts")
        text = text.replace("/etc/fonts", PREFIX + "/etc/fonts")
        config.write_text(text)


def calculator_apk(downloads: Path) -> Path:
    apk = downloads / CALCULATOR["filename"]
    if apk.exists():
        if sha256(apk) != CALCULATOR["sha256"]:
            raise RuntimeError(f"calculator APK checksum mismatch: {apk}")
        return apk
    archive = downloads / "arity-calculator-source-archive.zip"
    download(CALCULATOR["url"], archive, CALCULATOR["archive_sha256"])
    with zipfile.ZipFile(archive) as source:
        payload = source.read(CALCULATOR["archive_member"])
    if hashlib.sha256(payload).hexdigest() != CALCULATOR["sha256"]:
        raise RuntimeError("calculator APK checksum mismatch in official source archive")
    apk.write_bytes(payload)
    return apk


def stage(args: argparse.Namespace, lock: dict, downloads: Path) -> Path:
    staging = args.build_dir / "staging"
    runtime = staging / PREFIX.lstrip("/")
    art = art_tools()
    if not args.art_runtime.is_dir():
        raise RuntimeError(f"missing native 16 KiB ART overlay: {args.art_runtime}; "
                           "run build-support/android/build-art.sh on ARM64 Alpine Linux first")
    art_manifest = art.read_manifest(args.art_runtime)
    if not art_manifest.get("bootclasspath"):
        raise RuntimeError("ART's Java boot libraries must be desugared first; run "
                           "build-support/android/art-bootclasspath.py --build-dir "
                           f"{args.build_dir / 'java-build'} --art-runtime {args.art_runtime}")
    if not args.bionic_runtime.is_dir():
        raise RuntimeError(f"missing native 16 KiB APK library loader: {args.bionic_runtime}; "
                           "run build-support/android/build-bionic.sh on ARM64 Alpine Linux first")
    bionic_manifest = art.read_bionic_manifest(args.bionic_runtime)
    if not args.atl_runtime.is_dir():
        raise RuntimeError(f"missing coherent native ATL overlay: {args.atl_runtime}; "
                           "run build-support/android/build-atl.sh on ARM64 Alpine Linux first")
    atl_manifest = art.read_atl_manifest(args.atl_runtime)
    inputs = json.dumps(lock, sort_keys=True).encode() + str(args.with_calculator).encode()
    inputs += json.dumps(art_manifest, sort_keys=True).encode()
    inputs += json.dumps(bionic_manifest, sort_keys=True).encode()
    inputs += json.dumps(atl_manifest, sort_keys=True).encode()
    for source in (Path(__file__), SUPPORT / "run-android", SUPPORT / "runtime-compat.c",
                   SUPPORT / "art-runtime.py", SUPPORT / "art16k.patch", SUPPORT / "build-art.sh",
                   SUPPORT / "art-bootclasspath.py", SUPPORT / "bionic16k.patch", SUPPORT / "build-bionic.sh",
                   SUPPORT / "build-atl.sh", SUPPORT / "atl-dex.py",
                   ROOT / "build-support/java-cacerts.py"):
        inputs += source.read_bytes()
    cache_key = hashlib.sha256(inputs).hexdigest()
    cache = args.build_dir / ".staging-cache-key"
    if (cache.exists() and cache.read_text().strip() == cache_key and
        all((runtime / name).is_file() for name in REQUIRED) and
        (staging / "usr/bin/run-android").is_file() and
        (not args.with_calculator or (staging / "usr/bin/run-android-calculator").is_file())):
        try:
            cached_art = art.read_manifest(runtime)
            cached_bionic = art.read_bionic_manifest(runtime)
            cached_atl = art.read_atl_manifest(runtime)
            cached_runtime = json.loads((runtime / "runtime-manifest.json").read_text())
            metadata_matches = (
                isinstance(cached_runtime, dict) and
                cached_runtime.get("architecture") == ARCHITECTURE and
                (runtime / "architecture").read_text().strip() == ARCHITECTURE and
                cached_runtime.get("execution") == "native" and
                cached_runtime.get("page_size") == 16384 and
                cached_runtime.get("runtime_prefix") == PREFIX and
                cached_runtime.get("packages") == lock["packages"] and
                cached_runtime.get("art") == art_manifest and
                cached_runtime.get("bionic") == bionic_manifest and
                cached_runtime.get("atl") == atl_manifest
            )
        except (RuntimeError, OSError, ValueError):
            cached_art = None
            cached_bionic = None
            cached_atl = None
            metadata_matches = False
        if (cached_art == art_manifest and cached_bionic == bionic_manifest and
                cached_atl == atl_manifest and metadata_matches):
            print(f"Reusing pinned native Android runtime in {staging}", flush=True)
            return staging
    compiler = shutil.which("aarch64-linux-musl-gcc")
    if compiler is None:
        raise RuntimeError("aarch64-linux-musl-gcc is required to build the Android compatibility library")
    cache.unlink(missing_ok=True)
    if staging.exists():
        shutil.rmtree(staging)
    runtime.mkdir(parents=True)
    def fetch(record: dict) -> Path:
        archive = downloads / record["filename"]
        download(f"{lock['mirror']}/{record['repository']}/{lock['architecture']}/{record['filename']}",
                 archive, record["sha256"])
        return archive
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        archives = list(pool.map(fetch, lock["packages"]))
    for archive in archives:
        extract_apk(archive, runtime)
    materialize_library_links(runtime)
    # Alpine's ART assumes 4 KiB pages. Replace it with the verified native
    # source build before launching anything on Vinix's 16 KiB kernel.
    art.apply(args.art_runtime, runtime, art_manifest)
    (runtime / art.MANIFEST).write_text(json.dumps(art_manifest, indent=2) + "\n")
    art.apply_bionic(args.bionic_runtime, runtime, bionic_manifest)
    (runtime / art.BIONIC_MANIFEST).write_text(json.dumps(bionic_manifest, indent=2) + "\n")
    # Native helpers, framework DEX and resources must come from one source
    # build. Replacing only a JAR can leave JNI registration out of sync.
    art.apply_atl(args.atl_runtime, runtime, atl_manifest)
    (runtime / art.ATL_MANIFEST).write_text(json.dumps(atl_manifest, indent=2) + "\n")
    relocate_configuration(runtime)
    subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                    str(SUPPORT / "runtime-compat.c"), "-ldl",
                    "-o", str(runtime / "usr/lib/libvinix-android-compat.so")], check=True)
    # The java-cacerts package contains a trigger rather than its generated
    # store. Recreate that store without running Alpine package scripts.
    subprocess.run(["python3", str(ROOT / "build-support/java-cacerts.py"),
                    str(runtime / "usr/share/ca-certificates/mozilla"),
                    str(runtime / "etc/ssl/certs/java/cacerts")], check=True)
    # This is an ATL-owned Android font map; the native desktop keeps its
    # /etc/fonts and GTK libraries. INSTALL_DATADIR is fixed in Alpine's ATL.
    atl_resources = runtime / "usr/share/atl"
    if atl_resources.exists():
        shutil.copytree(atl_resources, staging / "usr/share/atl", symlinks=True)
    commands = staging / "usr/bin"
    commands.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SUPPORT / "run-android", commands / "run-android")
    (commands / "run-android").chmod(0o755)
    manifest = dict(lock)
    manifest["runtime_prefix"] = PREFIX
    manifest["execution"] = "native"
    manifest["page_size"] = 16384
    manifest["art"] = art_manifest
    manifest["bionic"] = bionic_manifest
    manifest["atl"] = atl_manifest
    manifest["upstream"] = "https://gitlab.com/android_translation_layer/android_translation_layer"
    if args.with_calculator:
        apk = calculator_apk(downloads)
        samples = staging / "usr/share/vinix/android"
        samples.mkdir(parents=True, exist_ok=True)
        shutil.copy2(apk, samples / apk.name)
        (commands / "run-android-calculator").write_text(
            '#!/bin/sh\nexec /usr/bin/run-android '
            '/usr/share/vinix/android/Arity-1.1.apk '
            '-l calculator/Calculator -w 480 -h 640 "$@"\n')
        (commands / "run-android-calculator").chmod(0o755)
        manifest["calculator"] = CALCULATOR
    (runtime / "runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (runtime / "architecture").write_text(lock["architecture"] + "\n")
    for name in REQUIRED:
        if not (runtime / name).is_file():
            raise RuntimeError(f"missing staged Android runtime file: {name}")
    cache.write_text(cache_key + "\n")
    print(f"Staged {len(lock['packages'])} pinned packages in {staging}", flush=True)
    return staging


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path,
                        default=os.environ.get("VINIX_ANDROID_BUILD_DIR"))
    parser.add_argument("--with-calculator", action="store_true", help="include the verified Arity calculator APK")
    parser.add_argument("--art-runtime", type=Path, default=os.environ.get("VINIX_ANDROID_ART_RUNTIME"),
                        help="verified ARM64 ART overlay built for Vinix's 16 KiB pages")
    parser.add_argument("--bionic-runtime", type=Path, default=os.environ.get("VINIX_ANDROID_BIONIC_RUNTIME"),
                        help="verified ARM64 APK native-library loader built for 16 KiB pages")
    parser.add_argument("--atl-runtime", type=Path, default=os.environ.get("VINIX_ANDROID_ATL_RUNTIME"),
                        help="verified coherent ARM64 ATL native/framework/resource overlay")
    parser.add_argument("--update-lock", action="store_true", help="resolve current Alpine indexes and pin their closure")
    parser.add_argument("--mirror", default=os.environ.get("ALPINE_MIRROR", MIRROR),
                        help="Alpine edge mirror used when updating the package lock")
    args = parser.parse_args()
    if args.build_dir is None:
        args.build_dir = ROOT / "build-aarch64-android/aarch64"
    args.build_dir = args.build_dir.expanduser().resolve()
    args.art_runtime = (args.art_runtime or args.build_dir / "art-runtime").expanduser().resolve()
    args.bionic_runtime = (args.bionic_runtime or args.build_dir / "bionic-runtime").expanduser().resolve()
    args.atl_runtime = (args.atl_runtime or args.build_dir / "atl-runtime").expanduser().resolve()
    downloads = args.build_dir / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    if args.update_lock:
        lock = make_lock(downloads, args.mirror.rstrip("/"))
        LOCK.write_text(json.dumps(lock, indent=2) + "\n")
    else:
        lock = json.loads(LOCK.read_text())
    if lock["architecture"] != ARCHITECTURE:
        raise RuntimeError("package lock architecture does not match requested runtime")
    stage(args, lock, downloads)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
