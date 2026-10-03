#!/bin/sh
# Build a coherent native ARM64 Android Translation Layer framework.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
COMMIT=aa80e7405436fb4b442b7c90abefd2d526f8543a
SOURCE_URL="https://gitlab.com/android_translation_layer/android_translation_layer/-/archive/$COMMIT/android_translation_layer-$COMMIT.tar.gz"
SOURCE_SHA512=3e274fd63f3eec25fd83efddc8c5135c494bb978c0a481a75ca703779e63a85ffe8d50047d73a29fdf68a4fb08c0c283339517afe8f82214e289b64037e88221
BUILD_DIR=${VINIX_ANDROID_ATL_BUILD_DIR:-$REPO_DIR/build-aarch64-android/aarch64/atl-build}
OUTPUT_DIR=${VINIX_ANDROID_ATL_RUNTIME:-$REPO_DIR/build-aarch64-android/aarch64/atl-runtime}
DEPENDENCY_CACHE=${VINIX_ANDROID_ATL_DEPENDENCY_CACHE:-/var/cache/apk}
JOBS=${VINIX_ANDROID_ATL_JOBS:-2}
SOURCE_ARCHIVE=
R8_ARCHIVE=
CORE_CLASSES=/usr/lib/java/core-all_classes.jar
ART_RUNTIME=${VINIX_ANDROID_ART_RUNTIME:-$REPO_DIR/build-aarch64-android/aarch64/art-runtime}
JAVA_D8=${VINIX_ATL_JAVA_D8:-java}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR=$2; shift 2 ;;
        --output) OUTPUT_DIR=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --source-archive) SOURCE_ARCHIVE=$2; shift 2 ;;
        --r8) R8_ARCHIVE=$2; shift 2 ;;
        --java) JAVA_D8=$2; shift 2 ;;
        --core-classes) CORE_CLASSES=$2; shift 2 ;;
        --art-runtime) ART_RUNTIME=$2; shift 2 ;;
        --dependency-cache) DEPENDENCY_CACHE=$2; shift 2 ;;
        --help|-h)
            echo "usage: $0 [--build-dir DIR] [--output DIR] [--jobs N] [--source-archive FILE] [--r8 FILE] [--art-runtime DIR]"
            echo "Run on native ARM64 Alpine Linux with ATL's build dependencies installed."
            exit 0 ;;
        *) echo "build-atl: unknown option: $1" >&2; exit 2 ;;
    esac
done
case "$(uname -s):$(uname -m)" in
    Linux:aarch64|Linux:arm64) ;;
    *) echo "build-atl: this build requires a native ARM64 Linux host" >&2; exit 2 ;;
esac
for command in python3 curl gcc g++ strip tar patch meson java javac; do
    command -v "$command" >/dev/null || { echo "build-atl: missing tool: $command" >&2; exit 2; }
done
case "$(gcc -dumpmachine)" in
    aarch64*musl*) ;;
    *) echo "build-atl: use an ARM64 musl toolchain (Alpine Linux), matching Vinix" >&2; exit 2 ;;
esac
case "$JOBS" in
    ''|*[!0-9]*|0) echo "build-atl: --jobs must be a positive integer" >&2; exit 2 ;;
esac
mkdir -p "$BUILD_DIR" "$(dirname -- "$OUTPUT_DIR")"
BUILD_DIR=$(CDPATH= cd -- "$BUILD_DIR" && pwd)
OUTPUT_PARENT=$(CDPATH= cd -- "$(dirname -- "$OUTPUT_DIR")" && pwd)
OUTPUT_DIR="$OUTPUT_PARENT/$(basename -- "$OUTPUT_DIR")"
if [ -z "$SOURCE_ARCHIVE" ]; then
    SOURCE_ARCHIVE="$BUILD_DIR/android_translation_layer-$COMMIT.tar.gz"
    if [ ! -f "$SOURCE_ARCHIVE" ]; then
        curl --fail --location --silent --show-error --retry 3 --output "$SOURCE_ARCHIVE.part" "$SOURCE_URL"
        mv "$SOURCE_ARCHIVE.part" "$SOURCE_ARCHIVE"
    fi
