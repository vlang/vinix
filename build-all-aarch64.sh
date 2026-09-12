#!/bin/bash
# Build one AArch64 desktop image containing Vinix's default software set.
# Large applications that can be installed on demand are deliberately left
# out. Individual layer builders remain useful while developing a component;
# this is the reproducible release/image entry point.
#
# Usage: ./build-all-aarch64.sh [--reuse-layers]
#
# --reuse-layers validates and assembles the existing staging trees without
# downloading or rebuilding them. The final image is always rebuilt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FINAL_IMAGE="$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar"
REBUILD_LAYERS=1
OMITTED_STAGING=""
manifest=""

cleanup() {
    if [ -n "$manifest" ]; then
        rm -f "$manifest"
    fi
    if [ -n "$OMITTED_STAGING" ]; then
        rm -rf "$OMITTED_STAGING"
    fi
}
trap cleanup EXIT INT TERM

for arg in "$@"; do
    case "$arg" in
        --reuse-layers) REBUILD_LAYERS=0 ;;
        --help|-h)
            awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

# The ordinary userland and desktop builders intentionally merge every cached
# optional staging tree they find. Point the two native on-demand layers at an
# empty temporary tree so an earlier component build cannot silently bloat
# this image again. The x86 translator remains part of the image, but its layer
# must be built in translator-only mode so it carries no Wine runtime.
OMITTED_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/vinix-all-omitted.XXXXXX")"

assemble_userland() {
    VINIX_JAVA_STAGING="$OMITTED_STAGING/java" \
    VINIX_MINECRAFT_STAGING="$OMITTED_STAGING/minecraft" \
        VINIX_ALPINE_BASE_ONLY=0 "$SCRIPT_DIR/build-userland-aarch64.sh"
}

assemble_desktop() {
    VINIX_MINECRAFT_STAGING="$OMITTED_STAGING/minecraft" \
        "$SCRIPT_DIR/build-desktop-aarch64.sh"
}

build_layer() {
    local label="$1"
    local builder="$2"
    shift 2
    echo
    echo "==> Building all-image layer: $label"
    "$SCRIPT_DIR/$builder" "$@"
}

require_file() {
    local label="$1"
    local relative="$2"
    if [ ! -e "$SCRIPT_DIR/$relative" ]; then
        echo "ERROR: $label layer is incomplete; missing $relative" >&2
        echo "       Re-run without --reuse-layers to build it." >&2
        exit 1
    fi
}

if [ "$REBUILD_LAYERS" -eq 1 ]; then
    # Xorg's cross-linker can use the target GCC runtime from this bootstrap
    # tree. Rebuild it after the layers so the published base contains them.
    echo "==> Bootstrapping the AArch64 base userland"
    VINIX_ALPINE_BASE_ONLY=1 "$SCRIPT_DIR/build-userland-aarch64.sh"

    build_layer "Python" build-python-aarch64.sh
    build_layer "Ruby" build-ruby-aarch64.sh
    build_layer "Go" build-go-aarch64.sh
    build_layer "network tools and package manager" build-network-tools-aarch64.sh
    build_layer "developer tools" build-developer-tools-aarch64.sh
    build_layer "X11" build-x11-aarch64.sh
    build_layer "Firefox" build-firefox-aarch64.sh
    build_layer "Hyprland" build-hyprland-aarch64.sh
    build_layer "Codex CLI" build-codex-aarch64.sh
    build_layer "Claude Code" build-claude-aarch64.sh
    build_layer "x86 translation" build-x86-translation-aarch64.sh --translator-only
fi

# Do not silently publish a partial "all" image. These are the portable layers
# the aggregate builder owns. Hardware-specific Asahi Mesa and native Blender
# are produced on mutually different Linux builders; build-desktop-aarch64.sh
# also merges those trees when they have been copied into this checkout.
require_file "Python" build-aarch64-python/staging/usr/bin/python3
require_file "Ruby" build-aarch64-ruby/staging/usr/bin/ruby
if [ ! -x "$SCRIPT_DIR/build-aarch64-go/staging/usr/bin/go" ] &&
   [ ! -x "$SCRIPT_DIR/build-aarch64-go/staging/usr/lib/go/bin/go" ]; then
    echo "ERROR: Go layer is incomplete; no staged Go executable" >&2
    exit 1
fi
require_file "network tools" build-aarch64-network-tools/staging/usr/bin/pkg
require_file "developer tools" build-aarch64-developer-tools/staging/usr/bin/cmake
require_file "X11" build-aarch64-x11/staging/usr/bin/Xorg
require_file "Firefox" build-aarch64-firefox/staging/usr/bin/run-firefox
require_file "Hyprland" build-aarch64-hyprland/staging/usr/bin/Hyprland
require_file "Codex CLI" build-aarch64-codex/staging/usr/bin/codex
require_file "Claude Code" build-aarch64-claude/staging/usr/bin/claude
require_file "x86 translation" build-aarch64-x86-translation/staging/usr/bin/qemu-x86_64
for wine_path in usr/bin/wine usr/bin/wine32 usr/bin/wine64; do
    if [ -e "$SCRIPT_DIR/build-aarch64-x86-translation/staging/$wine_path" ]; then
        echo "ERROR: cached x86 layer includes Wine; rebuild without --reuse-layers" >&2
        exit 1
    fi
done

echo
echo "==> Assembling the default AArch64 userland"
assemble_userland

echo
echo "==> Assembling the default AArch64 desktop image"
assemble_desktop

if [ ! -f "$FINAL_IMAGE" ]; then
    echo "ERROR: desktop builder did not publish $FINAL_IMAGE" >&2
    exit 1
fi

manifest="$(mktemp "${TMPDIR:-/tmp}/vinix-all-image.XXXXXX")"
tar -tf "$FINAL_IMAGE" | sed -e 's#^\./##' -e 's#/$##' > "$manifest"

for image_path in \
    usr/bin/python3 \
    usr/bin/ruby \
    usr/lib/go/bin/go \
    usr/bin/git \
    usr/bin/cmake \
    usr/bin/Xorg \
    usr/bin/run-firefox \
    usr/bin/Hyprland \
    usr/bin/codex \
    usr/bin/claude \
    usr/bin/qemu-x86_64; do
    if ! grep -Fqx "$image_path" "$manifest"; then
        echo "ERROR: default image is missing /$image_path" >&2
        exit 1
    fi
done

for image_path in \
    usr/bin/java \
    usr/bin/minecraft \
    usr/bin/wine \
    usr/bin/wine32 \
    usr/bin/wine64; do
    if grep -Fqx "$image_path" "$manifest"; then
        echo "ERROR: on-demand software was unexpectedly bundled: /$image_path" >&2
        exit 1
    fi
done

image_size="$(du -h "$FINAL_IMAGE" | cut -f1)"
echo
echo "=== Default AArch64 image built ==="
echo "Image: $FINAL_IMAGE ($image_size)"
echo "On demand: Java, Minecraft and Wine are not bundled"
echo "Boot:  ./run-desktop-aarch64.sh --no-desktop"
