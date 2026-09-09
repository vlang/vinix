#!/bin/bash
# Stage an unmodified Alpine x86_64 minirootfs for Vinix and create an
# initramfs that boots directly into Alpine BusyBox.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AMD64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-amd64-userland}"
ALPINE_VERSION="${ALPINE_VERSION:-3.21.7}"
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.21}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ALPINE_SHA256="${ALPINE_SHA256:-8cba1ea3e8b500ea986a313d8eecf3d5952a2a0d23a69117bb81c023d9ceac05}"
ARCHIVE="alpine-minirootfs-${ALPINE_VERSION}-x86_64.tar.gz"
ARCHIVE_PATH="$BUILD_DIR/$ARCHIVE"
STAGING="$BUILD_DIR/staging"
INITRAMFS="$BUILD_DIR/initramfs.tar"

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe amd64 userland build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac

mkdir -p "$BUILD_DIR"
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "==> Fetching Alpine ${ALPINE_VERSION} x86_64 minirootfs..."
    curl -fL "$ALPINE_MIRROR/$ALPINE_BRANCH/releases/x86_64/$ARCHIVE" \
        -o "$ARCHIVE_PATH"
fi

if command -v sha256sum >/dev/null 2>&1; then
    ARCHIVE_ACTUAL_SHA256="$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')"
else
    ARCHIVE_ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
fi
if [ "$ARCHIVE_ACTUAL_SHA256" != "$ALPINE_SHA256" ]; then
    echo "ERROR: Alpine minirootfs checksum mismatch." >&2
    echo "Expected: $ALPINE_SHA256" >&2
    echo "Actual:   $ARCHIVE_ACTUAL_SHA256" >&2
    exit 1
fi

echo "==> Staging the Alpine amd64 userland..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
tar -xzf "$ARCHIVE_PATH" -C "$STAGING"

# Vinix starts /sbin/init itself. Use Alpine's unmodified /bin/busybox through
# its normal /bin/sh applet and leave an interactive shell after the smoke
# marker, which also makes this image useful for manual compatibility checks.
rm -f "$STAGING/sbin/init"
install -m755 "$SCRIPT_DIR/build-support/init-amd64/alpine-init" \
    "$STAGING/sbin/init"
mkdir -p "$STAGING/dev" "$STAGING/proc" "$STAGING/sys" "$STAGING/tmp"
chmod 1777 "$STAGING/tmp"

INITRAMFS_TMP="$(mktemp "$BUILD_DIR/.initramfs.tar.XXXXXX")"
trap 'rm -f "$INITRAMFS_TMP"' EXIT
tar --format=ustar -cf "$INITRAMFS_TMP" -C "$STAGING" .
mv -f "$INITRAMFS_TMP" "$INITRAMFS"
trap - EXIT

echo "    $INITRAMFS ($(wc -c < "$INITRAMFS" | tr -d ' ') bytes)"
file "$STAGING/bin/busybox" "$STAGING/lib/ld-musl-x86_64.so.1"