fi
if [ -z "$R8_ARCHIVE" ]; then
    R8_ARCHIVE="$BUILD_DIR/r8-8.3.37.jar"
    if [ ! -f "$R8_ARCHIVE" ]; then
        curl --fail --location --silent --show-error --retry 3 --output "$R8_ARCHIVE.part" \
            https://storage.googleapis.com/r8-releases/raw/8.3.37/r8.jar
        mv "$R8_ARCHIVE.part" "$R8_ARCHIVE"
    fi
fi
SOURCE_ARCHIVE=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$SOURCE_ARCHIVE")
R8_ARCHIVE=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$R8_ARCHIVE")
CORE_CLASSES=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$CORE_CLASSES")
ART_RUNTIME=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$ART_RUNTIME")
python3 - "$SCRIPT_DIR/art-runtime.py" "$ART_RUNTIME" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("art_runtime", sys.argv[1])
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)
art.read_manifest(pathlib.Path(sys.argv[2]))
PY
python3 - "$SOURCE_ARCHIVE" "$SOURCE_SHA512" "$R8_ARCHIVE" "$CORE_CLASSES" <<'PY'
import hashlib, pathlib, sys
archive, expected, r8, core = sys.argv[1:]
if hashlib.sha512(pathlib.Path(archive).read_bytes()).hexdigest() != expected:
    raise SystemExit("build-atl: pinned source checksum mismatch")
for name, expected in ((r8, "900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199"),
                       (core, "f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42")):
    if hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest() != expected:
        raise SystemExit(f"build-atl: pinned compiler input checksum mismatch: {name}")
PY
SOURCE_DIR="$BUILD_DIR/android_translation_layer-$COMMIT"
INPUT_KEY=$(python3 - "$SOURCE_SHA512" "$ART_RUNTIME" "$0" "$SCRIPT_DIR/atl-dex.py" "$SCRIPT_DIR/atl-configuration.patch" "$SCRIPT_DIR/atl-configuration-test.c" "$ART_RUNTIME/art-runtime-manifest.json" <<'PY'
import hashlib, pathlib, sys
digest = hashlib.sha256(sys.argv[1].encode())
# Meson records absolute include/provider paths as well as their contents.
digest.update(sys.argv[2].encode())
for filename in sys.argv[3:]:
    digest.update(pathlib.Path(filename).read_bytes())
print(digest.hexdigest())
PY
)
if [ ! -f "$SOURCE_DIR/.vinix-atl-inputs" ] || [ "$(cat "$SOURCE_DIR/.vinix-atl-inputs")" != "$INPUT_KEY" ]; then
    rm -rf "$SOURCE_DIR"
    tar -xzf "$SOURCE_ARCHIVE" -C "$BUILD_DIR"
    (cd "$SOURCE_DIR" && patch --batch --fuzz=0 -p1 < "$SCRIPT_DIR/atl-configuration.patch")
    printf '%s\n' "$INPUT_KEY" > "$SOURCE_DIR/.vinix-atl-inputs"
fi
export SOURCE_DATE_EPOCH=1790718764
export VINIX_ATL_R8="$R8_ARCHIVE" VINIX_ATL_CORE_CLASSES="$CORE_CLASSES" VINIX_ATL_JAVA_D8="$JAVA_D8"
"$JAVA_D8" -cp "$R8_ARCHIVE" com.android.tools.r8.D8 --version
# Meson calls dx for DEX generation; the local adapter uses pinned D8 for
# all framework jars, lowering Java lambdas for ART's implemented boot APIs.
mkdir -p "$BUILD_DIR/tools"
printf '%s\n' '#!/bin/sh' 'exec python3 "'"$SCRIPT_DIR"'/atl-dex.py" "$@"' > "$BUILD_DIR/tools/dx"
chmod +x "$BUILD_DIR/tools/dx"
export PATH="$BUILD_DIR/tools:$PATH"
BUILD_OUTPUT="$SOURCE_DIR/output"
if [ ! -f "$BUILD_OUTPUT/build.ninja" ]; then
    COMPILE_ARGS=$(python3 -c 'import json,sys; print(json.dumps(["-I" + sys.argv[1] + "/usr/include"]))' "$ART_RUNTIME")
    LINK_ARGS=$(python3 -c 'import json,sys; print(json.dumps(["-Wl,-z,max-page-size=65536", "-L" + sys.argv[1] + "/usr/lib/art", "-Wl,-rpath-link," + sys.argv[1] + "/usr/lib/art", "-landroidfw"]))' "$ART_RUNTIME")
    meson setup "$BUILD_OUTPUT" "$SOURCE_DIR" --prefix /usr --libdir lib --buildtype release \
        "-Dc_args=$COMPILE_ARGS" "-Dc_link_args=$LINK_ARGS"
