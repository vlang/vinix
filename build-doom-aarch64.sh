#!/bin/bash
# Build upstream Chocolate Doom and stage it with SDL2 for the AArch64 desktop.
# The WAD is local input and is never checked into the repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_DOOM_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-doom}"
SOURCE="$BUILD_DIR/source"
DOWNLOADS="$BUILD_DIR/downloads"
SDL_ROOT="$BUILD_DIR/sysroot"
STAGING="$BUILD_DIR/staging"
DOOM_TAG=chocolate-doom-3.1.1
SDL_VERSION=2.30.9-r0
WAD="${VINIX_DOOM_WAD:-$SCRIPT_DIR/../3rd/doom/doom1.wad}"
CC="${VINIX_DOOM_CC:-aarch64-linux-musl-gcc}"

for tool in git curl tar cmake ninja "$CC"; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing build tool: $tool" >&2; exit 1; }
done
mkdir -p "$DOWNLOADS" "$SDL_ROOT" "$STAGING/usr/bin" \
    "$STAGING/usr/lib" "$STAGING/usr/share/games/doom"

if [ ! -f "$SOURCE/CMakeLists.txt" ]; then
    git clone --depth 1 --branch "$DOOM_TAG" \
        https://github.com/chocolate-doom/chocolate-doom.git "$SOURCE"
fi
for package in sdl2 sdl2-dev; do
    archive="$DOWNLOADS/$package-$SDL_VERSION.apk"
    if [ ! -s "$archive" ]; then
        curl -fL --retry 3 -o "$archive" \
            "https://dl-cdn.alpinelinux.org/alpine/v3.21/community/aarch64/$package-$SDL_VERSION.apk"
    fi
    tar xzf "$archive" -C "$SDL_ROOT" 2>/dev/null || true
done

cmake -S "$SOURCE" -B "$BUILD_DIR/cmake" -G Ninja \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=OFF \
    -DENABLE_SDL2_NET=OFF -DENABLE_SDL2_MIXER=OFF \
    -DSDL2_INCLUDE_DIR="$SDL_ROOT/usr/include/SDL2" \
    -DSDL2_LIBRARY="$SDL_ROOT/usr/lib/libSDL2.so" \
    -DSDL2_MAIN_LIBRARY="$SDL_ROOT/usr/lib/libSDL2main.a" \
    -DCMAKE_DISABLE_FIND_PACKAGE_PNG=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_SampleRate=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_FluidSynth=ON
cmake --build "$BUILD_DIR/cmake" --target chocolate-doom -j "${VINIX_DOOM_JOBS:-8}"

install -m755 "$BUILD_DIR/cmake/src/chocolate-doom" "$STAGING/usr/bin/chocolate-doom"
install -m755 "$SCRIPT_DIR/build-support/doom/run-doom" "$STAGING/usr/bin/run-doom"
install -m644 "$SCRIPT_DIR/build-support/doom/vinix.cfg" \
    "$STAGING/usr/share/games/doom/vinix.cfg"
install -m755 "$SDL_ROOT/usr/lib/libSDL2-2.0.so.0.3000.9" \
    "$STAGING/usr/lib/libSDL2-2.0.so.0"
if [ -f "$WAD" ]; then
    install -m644 "$WAD" "$STAGING/usr/share/games/doom/doom1.wad"
    echo "staged WAD: $WAD"
else
    rm -f "$STAGING/usr/share/games/doom/doom1.wad"
    echo "WAD not found at $WAD; set VINIX_DOOM_WAD to include it in the image"
fi
echo "staged Chocolate Doom: $STAGING"
