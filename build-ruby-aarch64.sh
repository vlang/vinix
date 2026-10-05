#!/bin/bash
# Stage Ruby for the Vinix aarch64 userland from Alpine's musl packages.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_RUBY_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-ruby}"
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
        curl -sL -o "$local_file" \
            "${ALPINE_MIRROR}/${repo}/${ALPINE_ARCH}/${filename}"
    fi

    echo "  extracting ${filename}"
    tar xzf "$local_file" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"*
}

# Ruby itself, common developer tools, and the libraries used by its native
# standard-library extensions (OpenSSL, Psych, Fiddle, readline and GDBM).
PKGS=(
    ruby
    ruby-libs
    ruby-bundler
    ruby-rake
    ca-certificates
    gmp
    libucontext
    yaml
    libffi
    libgcc
    libcrypto3
    libssl3
    zlib
    gdbm
    readline
    ncurses-libs
    ncurses-terminfo-base
)

echo "=== staging Ruby for $ALPINE_ARCH ==="
for pkg in "${PKGS[@]}"; do
    download_apk main "$pkg" || download_apk community "$pkg" || true
done

mkdir -p "$STAGING/root"
install -m644 "$SCRIPT_DIR/tests/ruby/smoke.rb" "$STAGING/root/ruby-smoke.rb"

# Make absolute package symlinks self-contained in the staging tree.
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
if [ -x "$STAGING/usr/bin/ruby" ]; then
    echo "interpreter: $(ls -l "$STAGING"/usr/bin/ruby* | head -3)"
else
    echo "WARNING: no Ruby binary in the staging tree"
fi
