#!/bin/bash
# Stage network-facing developer tools for the Vinix aarch64 userland.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_NETWORK_TOOLS_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-network-tools}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64

for tool in curl python3 tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

mkdir -p "$DOWNLOADS"
rm -rf "$STAGING"
mkdir -p "$STAGING"

for repository in main community; do
    index="$DOWNLOADS/${repository}_APKINDEX"
    if [ ! -f "$index" ]; then
        echo "  fetching ${repository} index"
        archive="$DOWNLOADS/${repository}_APKINDEX.tar.gz"
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/APKINDEX.tar.gz"
        tar xOf "$archive" APKINDEX > "$index"
    fi
done

ROOT_PACKAGES=(
    alpine-keys
    apk-tools
    ca-certificates
    ca-certificates-bundle
    curl
    git
    openssh-client-default
    openssh-keygen
    xbps
)

echo "=== resolving network developer tools for $ALPINE_ARCH ==="
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$DOWNLOADS/main_APKINDEX" \
    --index community "$DOWNLOADS/community_APKINDEX" \
    "${ROOT_PACKAGES[@]}" > "$BUILD_DIR/packages"

while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    archive="$DOWNLOADS/$filename"
    if [ ! -f "$archive" ]; then
        echo "  downloading $filename"
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/$filename"
    fi
    echo "  extracting $filename"
    # An apk contains concatenated tar streams (signature, metadata, payload).
    # bsdtar extracts the payload but can return non-zero after it; validate the
    # resulting tools below instead of treating that final warning as failure.
    tar xzf "$archive" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

mkdir -p "$STAGING/etc/apk" "$STAGING/lib/apk/db" \
    "$STAGING/var/cache/apk" "$STAGING/etc/xbps.d" "$STAGING/root"
printf '%s\n' \
    "$ALPINE_MIRROR/main" \
    "$ALPINE_MIRROR/community" \
    > "$STAGING/etc/apk/repositories"
printf '%s\n' "$ALPINE_ARCH" > "$STAGING/etc/apk/arch"
: > "$STAGING/lib/apk/db/installed"
: > "$STAGING/lib/apk/db/triggers"
: > "$STAGING/etc/apk/world"
# apk's database loader expects an empty tar archive even before any package
# scripts have been installed. Two 512-byte zero records are an empty tar.
dd if=/dev/zero of="$STAGING/lib/apk/db/scripts.tar" bs=1024 count=1 2>/dev/null
printf '%s\n' \
    'repository=https://repo-default.voidlinux.org/current/aarch64' \
    > "$STAGING/etc/xbps.d/00-repository-main.conf"

install -m755 "$SCRIPT_DIR/tests/network/tools-smoke.sh" \
    "$STAGING/root/network-tools-smoke.sh"

# musl opens shared objects without following links on Vinix. Materialize
# library links, but preserve Git's many executable links to its main binary.
find "$STAGING/lib" "$STAGING/usr/lib" -type l 2>/dev/null | \
while IFS= read -r link; do
    target=$(readlink "$link")
    case "$target" in
        /*) real="$STAGING$target" ;;
        *)  real="$(dirname "$link")/$target" ;;
    esac
    if [ -f "$real" ]; then
        rm "$link"
        cp "$real" "$link"
    fi
done

for binary in curl git ssh apk xbps-query; do
    if [ ! -x "$STAGING/usr/bin/$binary" ] \
        && [ ! -x "$STAGING/usr/sbin/$binary" ] \
        && [ ! -x "$STAGING/sbin/$binary" ]; then
        echo "missing staged binary: $binary" >&2
        exit 1
    fi
done

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
echo "packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
