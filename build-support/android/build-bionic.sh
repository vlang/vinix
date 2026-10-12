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
for command in curl patch gcc g++ strip tar meson; do
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
SOURCE_ARCHIVE=$("$SCRIPT_DIR/native-tool" resolve "$SOURCE_ARCHIVE")
"$SCRIPT_DIR/native-tool" verify-source bionic "$SOURCE_ARCHIVE" "$SOURCE_SHA512"

SOURCE_DIR="$BUILD_DIR/bionic_translation-$COMMIT"
INPUT_KEY=$("$SCRIPT_DIR/native-tool" source-key "$SOURCE_SHA512" "" "$SCRIPT_DIR/bionic16k.patch" "$0")

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
"$SCRIPT_DIR/native-tool" bionic-build-manifest "$NEXT_OUTPUT" "$COMMIT" "$SOURCE_URL" "$SOURCE_ARCHIVE" "$SCRIPT_DIR/bionic16k.patch" "$DEPENDENCY_CACHE"

rm -rf "$OUTPUT_DIR"
mv "$NEXT_OUTPUT" "$OUTPUT_DIR"
echo "Staged native 16 KiB bionic overlay in $OUTPUT_DIR"
