#!/bin/bash
# Stage a native AArch64 C++ Minecraft-style client for Vinix. The engine is
# Alpine's musl Minetest build; a pinned Minetest Game release makes the layer
# playable offline instead of leaving only the engine's development test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_MINECRAFT_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-minecraft}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64
MINETEST_GAME_VERSION=5.8.0
MINETEST_GAME_SHA256=33a3bb43b08497a0bdb2f49f140a2829e582d5c16c0ad52be1595c803f706912

for tool in curl python3 tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

file_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

mkdir -p "$DOWNLOADS"
rm -rf "$STAGING"
mkdir -p "$STAGING"

for repository in main community; do
    index="$DOWNLOADS/${repository}_APKINDEX"
    archive="$DOWNLOADS/${repository}_APKINDEX.tar.gz"
    echo "  fetching ${repository} index"
    curl -fL --retry 3 -o "$archive" \
        "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/APKINDEX.tar.gz"
    tar xOf "$archive" APKINDEX > "$index"
done

echo "=== resolving Minetest for $ALPINE_ARCH ==="
# Vinix's framebuffer Xorg loads Mesa's swrast DRI provider through libgbm.
# Alpine's Minetest dependency graph does not include that server-side edge,
# so request it explicitly or Xorg starts without a usable GLX provider.
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$DOWNLOADS/main_APKINDEX" \
    --index community "$DOWNLOADS/community_APKINDEX" \
    minetest wayland-libs-server > "$BUILD_DIR/packages"

while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    archive="$DOWNLOADS/$filename"
    if [ ! -f "$archive" ]; then
        echo "  downloading $filename"
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/$filename"
    fi
    echo "  extracting $filename"
    # APK files contain concatenated signature, metadata, and payload streams.
    tar xzf "$archive" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

game_archive="$DOWNLOADS/minetest_game-$MINETEST_GAME_VERSION.tar.gz"
if [ ! -f "$game_archive" ]; then
    echo "  downloading Minetest Game $MINETEST_GAME_VERSION"
    curl -fL --retry 3 -o "$game_archive" \
        "https://github.com/luanti-org/minetest_game/archive/refs/tags/$MINETEST_GAME_VERSION.tar.gz"
fi
actual_sha256=$(file_sha256 "$game_archive")
if [ "$actual_sha256" != "$MINETEST_GAME_SHA256" ]; then
    echo "Minetest Game checksum mismatch: $actual_sha256" >&2
    exit 1
fi
game_dir="$STAGING/usr/share/minetest/games/minetest_game"
mkdir -p "$game_dir"
tar xzf "$game_archive" -C "$game_dir" --strip-components=1

mkdir -p "$STAGING/usr/bin" "$STAGING/usr/share/vinix" "$STAGING/root"
install -m755 "$SCRIPT_DIR/build-support/minecraft/run-minecraft" \
    "$STAGING/usr/bin/minecraft"
install -m755 "$SCRIPT_DIR/build-support/minecraft/minecraft-xinitrc" \
    "$STAGING/usr/share/vinix/minecraft-xinitrc"
install -m644 "$SCRIPT_DIR/build-support/minecraft/minetest.conf" \
    "$STAGING/usr/share/vinix/minecraft.conf"
install -m755 "$SCRIPT_DIR/tests/minecraft/smoke.sh" \
    "$STAGING/root/minecraft-smoke.sh"

# Vinix's musl loader opens DT_NEEDED objects without following links. Turn
# the library aliases from Alpine packages into ordinary files in this layer.
for library_dir in "$STAGING/lib" "$STAGING/usr/lib"; do
    [ -d "$library_dir" ] || continue
    find "$library_dir" -type l 2>/dev/null | while IFS= read -r link; do
        target=$(readlink "$link")
        case "$target" in
            /*) real="$STAGING$target" ;;
            *) real="$(dirname "$link")/$target" ;;
        esac
        if [ -f "$real" ]; then
            rm "$link"
            cp "$real" "$link"
        fi
    done
done

# Alpine's Mesa package carries every ARM64 Gallium driver and installs the
# same 138 MiB LLVM image through several aliases. Minecraft uses Mesa's
# software rasterizer on Vinix, so retain its one pipe and the SONAME LLVM image
# it needs while dropping duplicate/private aliases and unrelated GPU drivers.
if [ -d "$STAGING/usr/lib/gallium-pipe" ]; then
    find "$STAGING/usr/lib/gallium-pipe" -type f ! -name pipe_swrast.so -delete
fi
rm -rf "$STAGING/usr/lib/llvm19"
rm -f "$STAGING/usr/lib/libLLVM-19.so"

for required in \
    usr/bin/minetest \
    usr/bin/minecraft \
    usr/lib/libwayland-server.so.0 \
    usr/share/vinix/minecraft-xinitrc \
    usr/share/minetest/games/minetest_game/game.conf; do
    if [ ! -e "$STAGING/$required" ]; then
        echo "missing staged Minecraft runtime: /$required" >&2
        exit 1
    fi
done
if command -v file >/dev/null 2>&1 \
    && ! file "$STAGING/usr/bin/minetest" | grep -Eq 'ARM aarch64|ARM64'; then
    echo "staged Minetest executable is not AArch64" >&2
    exit 1
fi

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
echo "packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
echo "run: rebuild the desktop image, then open Minecraft from the launcher"
