#!/bin/bash
# Stage Chromium and its Linux/aarch64 runtime for Vinix.
#
# Chromium is a multi-process browser whose Linux port assumes namespaces,
# seccomp-bpf and procfs. Vinix supplies the last of those and run-chromium
# turns the other two off, so the Alpine musl build runs as ordinary userspace
# processes; no Chromium ABI is implemented in the kernel or native desktop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_CHROMIUM_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-chromium}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"

# Track the branch `pkg` installs from at runtime, so a staged image and a
# `pkg install chromium` on a booted system produce the same browser.
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.21}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}/$ALPINE_BRANCH"
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

# chromium pulls GTK, X11, NSS and the media codecs through its own dependency
# closure. The extra roots are what a browser needs but Alpine does not make
# Chromium depend on: the system TLS bundle and a font with wide coverage.
# chromium-swiftshader supplies the CPU Vulkan device ANGLE falls back to when
# Vinix has no GPU driver for the guest.
ROOT_PACKAGES=(
    chromium
    chromium-swiftshader
    ca-certificates
    font-dejavu
    adwaita-icon-theme
)

echo "=== resolving chromium for Vinix/$ALPINE_ARCH ($ALPINE_BRANCH) ==="
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
    # APK signature, metadata and payload are concatenated tar streams. The
    # host tar can report the trailing stream even after extracting correctly.
    tar xzf "$archive" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

# Absolute library links from an APK would otherwise point into the build host,
# and Vinix's musl loader opens shared objects with O_NOFOLLOW. Materialise file
# links as hard links; Vinix's ustar unpacker preserves them, so Chromium's
# large shared objects are not duplicated in the image.
find "$STAGING" -type l | while IFS= read -r link; do
    target="$(readlink "$link")"
    case "$target" in
        /*) real="$STAGING$target" ;;
        *)  real="$(dirname "$link")/$target" ;;
    esac
    if [ -f "$real" ]; then
        rm "$link"
        ln "$real" "$link"
    fi
done

mkdir -p "$STAGING/usr/bin" "$STAGING/root" "$STAGING/usr/share/vinix" \
    "$STAGING/etc/chromium/policies/managed"
install -m755 "$SCRIPT_DIR/build-support/chromium/run-chromium" \
    "$STAGING/usr/bin/run-chromium"
install -m644 "$SCRIPT_DIR/tests/chromium/smoke.html" \
    "$STAGING/usr/share/vinix/chromium-smoke.html"
install -m644 "$SCRIPT_DIR/tests/chromium/smoke.html" \
    "$STAGING/root/chromium-smoke.html"
install -m644 "$SCRIPT_DIR/build-support/chromium/policies.json" \
    "$STAGING/etc/chromium/policies/managed/vinix.json"

if [ ! -x "$STAGING/usr/lib/chromium/chrome" ]; then
    echo "ERROR: the staged package has no Chromium application binary" >&2
    exit 1
fi
if [ ! -e "$STAGING/usr/bin/chromium" ] \
    && [ ! -e "$STAGING/usr/bin/chromium-browser" ]; then
    echo "ERROR: the staged package has no Chromium launcher" >&2
    exit 1
fi

echo
echo "staged packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
echo "staged size: $(du -sh "$STAGING" | cut -f1)"
echo "manifest: $BUILD_DIR/packages"
echo "launcher: /usr/bin/run-chromium"
