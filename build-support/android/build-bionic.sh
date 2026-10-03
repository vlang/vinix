#!/bin/sh
# Build the APK native-library loader for Vinix's ARM64 16 KiB memory ABI.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
COMMIT=ee37eb21c91409fe0eed833d0a5a0aa6b931bb7b
SOURCE_URL="https://gitlab.com/android_translation_layer/bionic_translation/-/archive/$COMMIT/bionic_translation-$COMMIT.tar.gz"
SOURCE_SHA512=713f3a7c147e06781eb60f352d2c801b1b661e52bd33aa627ec1bbcb3587f15af33393f8068d9e341f6869777ac008bee6c8ef8a26f0826049a9fa226dcdbeac
BUILD_DIR=${VINIX_ANDROID_BIONIC_BUILD_DIR:-$REPO_DIR/build-aarch64-android/aarch64/bionic-build}
OUTPUT_DIR=${VINIX_ANDROID_BIONIC_RUNTIME:-$REPO_DIR/build-aarch64-android/aarch64/bionic-runtime}
DEPENDENCY_CACHE=${VINIX_ANDROID_BIONIC_DEPENDENCY_CACHE:-/var/cache/apk}
JOBS=${VINIX_ANDROID_BIONIC_JOBS:-2}
SOURCE_ARCHIVE=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR=$2; shift 2 ;;
        --output) OUTPUT_DIR=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --source-archive) SOURCE_ARCHIVE=$2; shift 2 ;;
        --dependency-cache) DEPENDENCY_CACHE=$2; shift 2 ;;
        --help|-h)
            echo "usage: $0 [--build-dir DIR] [--output DIR] [--jobs N] [--source-archive FILE]"
            echo "Run on native ARM64 Alpine Linux with bionic_translation's build dependencies installed."
            exit 0
            ;;
        *) echo "build-bionic: unknown option: $1" >&2; exit 2 ;;
    esac
done
case "$(uname -s):$(uname -m)" in
    Linux:aarch64|Linux:arm64) ;;
    *) echo "build-bionic: this build requires a native ARM64 Linux host" >&2; exit 2 ;;
esac
for command in python3 curl patch gcc g++ strip tar meson; do
    command -v "$command" >/dev/null || { echo "build-bionic: missing tool: $command" >&2; exit 2; }
done
case "$(gcc -dumpmachine)" in
    aarch64*musl*) ;;
    *) echo "build-bionic: use an ARM64 musl toolchain (Alpine Linux), matching Vinix" >&2; exit 2 ;;
esac
case "$JOBS" in
    ''|*[!0-9]*|0) echo "build-bionic: --jobs must be a positive integer" >&2; exit 2 ;;
esac
mkdir -p "$BUILD_DIR" "$(dirname -- "$OUTPUT_DIR")"
BUILD_DIR=$(CDPATH= cd -- "$BUILD_DIR" && pwd)
OUTPUT_PARENT=$(CDPATH= cd -- "$(dirname -- "$OUTPUT_DIR")" && pwd)
OUTPUT_DIR="$OUTPUT_PARENT/$(basename -- "$OUTPUT_DIR")"
if [ -z "$SOURCE_ARCHIVE" ]; then
    SOURCE_ARCHIVE="$BUILD_DIR/bionic_translation-$COMMIT.tar.gz"
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
    raise SystemExit(f"build-bionic: pinned source checksum mismatch: {archive}")
PY
SOURCE_DIR="$BUILD_DIR/bionic_translation-$COMMIT"
INPUT_KEY=$(python3 - "$SOURCE_SHA512" "$SCRIPT_DIR/bionic16k.patch" "$0" <<'PY'
import hashlib, pathlib, sys
digest = hashlib.sha256(sys.argv[1].encode())
for filename in sys.argv[2:]:
    digest.update(pathlib.Path(filename).read_bytes())
print(digest.hexdigest())
PY
)
if [ ! -f "$SOURCE_DIR/.vinix-bionic-inputs" ] || \
   [ "$(cat "$SOURCE_DIR/.vinix-bionic-inputs")" != "$INPUT_KEY" ]; then
    rm -rf "$SOURCE_DIR"
    tar -xzf "$SOURCE_ARCHIVE" -C "$BUILD_DIR"
    (cd "$SOURCE_DIR" && patch --batch --fuzz=0 -p1 < "$SCRIPT_DIR/bionic16k.patch")
    printf '%s\n' "$INPUT_KEY" > "$SOURCE_DIR/.vinix-bionic-inputs"
