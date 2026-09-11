#!/bin/bash
# Build Blender 4.3 with the native Vinix GHOST backend on Alpine/aarch64.
# The resulting executable uses surfaceless EGL and Vinix's shared-surface ABI;
# neither X11 nor Wayland is compiled into its window-system layer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_BLENDER_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-blender-native}"
DOWNLOADS="$BUILD_DIR/downloads"
SOURCE_DIR="$BUILD_DIR/blender-4.3.0"
TARGET_BUILD="$BUILD_DIR/build-full"
STAGING="$BUILD_DIR/staging"
VERSION=4.3.0
SOURCE_ARCHIVE="$DOWNLOADS/blender-$VERSION.tar.xz"
SOURCE_URL="https://download.blender.org/source/blender-$VERSION.tar.xz"
SOURCE_SHA512=d71a954540eac1ce5301b0a831daeb03d8e3c5a39b8955077630c72cf502592ca9f2fd9926d19cde47b9e4b8cff16451c5d86e0213a230f20fa684e9e1c219e9
ALPINE_APORT_URL="https://gitlab.alpinelinux.org/alpine/aports/-/raw/3.21-stable/community/blender"
NPROC="${NPROC:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

case "$BUILD_DIR" in
    ''|'/'|"$SCRIPT_DIR")
        echo "unsafe VINIX_BLENDER_BUILD_DIR: $BUILD_DIR" >&2
        exit 1
        ;;
esac

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != aarch64 ]; then
    echo "build-blender-native-aarch64.sh must run on an aarch64 Linux builder." >&2
    echo "An Alpine 3.21 VM is recommended; its stock Blender package supplies the matching runtime." >&2
    exit 1
fi
if [ ! -f /etc/alpine-release ] || ! command -v apk >/dev/null 2>&1; then
    echo "this reproducible build currently requires Alpine Linux" >&2
    exit 1
fi
case "$(cat /etc/alpine-release)" in
    3.21.*) ;;
    *)
        echo "this build must run on Alpine 3.21 to match Vinix's Blender runtime package" >&2
        exit 1
        ;;
esac

BUILD_PACKAGES=(
    build-base linux-headers alembic-dev blosc-dev boost-dev clang-dev cmake
    curl eigen-dev embree-dev embree-static ffmpeg-dev fftw-dev freetype-dev gmp-dev
    jack-dev jemalloc-dev libepoxy-dev libharu-dev libjpeg-turbo-dev libpng-dev
    libsndfile-dev lzo-dev onetbb-dev openal-soft-dev opencolorio-dev openexr-dev
    openimagedenoise-dev openimageio-dev openjpeg-dev openpgl-dev opensubdiv-dev
    openvdb-dev openvdb-nanovdb osl osl-dev potrace-dev pugixml-dev pulseaudio-dev
    py3-numpy-dev py3-zstandard python3-dev samurai tiff-dev xz
)
if [ "${VINIX_BLENDER_SKIP_APK:-0}" != 1 ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "run as root to install build dependencies, or preinstall them and set VINIX_BLENDER_SKIP_APK=1" >&2
        exit 1
    fi
    apk add --no-cache "${BUILD_PACKAGES[@]}"
fi

for tool in awk cmake curl ninja patch python3 readelf sha512sum strings tar install; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing build tool: $tool" >&2
        exit 1
    }
done

mkdir -p "$DOWNLOADS"
if [ ! -s "$SOURCE_ARCHIVE" ]; then
    echo "==> Downloading Blender $VERSION"
    curl -fL --retry 3 -o "$SOURCE_ARCHIVE" "$SOURCE_URL"
fi
actual_sha512="$(sha512sum "$SOURCE_ARCHIVE" | awk '{print $1}')"
if [ "$actual_sha512" != "$SOURCE_SHA512" ]; then
    echo "Blender source checksum mismatch: $actual_sha512" >&2
    exit 1
fi

download_aport_patch() {
    local name="$1" checksum="$2"
    local destination="$DOWNLOADS/$name"
    if [ ! -s "$destination" ]; then
        curl -fL --retry 3 -o "$destination" "$ALPINE_APORT_URL/$name"
    fi
    local actual
    actual="$(sha512sum "$destination" | awk '{print $1}')"
    if [ "$actual" != "$checksum" ]; then
        echo "$name checksum mismatch: $actual" >&2
        exit 1
    fi
}

