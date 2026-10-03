#!/bin/sh
# Build ART for Vinix's native ARM64 16 KiB memory ABI on an ARM64 musl host.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
COMMIT=e78bf68917bcaaf58fef3960cd88793b3b7f39cc
SOURCE_URL="https://gitlab.com/android_translation_layer/art_standalone/-/archive/$COMMIT/art_standalone-$COMMIT.tar.gz"
SOURCE_SHA512=75ef56d63dfc7661a7928191441d4672d612b6a8d27c3957764d324e4f622a42c132c34540f6a89556b1971964df8be2eced0b8a599d5a793ab3039cfb9c48a2
BUILD_DIR=${VINIX_ANDROID_ART_BUILD_DIR:-$REPO_DIR/build-aarch64-android/aarch64/art-build}
OUTPUT_DIR=${VINIX_ANDROID_ART_RUNTIME:-$REPO_DIR/build-aarch64-android/aarch64/art-runtime}
JOBS=${VINIX_ANDROID_ART_JOBS:-}
SOURCE_ARCHIVE=
DEPENDENCY_CACHE=${VINIX_ANDROID_ART_DEPENDENCY_CACHE:-/var/cache/apk}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR=$2; shift 2 ;;
        --output) OUTPUT_DIR=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --source-archive) SOURCE_ARCHIVE=$2; shift 2 ;;
        --dependency-cache) DEPENDENCY_CACHE=$2; shift 2 ;;
        --help|-h)
            echo "usage: $0 [--build-dir DIR] [--output DIR] [--jobs N] [--source-archive FILE]"
            echo "Run on native ARM64 Alpine Linux with ART's build dependencies installed."
            exit 0
            ;;
        *) echo "build-art: unknown option: $1" >&2; exit 2 ;;
    esac
done
case "$(uname -s):$(uname -m)" in
    Linux:aarch64|Linux:arm64) ;;
    *) echo "build-art: this build requires a native ARM64 Linux host" >&2; exit 2 ;;
esac
for command in python3 curl make patch gcc g++ strip tar; do
    command -v "$command" >/dev/null || { echo "build-art: missing tool: $command" >&2; exit 2; }
done
case "$(gcc -dumpmachine)" in
    aarch64*musl*) ;;
    *) echo "build-art: use an ARM64 musl toolchain (Alpine Linux), matching Vinix" >&2; exit 2 ;;
esac
if [ -z "$JOBS" ]; then
    JOBS=$(getconf _NPROCESSORS_ONLN)
fi
case "$JOBS" in
    ''|*[!0-9]*|0) echo "build-art: --jobs must be a positive integer" >&2; exit 2 ;;
esac
mkdir -p "$BUILD_DIR" "$(dirname -- "$OUTPUT_DIR")"
BUILD_DIR=$(CDPATH= cd -- "$BUILD_DIR" && pwd)
OUTPUT_PARENT=$(CDPATH= cd -- "$(dirname -- "$OUTPUT_DIR")" && pwd)
OUTPUT_DIR="$OUTPUT_PARENT/$(basename -- "$OUTPUT_DIR")"
if [ -z "$SOURCE_ARCHIVE" ]; then
    SOURCE_ARCHIVE="$BUILD_DIR/art_standalone-$COMMIT.tar.gz"
    if [ ! -f "$SOURCE_ARCHIVE" ]; then
        curl --fail --location --silent --show-error --retry 3 \
            --output "$SOURCE_ARCHIVE.part" "$SOURCE_URL"
        mv "$SOURCE_ARCHIVE.part" "$SOURCE_ARCHIVE"
    fi
