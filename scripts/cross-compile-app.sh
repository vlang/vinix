#!/bin/bash
# Build the committed desktop for AArch64 and publish it as one or more native
# applications to running QEMU guests:
#
#   ./scripts/cross-compile-app.sh files activity settings
#
# Every native application is an exec name of the one multicall desktop, so a
# single build serves all of them. Guests started with the current desktop
# image poll the host package server and install each published binary at
# /usr/bin/vinix-<app> without restarting Vinix; reopening the app runs it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPS_DIR="$SCRIPT_DIR/build-aarch64-desktop-apps"
BUILD_CACHE="$APPS_DIR/app-cross-cache"
SYSROOT="${VINIX_AARCH64_SYSROOT:-$SCRIPT_DIR/build-aarch64-userland/staging}"

# The applications a guest knows how to replace. Adding one here also needs it
# in LIVE_APPS in tools/qemu-package-store.py, in build-support/vinix-files-sync
# and in LiveApp entries in build-support/init-aarch64/initcore/core.v.
if [ "$#" -eq 0 ]; then
    echo "usage: $0 files|activity|settings..." >&2
    exit 2
fi
for app in "$@"; do
    case "$app" in
        files|activity|settings) ;;
        *)
            echo "ERROR: $app cannot be published to a running guest (files, activity, settings)" >&2
            exit 2
            ;;
    esac
done

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

mkdir -p "$BUILD_CACHE"
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
# The half-published files of the app being published, if a publish stops.
temporary=
version_temporary=
clean_up() {
    [ -z "$temporary" ] || rm -f "$temporary"
    [ -z "$version_temporary" ] || rm -f "$version_temporary"
    release_lock
}
trap clean_up EXIT

# A post-commit build must use the committed sources. Other work in the shared
# checkout may be uncommitted or even temporarily uncompilable.
revision=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
echo "==> Cross-compiling $* from ${revision:0:8}"
if [ ! -d "$SNAPSHOT" ] || [ "$(cat "$BUILD_CACHE/source-revision" 2>/dev/null || true)" != "$revision" ]; then
    rm -rf "$SNAPSHOT"
    mkdir -p "$SNAPSHOT"
    git -C "$SCRIPT_DIR" archive "$revision" | tar -xf - -C "$SNAPSHOT"
    printf '%s\n' "$revision" > "$BUILD_CACHE/source-revision"
fi
VINIX_UI2_SOURCE="$UI2_SOURCE" \
VINIX_AARCH64_SYSROOT="$SYSROOT" \
VINIX_AARCH64_APP_CACHE="$BUILD_CACHE" \
    "$SNAPSHOT/scripts/build-desktop-aarch64.sh" --no-initramfs

binary="$SNAPSHOT/build/vinix-desktop"
if [ ! -s "$binary" ]; then
    echo "ERROR: cross-build produced no desktop executable" >&2
    exit 1
fi

# Publish even when a newer commit has landed meanwhile: that commit may not
# touch these applications, and so may never build them. Builds hold the lock
# until they have published, so a later build's binary still lands last.
#
# The complete binary goes up before its version. The guest verifies the
# checksum, then atomically replaces only that application's executable.
for app in "$@"; do
    publish_dir="$APPS_DIR/$app-live"
    mkdir -p "$publish_dir"
    temporary="$publish_dir/.vinix-$app.$$"
    cp "$binary" "$temporary"
    chmod 755 "$temporary"
    mv -f "$temporary" "$publish_dir/vinix-$app"
    version_temporary="$publish_dir/.version.$$"
    cksum "$publish_dir/vinix-$app" | awk '{print $1, $2}' > "$version_temporary"
    mv -f "$version_temporary" "$publish_dir/version"
    echo "==> Published $app to $publish_dir/vinix-$app"
done
echo "    A running desktop VM with app sync installed will pick it up shortly;"
echo "    reopen the app to run the new build."
