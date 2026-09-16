#!/bin/bash
# Stage Minecraft: Java Edition for the Vinix aarch64 desktop.
#
# The game itself is downloaded from Mojang's own distribution endpoints at
# build time, exactly as any third-party launcher does, and is never part of
# this repository. This script stages the runtime around it: the musl libraries
# Mojang's Linux build does not account for, Mesa's software OpenGL, and the
# launcher.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_MINECRAFT_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-minecraft}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
JAVA_STAGING="${VINIX_JAVA_STAGING:-$SCRIPT_DIR/build-aarch64-java/staging}"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64

# Mojang pins the client to a Java feature release; the Vinix Java layer stages
# OpenJDK 25, which covers every version that asks for 21 or 25.
MINECRAFT_VERSION="${VINIX_MINECRAFT_VERSION:-release}"
GAME_ROOT=/usr/share/minecraft

FETCH_ARGS=()
if [ "${VINIX_MINECRAFT_ASSETS:-full}" = none ]; then
    FETCH_ARGS+=(--no-assets)
fi

for tool in curl python3 tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

if [ ! -x "$JAVA_STAGING/usr/bin/java" ]; then
    echo "Minecraft needs the Java layer; run ./build-java-aarch64.sh first" >&2
    exit 1
fi

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

echo "=== resolving the Minecraft runtime for $ALPINE_ARCH ==="
# LWJGL publishes no musl natives, so its AArch64 builds are glibc objects that
# resolve through gcompat. Its bundled OpenAL and jemalloc are the two that do
# not survive that translation, so Alpine's native builds are staged for the
# launcher to substitute. mesa-dri-gallium brings llvmpipe, which is the only
# software rasteriser here that reaches the OpenGL 3.2 core profile the modern
# client requires. wayland-libs-server is a server-side edge of Mesa's gbm
# loader that Alpine's dependency graph does not record.
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$DOWNLOADS/main_APKINDEX" \
    --index community "$DOWNLOADS/community_APKINDEX" \
    gcompat jemalloc openal-soft-libs glfw freetype harfbuzz \
    mesa-dri-gallium mesa-gl mesa-egl mesa-gbm \
    libx11 libxcursor libxrandr libxinerama libxi libxxf86vm \
    wayland-libs-server > "$BUILD_DIR/packages"

while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    archive="$DOWNLOADS/$filename"
    if [ ! -f "$archive" ]; then
        echo "  downloading $filename"
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/$filename"
    fi
    echo "  extracting $filename"
    # APK files concatenate signature, metadata and payload tar streams; the
    # host tar reports the trailing stream after extracting the payload.
    tar xzf "$archive" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

echo "=== downloading Minecraft: Java Edition ==="
# The game is resolved into a cache beside the staging tree, which this script
# wipes on every run. Half a gigabyte of assets is not worth re-downloading to
# rebuild the layer around them.
GAME_CACHE="$BUILD_DIR/game-cache"
python3 "$SCRIPT_DIR/build-support/minecraft/fetch-minecraft.py" \
    --version "$MINECRAFT_VERSION" \
    --staging "$GAME_CACHE" \
    --game-root "$GAME_ROOT" \
    ${FETCH_ARGS[@]+"${FETCH_ARGS[@]}"}
mkdir -p "$STAGING$(dirname "$GAME_ROOT")"
cp -a "$GAME_CACHE$GAME_ROOT" "$STAGING$(dirname "$GAME_ROOT")/"

mkdir -p "$STAGING/usr/bin" "$STAGING/usr/share/vinix" "$STAGING/root"
install -m755 "$SCRIPT_DIR/build-support/minecraft/run-minecraft" \
    "$STAGING/usr/bin/minecraft"
install -m755 "$SCRIPT_DIR/build-support/minecraft/minecraft-login" \
    "$STAGING/usr/bin/minecraft-login"
install -m755 "$SCRIPT_DIR/build-support/minecraft/minecraft-xinitrc" \
    "$STAGING/usr/share/vinix/minecraft-xinitrc"
install -m755 "$SCRIPT_DIR/tests/minecraft/smoke.sh" \
    "$STAGING/root/minecraft-smoke.sh"

# Vinix's musl loader opens DT_NEEDED objects without following links, and
# gcompat ships its glibc ABI entirely as aliases of libgcompat. Turn every
# library alias in this layer into an ordinary file.
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

# Alpine's Mesa package carries every ARM64 Gallium driver. Minecraft uses the
# software rasteriser, so keep that one pipe — and, unlike the layer this
# replaces, the LLVM image it needs, because llvmpipe is what provides the
# OpenGL 3.2 core profile. softpipe alone cannot start the modern client.
if [ -d "$STAGING/usr/lib/gallium-pipe" ]; then
    find "$STAGING/usr/lib/gallium-pipe" -type f ! -name pipe_swrast.so -delete
fi

# Minecraft is a Java application and no image stages a JVM on its own, so this
# layer carries the Java one. It is merged after the alias pass above because
# build-java-aarch64.sh has already resolved its own libraries and deliberately
# keeps $JAVA_HOME/jre and the /usr/bin command aliases intact.
echo "=== merging the Java runtime ==="
tar -cf - -C "$JAVA_STAGING" . | tar -xf - -C "$STAGING"

for required in \
    usr/bin/minecraft \
    usr/bin/minecraft-login \
    usr/bin/java \
    usr/lib/jvm/java-25-openjdk/lib/server/libjvm.so \
    lib/libgcompat.so.0 \
    lib/libc.so.6 \
    usr/lib/libjemalloc.so.2 \
    usr/lib/libopenal.so.1 \
    usr/lib/libfreetype.so.6 \
    usr/lib/libharfbuzz.so.0 \
    usr/share/vinix/minecraft-xinitrc \
    "${GAME_ROOT#/}/launch.env"; do
    if [ ! -e "$STAGING/$required" ]; then
        echo "missing staged Minecraft runtime: /$required" >&2
        exit 1
    fi
done

# The client is only playable if the AArch64 LWJGL natives really were
# substituted for Mojang's x86-64 ones.
if ! grep -q 'natives-linux-arm64' "$STAGING$GAME_ROOT/launch.env"; then
    echo "staged classpath has no AArch64 LWJGL natives" >&2
    exit 1
fi
# Mojang ships the LWJGL core classes under an `unsafe` classifier rather than
# as a plain jar, so a filter written in terms of classifiers can drop
# org.lwjgl.system and leave a classpath that only fails once the client runs.
lwjgl_core=$(
    . "$STAGING$GAME_ROOT/launch.env"
    printf '%s' "$MC_CLASSPATH" | tr ':' '\n' |
        grep -E '/org/lwjgl/lwjgl/[^/]+/lwjgl-[^/]+\.jar$' |
        grep -vc 'natives-'
)
if [ "${lwjgl_core:-0}" -eq 0 ]; then
    echo "staged classpath has no LWJGL core classes" >&2
    exit 1
fi

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
echo "packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
echo "version: $(. "$STAGING$GAME_ROOT/launch.env" && echo "$MC_VERSION")"
echo "run: rebuild the desktop image, then open Minecraft from the launcher"
