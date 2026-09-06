#!/bin/bash
# Stage a CPython 3 for the Vinix aarch64 userland.
#
# Nothing is compiled here: Alpine already ships a musl aarch64 python3, which
# is the same libc and architecture the Vinix userland uses, so its packages
# drop straight into the initramfs. Building CPython from source in the guest
# would take hours and prove nothing extra.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_PYTHON_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-python}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"
ALPINE_ARCH=aarch64

mkdir -p "$DOWNLOADS" "$STAGING"

download_apk() {
    local repo="$1" pkg="$2"
    local index_file="$DOWNLOADS/${repo}_APKINDEX"

    if [ ! -f "$index_file" ]; then
        echo "  fetching ${repo} index"
        curl -sL "${ALPINE_MIRROR}/${repo}/${ALPINE_ARCH}/APKINDEX.tar.gz" \
            | tar xz -C "$DOWNLOADS" APKINDEX
        mv "$DOWNLOADS/APKINDEX" "$index_file"
    fi

    local filename
    filename=$(awk -v pkg="$pkg" '
        /^P:/{name=$0; sub(/^P:/,"",name)}
        /^V:/{ver=$0; sub(/^V:/,"",ver)}
        /^$/{if(name==pkg) print name "-" ver ".apk"}
    ' "$index_file")

    if [ -z "$filename" ]; then
        echo "  WARNING: $pkg not in ${repo}, skipping"
        return 1
    fi

    local local_file="$DOWNLOADS/${filename}"
    if [ ! -f "$local_file" ]; then
        echo "  downloading ${filename}"
        curl -sL -o "$local_file" "${ALPINE_MIRROR}/${repo}/${ALPINE_ARCH}/${filename}"
    fi

    echo "  extracting ${filename}"
    tar xzf "$local_file" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"*
}

# python3 itself, then everything its extension modules dlopen or link against.
# Without these the interpreter starts but importing half the standard library
# fails, which is worse than not having it.
PKGS=(
    python3
    python3-pyc
    libffi
    libbz2
    libcrypto3
    libssl3
    expat
    xz-libs
    zlib
    sqlite-libs
    readline
    ncurses-libs
    ncurses-terminfo-base
    mpdecimal
    gdbm
)

echo "=== staging python3 for $ALPINE_ARCH ==="
for pkg in "${PKGS[@]}"; do
    download_apk main "$pkg" || download_apk community "$pkg" || true
done

# Alpine ships some libraries as absolute symlinks, which resolve on the host
# rather than in the guest. Replace them with the file they name.
find "$STAGING" -type l | while IFS= read -r link; do
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

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
if [ -x "$STAGING/usr/bin/python3" ]; then
    echo "interpreter: $(ls -l "$STAGING"/usr/bin/python3* | head -3)"
else
    echo "WARNING: no python3 binary in the staging tree"
fi