download_aport_patch 0001-musl-fixes.patch fd06c0af6855e15edc7ce9a4bdcd07f245d5d8bc84f67b49c2935bbfb6c811e62926ec8932bc9b903d5d314e5be5c079510e73b4ef9968fd88abca585ffecb57
download_aport_patch 0002-fix-includes.patch 8fffd66af4a4ebc23767950c2831c889d2260fc499d094d57da5f6638cb85b67d520eb2d68d88146326ffbac74495fc09f803c03a6ab04555e91b379fd3328f2

rm -rf "$SOURCE_DIR" "$TARGET_BUILD" "$STAGING"
tar xJf "$SOURCE_ARCHIVE" -C "$BUILD_DIR"
patch -p1 -d "$SOURCE_DIR" < "$DOWNLOADS/0001-musl-fixes.patch"
patch -p1 -d "$SOURCE_DIR" < "$DOWNLOADS/0002-fix-includes.patch"
patch -p1 -d "$SOURCE_DIR" < "$SCRIPT_DIR/build-support/blender/blender-4.3-vinix.patch"
for source in GHOST_VinixProtocol.hh GHOST_SystemVinix.hh GHOST_SystemVinix.cc \
    GHOST_WindowVinix.hh GHOST_WindowVinix.cc; do
    install -m644 "$SCRIPT_DIR/build-support/blender/$source" \
        "$SOURCE_DIR/intern/ghost/intern/$source"
done

PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
echo "==> Building Blender $VERSION with native Vinix GHOST"
cmake -S "$SOURCE_DIR" -B "$TARGET_BUILD" -G Ninja -Wno-dev \
    -C "$SOURCE_DIR/build_files/cmake/config/blender_full.cmake" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_GHOST_VINIX=ON \
    -DWITH_GHOST_X11=OFF \
    -DWITH_GHOST_WAYLAND=OFF \
    -DWITH_GHOST_SDL=OFF \
    -DWITH_HEADLESS=OFF \
    -DWITH_OPENGL_BACKEND=ON \
    -DWITH_VULKAN_BACKEND=OFF \
    -DWITH_XR_OPENXR=OFF \
    -DWITH_INPUT_IME=OFF \
    -DWITH_INPUT_NDOF=OFF \
    -DWITH_PYTHON_INSTALL=OFF \
    -DWITH_INSTALL_PORTABLE=OFF \
    -DWITH_LIBS_PRECOMPILED=OFF \
    -DWITH_SYSTEM_EIGEN3=ON \
    -DWITH_SYSTEM_LZO=ON \
    -DWITH_LZMA=OFF \
    -DPYTHON_VERSION="$PYTHON_VERSION" \
    -DWITH_DRACO=OFF \
    -DWITH_CYCLES_OSL=OFF
cmake --build "$TARGET_BUILD" -j "$NPROC"

mkdir -p "$STAGING/usr/libexec"
install -m755 "$TARGET_BUILD/bin/blender" "$STAGING/usr/libexec/vinix-blender-native"

if ! readelf -h "$STAGING/usr/libexec/vinix-blender-native" | grep 'Machine:.*AArch64' >/dev/null; then
    echo "native Blender output is not AArch64" >&2
    exit 1
fi
if readelf -d "$STAGING/usr/libexec/vinix-blender-native" | \
    grep -E 'Shared library: \[(libX|libxcb|libwayland|libSDL)' >/dev/null; then
    echo "native Blender unexpectedly links an X11, Wayland, or SDL window-system library" >&2
    exit 1
fi
if ! strings "$STAGING/usr/libexec/vinix-blender-native" | grep VINIX_SURFACE_PATH >/dev/null; then
    echo "native Blender is missing the Vinix GHOST backend" >&2
    exit 1
fi

echo "==> Staged $STAGING/usr/libexec/vinix-blender-native"
echo "Install Blender's runtime data in Vinix with: pkg install blender"