fi
echo "Building native ARM64 ATL $COMMIT in $SOURCE_DIR"
meson compile -C "$BUILD_OUTPUT" -j "$JOBS"
INSTALL_ROOT="$BUILD_DIR/install"
rm -rf "$INSTALL_ROOT"
meson install -C "$BUILD_OUTPUT" --no-rebuild --destdir "$INSTALL_ROOT"
NEXT_OUTPUT="$OUTPUT_DIR.next"
rm -rf "$NEXT_OUTPUT"
mkdir -p "$NEXT_OUTPUT"
python3 - "$INSTALL_ROOT" "$NEXT_OUTPUT" <<'PY'
import pathlib, shutil, sys
source, output = map(pathlib.Path, sys.argv[1:])
for path in sorted((source / "usr").rglob("*")):
    if path.is_file():
        target = output / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target, follow_symlinks=True)
PY
# Verify the production configuration object against the real selected
# androidfw provider. Loading all of libandroid requires launcher globals and
# a desktop; its freshly compiled configuration object needs neither.
CONFIGURATION_TEST="$NEXT_OUTPUT/usr/libexec/vinix-android/atl-configuration-test"
mkdir -p "$(dirname -- "$CONFIGURATION_TEST")"
gcc -O2 -Wall -Wextra -Werror -Wl,-z,max-page-size=65536 -I"$ART_RUNTIME/usr/include" \
    "$SCRIPT_DIR/atl-configuration-test.c" -o "$CONFIGURATION_TEST" \
    "$BUILD_OUTPUT/libandroid.so.0.p/src_libandroid_configuration.c.o" \
    -L"$ART_RUNTIME/usr/lib/art" -landroidfw -lpng -Wl,-rpath-link,"$ART_RUNTIME/usr/lib/art"
LD_LIBRARY_PATH="$ART_RUNTIME/usr/lib/art${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$CONFIGURATION_TEST"
python3 - "$NEXT_OUTPUT" "$COMMIT" "$SOURCE_URL" "$SOURCE_ARCHIVE" "$R8_ARCHIVE" \
    "$CORE_CLASSES" "$SCRIPT_DIR/atl-dex.py" "$0" "$DEPENDENCY_CACHE" \
    "$SCRIPT_DIR/atl-configuration.patch" "$SCRIPT_DIR/art16k.patch" \
    "$ART_RUNTIME" "$SCRIPT_DIR/atl-configuration-test.c" <<'PY'
