#!/bin/bash
# Assemble the amd64 Vinix userland from official Alpine binaries and create
# an initramfs that boots directly into Alpine BusyBox.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AMD64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-amd64-userland}"
DOWNLOADS="$BUILD_DIR/downloads"
ALPINE_VERSION="${ALPINE_VERSION:-3.21.7}"
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.21}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ALPINE_SHA256="${ALPINE_SHA256:-8cba1ea3e8b500ea986a313d8eecf3d5952a2a0d23a69117bb81c023d9ceac05}"
ALPINE_ARCH=x86_64
ALPINE_DEVTOOLS="${VINIX_ALPINE_DEVTOOLS:-0}"
ARCHIVE="alpine-minirootfs-${ALPINE_VERSION}-x86_64.tar.gz"
ARCHIVE_PATH="$BUILD_DIR/$ARCHIVE"
STAGING="$BUILD_DIR/staging"
INITRAMFS="${VINIX_AMD64_INITRAMFS:-$BUILD_DIR/initramfs.tar}"
REPOSITORY_ROOT="$ALPINE_MIRROR/$ALPINE_BRANCH"

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe amd64 userland build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac

for tool in curl file python3 tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing build tool: $tool" >&2
        exit 1
    fi
done

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

fetch_alpine_indexes() {
    local repository archive index
    for repository in main community; do
        archive="$DOWNLOADS/${repository}_APKINDEX.tar.gz"
        index="$DOWNLOADS/${repository}_APKINDEX"
        if [ ! -s "$index" ]; then
            echo "    fetching Alpine ${repository} index"
            curl -fL --retry 3 \
                "$REPOSITORY_ROOT/$repository/$ALPINE_ARCH/APKINDEX.tar.gz" \
                -o "$archive"
            tar xOf "$archive" APKINDEX > "$index"
        fi
    done
}

stage_alpine_packages() {
    local repository filename package_archive

    fetch_alpine_indexes
    python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
        --index main "$DOWNLOADS/main_APKINDEX" \
        --index community "$DOWNLOADS/community_APKINDEX" \
        "$@" > "$BUILD_DIR/packages"

    while IFS=$'\t' read -r repository filename; do
        [ -n "$filename" ] || continue
        package_archive="$DOWNLOADS/$filename"
        if [ ! -s "$package_archive" ]; then
            echo "    downloading $filename"
            curl -fL --retry 3 \
                "$REPOSITORY_ROOT/$repository/$ALPINE_ARCH/$filename" \
                -o "$package_archive"
        fi
        echo "    extracting $filename"
        # APK signatures, metadata, and payload are concatenated tar streams.
        # Extract the payload stream; BSD tar can report the trailing stream
        # after it has done so. Its short -i option is not portable here: it
        # can leave the payload unextracted on macOS.
        tar -xzf "$package_archive" -C "$STAGING" 2>/dev/null || true
        rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* \
            "$STAGING/.trigger"* "$STAGING/.pre-"* "$STAGING/.post-"*
    done < "$BUILD_DIR/packages"
}

mkdir -p "$BUILD_DIR" "$DOWNLOADS"
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "==> Fetching Alpine ${ALPINE_VERSION} x86_64 minirootfs..."
    curl -fL --retry 3 "$REPOSITORY_ROOT/releases/x86_64/$ARCHIVE" \
        -o "$ARCHIVE_PATH"
fi

ARCHIVE_ACTUAL_SHA256="$(sha256_file "$ARCHIVE_PATH")"
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

if [ "$ALPINE_DEVTOOLS" = 1 ]; then
    echo "==> Staging Alpine's prebuilt C/C++ toolchain..."
    stage_alpine_packages build-base
else
    echo "==> Skipping guest development tools (VINIX_ALPINE_DEVTOOLS=0)"
    : > "$BUILD_DIR/packages"
fi

echo "==> Staging Zsh, Vim, and Oh My Zsh..."
stage_alpine_packages zsh vim
"$SCRIPT_DIR/build-support/stage-oh-my-zsh.sh" "$STAGING" "$DOWNLOADS"

# Vinix starts /sbin/init itself. Use Alpine's unmodified /bin/busybox through
# its normal /bin/sh applet and leave an interactive shell after the smoke
# marker, which also makes this image useful for manual compatibility checks.
rm -f "$STAGING/sbin/init"
install -m755 "$SCRIPT_DIR/build-support/init-amd64/alpine-init" \
    "$STAGING/sbin/init"
mkdir -p "$STAGING/dev" "$STAGING/proc" "$STAGING/sys" "$STAGING/tmp"
chmod 1777 "$STAGING/tmp"

cat > "$STAGING/root/hello.c" << 'EOF'
#include <stdio.h>
int main(void) {
    puts("Hello from Alpine GCC on Vinix/amd64!");
    return 0;
}
EOF

if [ ! -x "$STAGING/bin/busybox" ] ||
   [ ! -e "$STAGING/lib/ld-musl-x86_64.so.1" ] ||
   [ ! -x "$STAGING/usr/bin/vim" ]; then
    echo "ERROR: Alpine base userland is incomplete" >&2
    exit 1
fi
if [ "$ALPINE_DEVTOOLS" = 1 ] && [ ! -x "$STAGING/usr/bin/gcc" ]; then
    echo "ERROR: Alpine build-base did not provide /usr/bin/gcc" >&2
    exit 1
fi

mkdir -p "$(dirname "$INITRAMFS")"
INITRAMFS_TMP="$(mktemp "$(dirname "$INITRAMFS")/.initramfs.tar.XXXXXX")"
trap 'rm -f "$INITRAMFS_TMP"' EXIT
tar --format=ustar -cf "$INITRAMFS_TMP" -C "$STAGING" .
mv -f "$INITRAMFS_TMP" "$INITRAMFS"
trap - EXIT

echo "    $INITRAMFS ($(wc -c < "$INITRAMFS" | tr -d ' ') bytes)"
file "$STAGING/bin/busybox" "$STAGING/lib/ld-musl-x86_64.so.1"
