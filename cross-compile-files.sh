#!/bin/bash
# Build the committed Files app for AArch64 and publish it to running QEMU guests.
# Guests started with the current desktop image poll the host package server and
# install this binary at /usr/bin/vinix-files without restarting Vinix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLISH_DIR="$SCRIPT_DIR/build-aarch64-desktop-apps/files-live"
BUILD_CACHE="$SCRIPT_DIR/build-aarch64-desktop-apps/files-cross-cache"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$SCRIPT_DIR/build-aarch64-userland/staging}"

if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    UI2_SOURCE="$VINIX_UI2_SOURCE"
elif [ -f "$SCRIPT_DIR/../ui2/v.mod" ]; then
    UI2_SOURCE="$SCRIPT_DIR/../ui2"
else
    UI2_SOURCE="$SCRIPT_DIR/third_party/ui2"
fi

if [ ! -f "$UI2_SOURCE/v.mod" ]; then
    echo "ERROR: ui2 source is missing: $UI2_SOURCE" >&2
    exit 1
fi

mkdir -p "$PUBLISH_DIR" "$BUILD_CACHE"
SNAPSHOT="$BUILD_CACHE/source"
LOCK="$BUILD_CACHE/.lock"
release_lock() {
    if [ "$(readlink "$LOCK" 2>/dev/null || true)" = "$$" ]; then
        rm -f "$LOCK"
    fi
}
while ! ln -s "$$" "$LOCK" 2>/dev/null; do
    owner=$(readlink "$LOCK" 2>/dev/null || true)
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
        rm -f "$LOCK"
        continue
    fi
    sleep 1
done
trap release_lock EXIT

# A post-commit build must use the committed sources. Other work in the shared
# checkout may be uncommitted or even temporarily uncompilable.
revision=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
echo "==> Cross-compiling Files from ${revision:0:8}"
if [ ! -d "$SNAPSHOT" ] || [ "$(cat "$BUILD_CACHE/source-revision" 2>/dev/null || true)" != "$revision" ]; then
    rm -rf "$SNAPSHOT"
    mkdir -p "$SNAPSHOT"
    git -C "$SCRIPT_DIR" archive "$revision" | tar -xf - -C "$SNAPSHOT"
    printf '%s\n' "$revision" > "$BUILD_CACHE/source-revision"
fi
VINIX_UI2_SOURCE="$UI2_SOURCE" \
VINIX_AARCH64_SYSROOT="$SYSROOT" \
VINIX_AARCH64_APP_CACHE="$BUILD_CACHE" \
    "$SNAPSHOT/build-desktop-aarch64.sh" --no-initramfs

binary="$SNAPSHOT/build/vinix-desktop"
if [ ! -s "$binary" ]; then
    echo "ERROR: cross-build produced no desktop executable" >&2
    exit 1
fi
if [ "$(git -C "$SCRIPT_DIR" rev-parse HEAD)" != "$revision" ]; then
    echo "==> A newer commit arrived during the build; it will publish its own Files binary"
    exit 0
fi

# Publish the complete binary before its version. The guest verifies the
# checksum, then atomically replaces only the Files executable.
temporary="$PUBLISH_DIR/.vinix-files.$$"
trap 'rm -f "$temporary"; release_lock' EXIT
cp "$binary" "$temporary"
chmod 755 "$temporary"
mv -f "$temporary" "$PUBLISH_DIR/vinix-files"
version_temporary="$PUBLISH_DIR/.version.$$"
trap 'rm -f "$temporary" "$version_temporary"; release_lock' EXIT
cksum "$PUBLISH_DIR/vinix-files" | awk '{print $1, $2}' \
    > "$version_temporary"
mv -f "$version_temporary" "$PUBLISH_DIR/version"
echo "==> Published Files to $PUBLISH_DIR/vinix-files"
echo "    A running desktop VM with Files sync installed will pick it up shortly."
