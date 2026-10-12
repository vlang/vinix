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
for command in curl make patch gcc g++ strip tar; do
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
SOURCE_ARCHIVE=$("$SCRIPT_DIR/native-tool" resolve "$SOURCE_ARCHIVE")
"$SCRIPT_DIR/native-tool" verify-source art "$SOURCE_ARCHIVE" "$SOURCE_SHA512"

SOURCE_DIR="$BUILD_DIR/art_standalone-$COMMIT"
INPUT_KEY=$("$SCRIPT_DIR/native-tool" source-key "$SOURCE_SHA512" "" "$SCRIPT_DIR/art16k.patch" "$0")

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
find "$NEXT_OUTPUT/usr/bin" "$NEXT_OUTPUT/usr/lib" -type f -exec strip --strip-unneeded '{}' \;
mkdir -p "$NEXT_OUTPUT/usr/include/androidfw"
cp "$SOURCE_DIR/libandroidfw/include/androidfw/androidfw_c_api.h" "$NEXT_OUTPUT/usr/include/androidfw/"
"$SCRIPT_DIR/native-tool" art-build-manifest "$NEXT_OUTPUT" "$COMMIT" "$SOURCE_URL" "$SOURCE_ARCHIVE" "$SCRIPT_DIR/art16k.patch" "$DEPENDENCY_CACHE"

rm -rf "$OUTPUT_DIR"
mv "$NEXT_OUTPUT" "$OUTPUT_DIR"
echo "Staged native 16 KiB ART overlay in $OUTPUT_DIR"
