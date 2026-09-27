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
SNAPSHOT="$(mktemp -d "${TMPDIR:-/tmp}/vinix-files-build.XXXXXX")"
cleanup() { rm -rf "$SNAPSHOT"; }
trap cleanup EXIT

# A post-commit build must use the committed sources. Other work in the shared
# checkout may be uncommitted or even temporarily uncompilable.
echo "==> Cross-compiling Files from $(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
git -C "$SCRIPT_DIR" archive HEAD | tar -xf - -C "$SNAPSHOT"
VINIX_UI2_SOURCE="$UI2_SOURCE" \
VINIX_AARCH64_SYSROOT="$SYSROOT" \
VINIX_AARCH64_APP_CACHE="$BUILD_CACHE" \
    "$SNAPSHOT/build-desktop-aarch64.sh" --no-initramfs

binary="$SNAPSHOT/build/vinix-desktop"
if [ ! -s "$binary" ]; then
    echo "ERROR: cross-build produced no desktop executable" >&2
    exit 1
fi

# Publish the complete binary before its version. The guest verifies the
# checksum, then atomically replaces only the Files executable.
temporary="$PUBLISH_DIR/.vinix-files.$$"
trap 'rm -f "$temporary"; cleanup' EXIT
cp "$binary" "$temporary"
chmod 755 "$temporary"
mv -f "$temporary" "$PUBLISH_DIR/vinix-files"
version_temporary="$PUBLISH_DIR/.version.$$"
trap 'rm -f "$temporary" "$version_temporary"; cleanup' EXIT
cksum "$PUBLISH_DIR/vinix-files" | awk '{print $1, $2}' \
    > "$version_temporary"
mv -f "$version_temporary" "$PUBLISH_DIR/version"
echo "==> Published Files to $PUBLISH_DIR/vinix-files"
echo "    A running desktop VM with Files sync installed will pick it up shortly."