import hashlib, json, os, pathlib, struct, subprocess, sys, zipfile
output, commit, url, archive, r8, core, adapter, builder, cache, patch, art_patch, art_runtime, probe = sys.argv[1:]
root = pathlib.Path(output)
files = []
for path in sorted((root / "usr").rglob("*")):
    if not path.is_file():
        continue
    data = path.read_bytes()
    kind = "data"
    if data.startswith(b"\x7fELF"):
        kind = "elf"
        subprocess.run(["strip", "--strip-unneeded", str(path)], check=True)
        data = path.read_bytes()
        if data[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", data, 18)[0] != 183:
            raise SystemExit(f"build-atl: output is not an ARM64 ELF: {path}")
        offset = struct.unpack_from("<Q", data, 32)[0]
        entry_size, count = struct.unpack_from("<HH", data, 54)
        if entry_size != 56 or count == 0 or offset > len(data) or count * entry_size > len(data) - offset:
            raise SystemExit(f"build-atl: invalid ELF headers: {path}")
        loads = 0
        for index in range(count):
            ptype, _, file_offset, address, _, file_size, memory_size, _ = struct.unpack_from(
                "<IIQQQQQQ", data, offset + index * entry_size)
            if ptype != 1:
                continue
            loads += 1
            if (file_size > memory_size or file_offset > len(data) or file_size > len(data) - file_offset
                    or memory_size > (1 << 64) - 1 - address or address % 16384 != file_offset % 16384):
                raise SystemExit(f"build-atl: output cannot load with 16 KiB pages: {path}")
        if not loads:
            raise SystemExit(f"build-atl: no loadable segments: {path}")
    record = {"path": str(path.relative_to(root)), "kind": kind, "size": len(data),
              "sha256": hashlib.sha256(data).hexdigest()}
    if path.suffix == ".jar":
        record["kind"] = "dex"
        classes = 0
        callsites = 0
        with zipfile.ZipFile(path) as jar:
            for name in jar.namelist():
                if not name.endswith(".dex"):
                    continue
                dex = jar.read(name)
                if not dex.startswith(b"dex\n") or len(dex) < 112:
                    raise SystemExit(f"build-atl: invalid framework DEX: {path}")
                classes += struct.unpack_from("<I", dex, 96)[0]
                offset = struct.unpack_from("<I", dex, 52)[0]
                if offset > len(dex) - 4:
                    raise SystemExit(f"build-atl: invalid DEX map: {path}")
                count = struct.unpack_from("<I", dex, offset)[0]
                if count * 12 > len(dex) - offset - 4:
                    raise SystemExit(f"build-atl: truncated DEX map: {path}")
                for index in range(count):
                    item_type, _, size, _ = struct.unpack_from("<HHII", dex, offset + 4 + index * 12)
                    if item_type == 7:
                        callsites += size
        if not classes or callsites:
            raise SystemExit(f"build-atl: framework has missing classes or Java bootstrap calls: {path}")
        record["class_count"] = classes
        record["bootstrap_callsites"] = callsites
    files.append(record)
digest = lambda name: hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()
source = pathlib.Path(archive).read_bytes()
manifest = {"format": 1, "architecture": "aarch64", "page_size": 16384,
            "source_commit": commit, "source_url": url,
            "source_sha512": hashlib.sha512(source).hexdigest(),
            "source_sha256": hashlib.sha256(source).hexdigest(),
            "patch_sha256": digest(patch), "androidfw_patch_sha256": digest(art_patch),
            "androidfw_configuration_api": 1,
            "androidfw_header_sha256": digest(pathlib.Path(art_runtime) / "usr/include/androidfw/androidfw_c_api.h"),
            "androidfw_library_sha256": digest(pathlib.Path(art_runtime) / "usr/lib/art/libandroidfw.so"),
            "configuration_probe_sha256": digest(probe),
            "build_flags": ["--buildtype=release", "-Wl,-z,max-page-size=65536"],
            "builder_sha256": digest(builder), "dex_adapter_sha256": digest(adapter),
            "dex_compiler_sha256": digest(r8), "java_core_classes_sha256": digest(core),
            "dex_compiler_arguments": ["--release", "--min-api", "26", "--android-platform-build",
                                       "--force-passthrough-assertions"],
            "dex_compiler": subprocess.check_output([os.environ["VINIX_ATL_JAVA_D8"], "-cp", r8, "com.android.tools.r8.D8", "--version"], text=True).strip(),
            "compiler": subprocess.check_output(["gcc", "--version"], text=True).splitlines()[0],
            "compiler_target": subprocess.check_output(["gcc", "-dumpmachine"], text=True).strip(),
            "source_date_epoch": 1790718764,
            "build_packages": subprocess.check_output(["apk", "list", "--installed"], text=True).splitlines(),
            "dependency_archives": [{"filename": path.name, "sha256": digest(path)}
                                    for path in sorted(pathlib.Path(cache).glob("*.apk"))],
            "files": files}
(root / "atl-runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Verified {len(files)} coherent native ATL outputs")
PY
rm -rf "$OUTPUT_DIR"
mv "$NEXT_OUTPUT" "$OUTPUT_DIR"
echo "Staged native ATL overlay in $OUTPUT_DIR"
