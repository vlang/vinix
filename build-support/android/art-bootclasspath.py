#!/usr/bin/env python3
"""Desugar ART's own Java boot libraries without modifying application APKs."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
import tempfile
import zipfile


SUPPORT = Path(__file__).resolve().parent
BASE_URL = "https://dl-cdn.alpinelinux.org/alpine/edge/testing/aarch64/"
INPUTS = (
    {"filename": "art_standalone-0_git20251009-r2.apk", "url": BASE_URL + "art_standalone-0_git20251009-r2.apk",
     "sha256": "92f37ff68bff7e3d9f89ac4da0f7e0474aeccd9d77df7360a128ad76093aad99"},
    {"filename": "art_standalone-dev-0_git20251009-r2.apk", "url": BASE_URL + "art_standalone-dev-0_git20251009-r2.apk",
     "sha256": "0486502b242290d0f8b270205e726230ba1d9d57c04ed54f16bacef8ff829e99"},
    {"filename": "r8-8.3.37.jar", "url": "https://storage.googleapis.com/r8-releases/raw/8.3.37/r8.jar",
     "sha256": "900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199"},
)
JAVA_CLASS_JAR = "usr/lib/java/core-all_classes.jar"
BOOT_JARS = ("core-oj-hostdex.jar", "core-libart-hostdex.jar")
BOOT_DIRECTORY = "usr/lib/java/dex/art"
COMPILER_ARGUMENTS = ["--release", "--min-api", "26", "--android-platform-build",
                      "--force-passthrough-assertions"]
BOOT_ORIGINAL = {
    "core-oj-hostdex.jar": {
        "original_sha256": "ce272a51212558a609e364e527bf8f548b56a1284899c398a74183c12c4f45a6",
        "classes_before": 3296, "bootstrap_callsites_before": 339,
    },
    "core-libart-hostdex.jar": {
        "original_sha256": "5db335098d4f779c55deb1fe63ff3becf37e39228b242c366a4ad809dd3cd132",
        "classes_before": 1686, "bootstrap_callsites_before": 3,
    },
}


_native_spec = importlib.util.spec_from_file_location("vinix_android_native", Path(__file__).with_name("_native.py"))
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def digest(path: Path) -> str:
    return _native.request("digest", path=str(path))


def download(record: dict, directory: Path) -> Path:
    target = directory / record["filename"]
    if not target.exists():
        temporary = target.with_suffix(target.suffix + ".part")
        try:
            subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "3",
                            "--output", str(temporary), record["url"]], check=True)
            if digest(temporary) != record["sha256"]:
                raise RuntimeError(f"bootclasspath input checksum mismatch: {target.name}")
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    if not target.is_file() or target.is_symlink() or digest(target) != record["sha256"]:
        raise RuntimeError(f"bootclasspath input checksum mismatch: {target.name}")
    return target


def extract_member(archive: Path, name: str, output: Path) -> None:
    with tarfile.open(archive, "r:gz", ignore_zeros=True) as source:
        for member in source:
            if member.name == name:
                if not member.isfile():
                    raise RuntimeError(f"bootclasspath input is not a regular file: {name}")
                contents = source.extractfile(member)
                if contents is None:
                    raise RuntimeError(f"bootclasspath input has no contents: {name}")
                with contents, output.open("wb") as target:
                    shutil.copyfileobj(contents, target)
                return
    raise RuntimeError(f"bootclasspath input is missing {name}")


def dex_info(data: bytes) -> tuple[set[str], int]:
    classes, callsites = _native.request("dex_info", data=bytes(data).hex())
    return set(classes), callsites


def jar_info(path: Path) -> tuple[set[str], int]:
    classes, callsites = set(), 0
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.endswith(".dex"):
                found, count = dex_info(archive.read(name))
                if classes & found:
                    raise RuntimeError(f"duplicate classes across bootclasspath DEX files: {path}")
                classes.update(found)
                callsites += count
    if not classes:
        raise RuntimeError(f"bootclasspath JAR has no DEX classes: {path}")
    return classes, callsites


def class_subset(raw: Path, names: set[str], output: Path) -> None:
    with zipfile.ZipFile(raw) as source, zipfile.ZipFile(output, "w") as target:
        available = set(source.namelist())
        missing = names - available
        if missing:
            raise RuntimeError(f"pinned bootclasspath class input is missing {sorted(missing)[0]}")
        for name in sorted(names):
            target.writestr(name, source.read(name))


def package_jar(original: Path, dex_directory: Path, output: Path) -> None:
    payload = {}
    with zipfile.ZipFile(original) as source:
        for name in source.namelist():
            if not name.endswith(".dex"):
                payload[name] = source.read(name)
    for path in sorted(dex_directory.glob("*.dex")):
        payload[path.name] = path.read_bytes()
    if "classes.dex" not in payload:
        raise RuntimeError("D8 did not produce classes.dex")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for name, contents in sorted(payload.items()):
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o644 << 16
            target.writestr(entry, contents)


def validate_provenance(root: Path, manifest: dict, payloads: list[dict] | None = None) -> None:
    """Tie the compiler receipt to pinned inputs and the installed DEX payloads."""
    if (not isinstance(manifest, dict) or type(manifest.get("format")) is not int
            or manifest["format"] != 1 or manifest.get("inputs") != list(INPUTS)
            or manifest.get("compiler_arguments") != COMPILER_ARGUMENTS
            or not isinstance(manifest.get("compiler"), str)
            or not manifest["compiler"].startswith("D8 8.3.37 (build ")):
        raise RuntimeError("bootclasspath provenance does not match the pinned compiler and inputs")
    key = manifest.get("input_key")
    if not isinstance(key, str) or len(key) != 64 or any(value not in "0123456789abcdef" for value in key):
        raise RuntimeError("bootclasspath provenance has an invalid input key")
    files = manifest.get("files")
    if not isinstance(files, list) or len(files) != len(BOOT_JARS):
        raise RuntimeError("bootclasspath provenance must contain both Java boot libraries")
    records = {record["path"]: record for record in payloads} if payloads is not None else None
    seen = set()
    for record in files:
        if not isinstance(record, dict):
            raise RuntimeError("bootclasspath file receipt must be an object")
        name = record.get("path")
        if (not isinstance(name, str)
                or name not in {BOOT_DIRECTORY + "/" + jar for jar in BOOT_JARS} or name in seen):
            raise RuntimeError("bootclasspath provenance has an unexpected or duplicate library")
        seen.add(name)
        original = BOOT_ORIGINAL[Path(name).name]
        if any(record.get(key) != value for key, value in original.items()):
            raise RuntimeError(f"bootclasspath provenance has a different source library: {name}")
        if (any(type(record.get(key)) is not int for key in (
                "size", "classes_before", "classes_after", "bootstrap_callsites_before", "bootstrap_callsites_after"))
                or record["size"] < 0 or record["bootstrap_callsites_after"] != 0
                or record["classes_after"] < record["classes_before"]):
            raise RuntimeError(f"bootclasspath provenance lost classes or retained bootstrap calls: {name}")
        if records is not None and (name not in records or any(
                records[name].get(key) != record.get(key) for key in ("sha256", "size"))):
            raise RuntimeError(f"bootclasspath receipt does not match the ART payload: {name}")
        path = root / name
        parent = root
        if parent.is_symlink():
            raise RuntimeError(f"bootclasspath payload must not use symlinks: {name}")
        for part in Path(name).parts:
            parent = parent / part
            if parent.is_symlink():
                raise RuntimeError(f"bootclasspath payload must not use symlinks: {name}")
        if (not path.is_file() or path.stat().st_size != record["size"]
                or digest(path) != record.get("sha256")):
            raise RuntimeError(f"bootclasspath payload checksum mismatch: {name}")
        try:
            classes, callsites = jar_info(path)
        except (ValueError, UnicodeError, zipfile.BadZipFile) as error:
            raise RuntimeError(f"invalid bootclasspath payload: {name}") from error
        if len(classes) != record["classes_after"] or callsites != 0:
            raise RuntimeError(f"bootclasspath DEX does not match its compiler receipt: {name}")


def prepare(build_dir: Path, java: str = "java") -> tuple[Path, dict]:
    build_dir.mkdir(parents=True, exist_ok=True)
    downloads = build_dir / "downloads"
    downloads.mkdir(exist_ok=True)
    archives = [download(record, downloads) for record in INPUTS]
    key = hashlib.sha256(json.dumps(INPUTS, sort_keys=True).encode()
                         + Path(__file__).read_bytes()).hexdigest()
    cache = build_dir / "bootclasspath-runtime-manifest.json"
    jars = build_dir / "jars"
    if cache.is_file():
        try:
            previous = json.loads(cache.read_text())
            validate_provenance(jars, previous)
            if previous["input_key"] == key:
                return jars, previous
        except (RuntimeError, ValueError, OSError):
            pass
    work = build_dir / "work"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    raw = work / "core-all_classes.jar"
    extract_member(archives[1], JAVA_CLASS_JAR, raw)
    version = subprocess.check_output([java, "-cp", str(archives[2]),
                                       "com.android.tools.r8.D8", "--version"], text=True).strip()
    next_jars = build_dir / "jars.next"
    if next_jars.exists():
        shutil.rmtree(next_jars)
    destination = next_jars / BOOT_DIRECTORY
    destination.mkdir(parents=True)
    files = []
    for name in BOOT_JARS:
        original = work / name
        extract_member(archives[0], BOOT_DIRECTORY + "/" + name, original)
        classes, before = jar_info(original)
        inputs = work / (name + ".classes.jar")
        class_subset(raw, classes, inputs)
        dex_directory = work / (name + ".dex")
        dex_directory.mkdir()
        subprocess.run([java, "-cp", str(archives[2]), "com.android.tools.r8.D8",
                        *COMPILER_ARGUMENTS, "--lib", str(raw), "--output", str(dex_directory),
                        str(inputs)], check=True)
        output = destination / name
        package_jar(original, dex_directory, output)
        generated, after = jar_info(output)
        if after != 0 or not classes <= generated:
            raise RuntimeError(f"desugared bootclasspath lost classes or retained bootstrap calls: {name}")
        files.append({"path": BOOT_DIRECTORY + "/" + name,
                      "sha256": digest(output), "size": output.stat().st_size,
                      "original_sha256": digest(original), "classes_before": len(classes),
                      "classes_after": len(generated), "bootstrap_callsites_before": before,
                      "bootstrap_callsites_after": after})
    manifest = {"format": 1, "input_key": key, "compiler": version,
                "compiler_arguments": COMPILER_ARGUMENTS, "inputs": list(INPUTS), "files": files}
    validate_provenance(next_jars, manifest)
    if jars.exists():
        shutil.rmtree(jars)
    next_jars.replace(jars)
    next_cache = cache.with_suffix(".json.next")
    next_cache.write_text(json.dumps(manifest, indent=2) + "\n")
    next_cache.replace(cache)
    return jars, manifest


def stage(build_dir: Path, overlay: Path, java: str = "java") -> dict:
    specification = importlib.util.spec_from_file_location("art_runtime", SUPPORT / "art-runtime.py")
    art = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(art)
    manifest = art.read_manifest(overlay)
    jars, provenance = prepare(build_dir, java)
    replaced = {record["path"] for record in provenance["files"]}
    records = [record for record in manifest["files"] if record["path"] not in replaced]
    # Keep replacement JARs separate from hardlinked package files.
    for record in provenance["files"]:
        target = art._inside(overlay, art._relative(record["path"]))
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(prefix=".vinix-art-java-", dir=target.parent, delete=False) as output:
                temporary = Path(output.name)
                with (jars / record["path"]).open("rb") as source:
                    shutil.copyfileobj(source, output)
            if digest(temporary) != record["sha256"]:
                raise RuntimeError(f"bootclasspath cache changed during staging: {record['path']}")
            temporary.chmod(0o644)
            os.replace(temporary, target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        records.append({key: record[key] for key in ("path", "sha256", "size")})
    manifest["files"] = sorted(records, key=lambda record: record["path"])
    manifest["bootclasspath"] = provenance
    path = overlay / art.MANIFEST
    temporary = path.with_suffix(".json.next")
    temporary.write_text(json.dumps(manifest, indent=2) + "\n")
    temporary.replace(path)
    return art.read_manifest(overlay)


def build_probe(build_dir: Path, output: Path, java: str = "java", javac: str = "javac") -> None:
    """Compile the native guest Java-library probe with the same pinned D8."""
    prepare(build_dir, java)
    directory = build_dir / "probe"
    if directory.exists():
        shutil.rmtree(directory)
    classes, dex = directory / "classes", directory / "dex"
    classes.mkdir(parents=True)
    dex.mkdir()
    raw = directory / "core-all_classes.jar"
    extract_member(build_dir / "downloads" / INPUTS[1]["filename"], JAVA_CLASS_JAR, raw)
    source = SUPPORT.parents[1] / "tests/android/ArtBootProbe.java"
    subprocess.run([javac, "--release", "8", "-d", str(classes), str(source)], check=True)
    inputs = directory / "classes.jar"
    with zipfile.ZipFile(inputs, "w") as archive:
        for path in sorted(classes.rglob("*.class")):
            archive.write(path, str(path.relative_to(classes)))
    subprocess.run([java, "-cp", str(build_dir / "downloads" / INPUTS[2]["filename"]),
                    "com.android.tools.r8.D8", "--release", "--min-api", "26", "--lib", str(raw),
                    "--output", str(dex), str(inputs)], check=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w") as archive:
        for path in sorted(dex.glob("*.dex")):
            archive.write(path, path.name)
    jar_info(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--art-runtime", type=Path, required=True)
    parser.add_argument("--java", default=os.environ.get("VINIX_ANDROID_BUILD_JAVA", "java"))
    parser.add_argument("--build-probe", type=Path, help="also compile the native Java-library test JAR")
    parser.add_argument("--javac", default=os.environ.get("VINIX_ANDROID_BUILD_JAVAC", "javac"))
    args = parser.parse_args()
    manifest = stage(args.build_dir.resolve(), args.art_runtime.resolve(), args.java)
    if args.build_probe:
        build_probe(args.build_dir.resolve(), args.build_probe.resolve(), args.java, args.javac)
    print("Desugared ART boot libraries; "
          + ", ".join(record["path"] for record in manifest["bootclasspath"]["files"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