fi
SOURCE_ARCHIVE=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$SOURCE_ARCHIVE")
python3 - "$SOURCE_ARCHIVE" "$SOURCE_SHA512" <<'PY'
import hashlib, pathlib, sys
archive = pathlib.Path(sys.argv[1])
if hashlib.sha512(archive.read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit(f"build-art: pinned ART source checksum mismatch: {archive}")
PY

SOURCE_DIR="$BUILD_DIR/art_standalone-$COMMIT"
INPUT_KEY=$(python3 - "$SOURCE_SHA512" "$SCRIPT_DIR/art16k.patch" "$0" <<'PY'
import hashlib, pathlib, sys
digest = hashlib.sha256(sys.argv[1].encode())
for filename in sys.argv[2:]:
    digest.update(pathlib.Path(filename).read_bytes())
print(digest.hexdigest())
PY
)
if [ ! -f "$SOURCE_DIR/.vinix-art-inputs" ] || \
   [ "$(cat "$SOURCE_DIR/.vinix-art-inputs")" != "$INPUT_KEY" ]; then
    rm -rf "$SOURCE_DIR"
    tar -xzf "$SOURCE_ARCHIVE" -C "$BUILD_DIR"
    (cd "$SOURCE_DIR" && patch --batch --fuzz=0 -p1 < "$SCRIPT_DIR/art16k.patch")
    printf '%s\n' "$INPUT_KEY" > "$SOURCE_DIR/.vinix-art-inputs"
fi
BUILDSPEC="$BUILD_DIR/art16k-buildspec.mk"
printf '%s\n' \
    'COMMON_GLOBAL_CFLAGS += -DART_PAGE_SIZE=16384' \
    'COMMON_GLOBAL_CPPFLAGS += -DART_PAGE_SIZE=16384' > "$BUILDSPEC"
export SOURCE_DATE_EPOCH=1759985629

# Use host output targets: some upstream module aliases also pull in obsolete
# Android device targets. ART calls this directory linux-x86 even on ARM64.
ART_LIBRARIES='libandroidfw libart libart-compiler libart-dexlayout libartbase libartpalette libbacktrace libbase libcutils libdexfile liblog libnativebridge libprofile libsigchain libunwind libutils libziparchive'
JNI_LIBRARIES='libjavacore libnativehelper libopenjdk libopenjdkjvm'
set --
for library in $ART_LIBRARIES $JNI_LIBRARIES; do
    set -- "$@" "out/host/linux-x86/lib64/$library.so"
done
set -- "$@" out/host/linux-x86/bin/dalvikvm out/host/linux-x86/bin/dex2oat
echo "Building native ARM64 ART with 16 KiB pages in $SOURCE_DIR"
(cd "$SOURCE_DIR" && make -j"$JOBS" ____PREFIX=/usr ____LIBDIR=lib \
    ANDROID_BUILDSPEC="$BUILDSPEC" ART_BUILD_HOST_DEBUG=false "$@")

NEXT_OUTPUT="$OUTPUT_DIR.next"
rm -rf "$NEXT_OUTPUT"
mkdir -p "$NEXT_OUTPUT/usr/lib/art" "$NEXT_OUTPUT/usr/lib/java/dex/art/natives" "$NEXT_OUTPUT/usr/bin"
for library in $ART_LIBRARIES; do
    cp "$SOURCE_DIR/out/host/linux-x86/lib64/$library.so" "$NEXT_OUTPUT/usr/lib/art/"
done
for library in $JNI_LIBRARIES; do
    cp "$SOURCE_DIR/out/host/linux-x86/lib64/$library.so" "$NEXT_OUTPUT/usr/lib/java/dex/art/natives/"
done
cp "$SOURCE_DIR/out/host/linux-x86/bin/dalvikvm" "$NEXT_OUTPUT/usr/bin/"
cp "$SOURCE_DIR/out/host/linux-x86/bin/dex2oat" "$NEXT_OUTPUT/usr/bin/"
find "$NEXT_OUTPUT/usr" -type f -exec strip --strip-unneeded '{}' \;
python3 - "$NEXT_OUTPUT" "$COMMIT" "$SOURCE_URL" "$SOURCE_ARCHIVE" \
    "$SCRIPT_DIR/art16k.patch" "$DEPENDENCY_CACHE" <<'PY'
import hashlib, json, pathlib, struct, subprocess, sys
output, commit, url, archive, patch, cache = sys.argv[1:]
root = pathlib.Path(output)
files = []
for path in sorted((root / "usr").rglob("*")):
    if not path.is_file():
        continue
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", data, 18)[0] != 183:
        raise SystemExit(f"build-art: output is not an ARM64 ELF: {path}")
    offset = struct.unpack_from("<Q", data, 32)[0]
    entry_size, count = struct.unpack_from("<HH", data, 54)
    if (entry_size != 56 or count == 0 or offset > len(data)
            or count * entry_size > len(data) - offset):
        raise SystemExit(f"build-art: invalid ELF program headers: {path}")
    loads = 0
    for index in range(count):
        kind, _, file_offset, address, _, file_size, memory_size, _ = struct.unpack_from(
            "<IIQQQQQQ", data, offset + index * entry_size)
        if kind != 1:
            continue
        loads += 1
        if (file_size > memory_size or file_offset > len(data)
                or file_size > len(data) - file_offset
                or memory_size > (1 << 64) - 1 - address
                or address % 16384 != file_offset % 16384):
            raise SystemExit(f"build-art: output cannot load with 16 KiB pages: {path}")
    if loads == 0:
        raise SystemExit(f"build-art: output has no loadable segments: {path}")
    files.append({"path": str(path.relative_to(root)), "size": len(data),
                  "sha256": hashlib.sha256(data).hexdigest()})
package_versions = []
try:
    package_versions = subprocess.check_output(["apk", "list", "--installed"], text=True).splitlines()
except (OSError, subprocess.CalledProcessError):
    pass
dependency_archives = []
for path in sorted(pathlib.Path(cache).glob("*.apk")):
    dependency_archives.append({"filename": path.name,
                                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
source = pathlib.Path(archive).read_bytes()
manifest = {"format": 1, "architecture": "aarch64", "page_size": 16384,
            "source_commit": commit, "source_url": url,
            "source_sha512": hashlib.sha512(source).hexdigest(),
            "source_sha256": hashlib.sha256(source).hexdigest(),
            "patch_sha256": hashlib.sha256(pathlib.Path(patch).read_bytes()).hexdigest(),
            "build_flags": ["-DART_PAGE_SIZE=16384", "ART_BUILD_HOST_DEBUG=false"],
            "compiler": subprocess.check_output(["gcc", "--version"], text=True).splitlines()[0],
            "compiler_target": subprocess.check_output(["gcc", "-dumpmachine"], text=True).strip(),
            "source_date_epoch": 1759985629, "build_packages": package_versions,
            "dependency_archives": dependency_archives, "files": files}
(root / "art-runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Verified {len(files)} native ARM64 ELF outputs")
PY
rm -rf "$OUTPUT_DIR"
mv "$NEXT_OUTPUT" "$OUTPUT_DIR"
echo "Staged native 16 KiB ART overlay in $OUTPUT_DIR"
