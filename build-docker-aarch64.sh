#!/bin/bash
# Stage the Docker engine, CLI, containerd and runc for the Vinix aarch64
# userland, together with an offline busybox image for the smoke test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_DOCKER_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-docker}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
IMAGE_ROOT="$BUILD_DIR/image-root"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64

for tool in curl python3 tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

mkdir -p "$DOWNLOADS"
rm -rf "$STAGING" "$IMAGE_ROOT"
mkdir -p "$STAGING" "$IMAGE_ROOT"

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

# Extract every package a resolver run lists into one directory.
stage_packages() {
    local destination="$1" list="$2" repository filename archive
    shift 2
    python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
        --index main "$DOWNLOADS/main_APKINDEX" \
        --index community "$DOWNLOADS/community_APKINDEX" \
        "$@" > "$list"

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
        tar xzf "$archive" -C "$destination" 2>/dev/null || true
        rm -f "$destination/.PKGINFO" "$destination/.SIGN"* \
            "$destination/.trigger"* "$destination/.pre-"* "$destination/.post-"*
    done < "$list"
}

echo "=== resolving Docker for $ALPINE_ARCH ==="
stage_packages "$STAGING" "$BUILD_DIR/packages" \
    docker-engine docker-cli containerd runc tini-static ca-certificates-bundle

# Vinix's dynamic loader currently needs shared-object aliases to be regular
# files. Leave command symlinks intact, but materialize library aliases.
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

for binary in dockerd docker containerd containerd-shim-runc-v2 runc; do
    if [ ! -x "$STAGING/usr/bin/$binary" ]; then
        echo "missing staged Docker component: $binary" >&2
        exit 1
    fi
done

# The smoke test must not depend on a registry, so it loads a busybox image
# assembled here from Alpine's statically linked busybox.
echo "=== assembling the offline busybox test image ==="
stage_packages "$IMAGE_ROOT" "$BUILD_DIR/image-packages" busybox-static
python3 "$SCRIPT_DIR/build-support/make-docker-image.py" \
    --busybox "$IMAGE_ROOT/bin/busybox.static" \
    --output "$BUILD_DIR/busybox-rootfs.tar"

mkdir -p "$STAGING/usr/share/vinix-docker" "$STAGING/root" \
    "$STAGING/etc/docker"
install -m644 "$BUILD_DIR/busybox-rootfs.tar" \
    "$STAGING/usr/share/vinix-docker/busybox-rootfs.tar"
install -m755 "$SCRIPT_DIR/tests/docker/smoke.sh" "$STAGING/root/docker-smoke.sh"
install -m755 "$SCRIPT_DIR/build-support/docker/vinix-dockerd" \
    "$STAGING/usr/bin/vinix-dockerd"
install -m644 "$SCRIPT_DIR/build-support/docker/daemon.json" \
    "$STAGING/etc/docker/daemon.json"

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
echo "packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
