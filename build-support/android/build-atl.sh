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
for command in curl gcc g++ strip tar patch meson java javac; do
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
SOURCE_ARCHIVE=$("$SCRIPT_DIR/native-tool" resolve "$SOURCE_ARCHIVE")
R8_ARCHIVE=$("$SCRIPT_DIR/native-tool" resolve "$R8_ARCHIVE")
CORE_CLASSES=$("$SCRIPT_DIR/native-tool" resolve "$CORE_CLASSES")
ART_RUNTIME=$("$SCRIPT_DIR/native-tool" resolve "$ART_RUNTIME")
"$SCRIPT_DIR/native-tool" verify-source atl "$SOURCE_ARCHIVE" "$SOURCE_SHA512"
"$SCRIPT_DIR/native-tool" verify-atl-inputs "$ART_RUNTIME" "$R8_ARCHIVE" "$CORE_CLASSES"

SOURCE_DIR="$BUILD_DIR/android_translation_layer-$COMMIT"
INPUT_KEY=$("$SCRIPT_DIR/native-tool" source-key "$SOURCE_SHA512" "$ART_RUNTIME" "$0" "$SCRIPT_DIR/atl-configuration.patch" "$SCRIPT_DIR/atlconfiguration/core.v" "$SCRIPT_DIR/atl-configuration-v-abi.h" "$SCRIPT_DIR/../compile-v-module" "$SCRIPT_DIR/../find-v.sh" "$ART_RUNTIME/art-runtime-manifest.json")

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
printf '%s\n' '#!/bin/sh' 'exec "'"$SCRIPT_DIR"'/atl-dex" "$@"' > "$BUILD_DIR/tools/dx"

chmod +x "$BUILD_DIR/tools/dx"
export PATH="$BUILD_DIR/tools:$PATH"
BUILD_OUTPUT="$SOURCE_DIR/output"
if [ ! -f "$BUILD_OUTPUT/build.ninja" ]; then
    COMPILE_ARGS=$("$SCRIPT_DIR/native-tool" compile-args "$ART_RUNTIME")
    LINK_ARGS=$("$SCRIPT_DIR/native-tool" link-args "$ART_RUNTIME")

    meson setup "$BUILD_OUTPUT" "$SOURCE_DIR" --prefix /usr --libdir lib --buildtype release \
        "-Dc_args=$COMPILE_ARGS" "-Dc_link_args=$LINK_ARGS"
fi
echo "Building native ARM64 ATL $COMMIT in $SOURCE_DIR"
# AAPT rewrites internal R.java, and javac regenerates the native JNI headers.
# Upstream Meson does not declare these generated-file ordering dependencies.
# Finish both generators before parallel Java/native consumers read their files.
meson compile -C "$BUILD_OUTPUT" -j "$JOBS" framework-res.apk
meson compile -C "$BUILD_OUTPUT" -j "$JOBS" hax
meson compile -C "$BUILD_OUTPUT" -j "$JOBS"
INSTALL_ROOT="$BUILD_DIR/install"
rm -rf "$INSTALL_ROOT"
meson install -C "$BUILD_OUTPUT" --no-rebuild --destdir "$INSTALL_ROOT"
NEXT_OUTPUT="$OUTPUT_DIR.next"
rm -rf "$NEXT_OUTPUT"
mkdir -p "$NEXT_OUTPUT"
"$SCRIPT_DIR/native-tool" copy-installed "$INSTALL_ROOT" "$NEXT_OUTPUT"

# Verify the production configuration object against the real selected
# androidfw provider. Loading all of libandroid requires launcher globals and
# a desktop; its freshly compiled configuration object needs neither.
CONFIGURATION_TEST="$NEXT_OUTPUT/usr/libexec/vinix-android/atl-configuration-test"
mkdir -p "$(dirname -- "$CONFIGURATION_TEST")"
"$SCRIPT_DIR/compile-v-atl-configuration" "$BUILD_DIR/atl-configuration-probe.c"
gcc -O2 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-parameter \
    -I"$ART_RUNTIME/usr/include" -I"$SCRIPT_DIR" \
    -c "$BUILD_DIR/atl-configuration-probe.c" -o "$BUILD_DIR/atl-configuration-probe.o"
gcc -O2 -Wall -Wextra -Werror -Wl,-z,max-page-size=65536 \
    "$BUILD_DIR/atl-configuration-probe.o" -o "$CONFIGURATION_TEST" \
    "$BUILD_OUTPUT/libandroid.so.0.p/src_libandroid_configuration.c.o" \
    -L"$ART_RUNTIME/usr/lib/art" -landroidfw -lpng -Wl,-rpath-link,"$ART_RUNTIME/usr/lib/art"
LD_LIBRARY_PATH="$ART_RUNTIME/usr/lib/art${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$CONFIGURATION_TEST"
CONFIGURATION_PROBE_KEY=$("$SCRIPT_DIR/native-tool" configuration-probe-key)

"$SCRIPT_DIR/native-tool" atl-build-manifest "$NEXT_OUTPUT" "$COMMIT" "$SOURCE_URL" "$SOURCE_ARCHIVE" "$R8_ARCHIVE" "$CORE_CLASSES" "$SCRIPT_DIR/atl-dex" "$0" "$DEPENDENCY_CACHE" "$SCRIPT_DIR/atl-configuration.patch" "$SCRIPT_DIR/art16k.patch" "$ART_RUNTIME" "$CONFIGURATION_PROBE_KEY"

rm -rf "$OUTPUT_DIR"
mv "$NEXT_OUTPUT" "$OUTPUT_DIR"
echo "Staged native ATL overlay in $OUTPUT_DIR"