fi
export SOURCE_DATE_EPOCH=1773705600
BUILD_OUTPUT="$SOURCE_DIR/output"
if [ ! -f "$BUILD_OUTPUT/build.ninja" ]; then
    meson setup "$BUILD_OUTPUT" "$SOURCE_DIR" --prefix /usr --libdir lib \
        --buildtype release -Dc_args=-DBIONIC_PAGE_SIZE=16384 \
        -Dcpp_args=-DBIONIC_PAGE_SIZE=16384 \
        -Dc_link_args=-Wl,-z,max-page-size=65536 \
        -Dcpp_link_args=-Wl,-z,max-page-size=65536
fi
echo "Building native ARM64 bionic loader with 16 KiB pages in $SOURCE_DIR"
meson compile -C "$BUILD_OUTPUT" -j "$JOBS"
INSTALL_ROOT="$BUILD_DIR/install"
rm -rf "$INSTALL_ROOT"
meson install -C "$BUILD_OUTPUT" --no-rebuild --destdir "$INSTALL_ROOT"
NEXT_OUTPUT="$OUTPUT_DIR.next"
rm -rf "$NEXT_OUTPUT"
mkdir -p "$NEXT_OUTPUT/usr/lib"
for library in "$INSTALL_ROOT"/usr/lib/libc_bio.so* "$INSTALL_ROOT"/usr/lib/libdl_bio.so* \
               "$INSTALL_ROOT"/usr/lib/libpthread_bio.so* "$INSTALL_ROOT"/usr/lib/libstdc++_bio.so*; do
    # Materialize every SONAME alias so a replaced loader never resolves an
    # alias left pointing at the original 4 KiB build.
    cp -L "$library" "$NEXT_OUTPUT/usr/lib/"
done
find "$NEXT_OUTPUT/usr" -type f -exec strip --strip-unneeded '{}' \;
python3 - "$NEXT_OUTPUT" "$COMMIT" "$SOURCE_URL" "$SOURCE_ARCHIVE" \
    "$SCRIPT_DIR/bionic16k.patch" "$DEPENDENCY_CACHE" <<'PY'
import hashlib, json, pathlib, struct, subprocess, sys
output, commit, url, archive, patch, cache = sys.argv[1:]
root = pathlib.Path(output)
files = []
for path in sorted((root / "usr").rglob("*")):
    if not path.is_file():
        continue
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", data, 18)[0] != 183:
        raise SystemExit(f"build-bionic: output is not an ARM64 ELF: {path}")
    offset = struct.unpack_from("<Q", data, 32)[0]
    entry_size, count = struct.unpack_from("<HH", data, 54)
    if (entry_size != 56 or count == 0 or offset > len(data)
            or count * entry_size > len(data) - offset):
        raise SystemExit(f"build-bionic: invalid ELF program headers: {path}")
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
            raise SystemExit(f"build-bionic: output cannot load with 16 KiB pages: {path}")
    if loads == 0:
        raise SystemExit(f"build-bionic: output has no loadable segments: {path}")
    files.append({"path": str(path.relative_to(root)), "size": len(data),
                  "sha256": hashlib.sha256(data).hexdigest()})
packages = subprocess.check_output(["apk", "list", "--installed"], text=True).splitlines()
archives = [{"filename": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in sorted(pathlib.Path(cache).glob("*.apk"))]
source = pathlib.Path(archive).read_bytes()
manifest = {"format": 1, "architecture": "aarch64", "page_size": 16384,
            "source_commit": commit, "source_url": url,
            "source_sha512": hashlib.sha512(source).hexdigest(),
            "source_sha256": hashlib.sha256(source).hexdigest(),
            "patch_sha256": hashlib.sha256(pathlib.Path(patch).read_bytes()).hexdigest(),
            "build_flags": ["-DBIONIC_PAGE_SIZE=16384", "-Wl,-z,max-page-size=65536"],
            "compiler": subprocess.check_output(["gcc", "--version"], text=True).splitlines()[0],
            "compiler_target": subprocess.check_output(["gcc", "-dumpmachine"], text=True).strip(),
            "source_date_epoch": 1773705600, "build_packages": packages,
            "dependency_archives": archives, "files": files}
(root / "bionic-runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Verified {len(files)} native ARM64 bionic ELF outputs")
PY
rm -rf "$OUTPUT_DIR"
mv "$NEXT_OUTPUT" "$OUTPUT_DIR"
echo "Staged native 16 KiB bionic overlay in $OUTPUT_DIR"
