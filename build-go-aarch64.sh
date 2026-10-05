#!/bin/bash
# Stage the Go compiler and standard library for the Vinix aarch64 userland.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_GO_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-go}"
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

echo "=== resolving Go for $ALPINE_ARCH ==="
python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$DOWNLOADS/main_APKINDEX" \
    --index community "$DOWNLOADS/community_APKINDEX" \
    go ca-certificates-bundle > "$BUILD_DIR/packages"

while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    archive="$DOWNLOADS/$filename"
    if [ ! -f "$archive" ]; then
        echo "  downloading $filename"
        curl -fL --retry 3 -o "$archive" \
            "$ALPINE_MIRROR/$repository/$ALPINE_ARCH/$filename"
    fi
    echo "  extracting $filename"
    # APK signatures, metadata and payload are concatenated tar streams. The
    # host tar can report the trailing stream after extracting successfully.
    tar xzf "$archive" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

mkdir -p "$STAGING/root"
install -m644 "$SCRIPT_DIR/tests/go/smoke.go" "$STAGING/root/go-smoke.go"
install -m644 "$SCRIPT_DIR/tests/go/cgo.go" "$STAGING/root/go-cgo.go"
install -m755 "$SCRIPT_DIR/tests/go/smoke.sh" "$STAGING/root/go-smoke.sh"

# Vinix's dynamic loader currently needs shared-object aliases to be regular
# files. Leave Go's command symlinks intact, but materialize library aliases.
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

if [ ! -x "$STAGING/usr/bin/go" ] && [ ! -x "$STAGING/usr/lib/go/bin/go" ]; then
    echo "missing staged Go compiler" >&2
    exit 1
fi
if [ ! -x "$STAGING/usr/bin/gofmt" ] && [ ! -x "$STAGING/usr/lib/go/bin/gofmt" ]; then
    echo "missing staged gofmt" >&2
    exit 1
fi

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
echo "packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
