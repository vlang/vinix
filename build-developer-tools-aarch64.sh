#!/bin/bash
# Stage a native development environment for the Vinix aarch64 userland.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_DEVELOPER_TOOLS_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-developer-tools}"
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

# Keep this explicit: it is both the image manifest and the user-facing set of
# tools Vinix promises. Dependencies (including Perl/Python runtimes and all
# shared libraries) are resolved from the pinned Alpine release above.
ROOT_PACKAGES=(
    autoconf
    automake
    bash
    ca-certificates-bundle
    cmake
    coreutils
    diffutils
    file
    findutils
    gdb
    git
    grep
    libtool
    m4
    make
    meson
    patch
    pkgconf
    radare2
    samurai
    sed
    strace
    tar
    tmux
    xz
)

echo "=== resolving native developer tools for $ALPINE_ARCH ==="
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
    # APK signatures, metadata and payload are concatenated tar streams. The
    # host tar can report the trailing stream even after extracting correctly.
    tar xzf "$archive" -C "$STAGING" 2>/dev/null || true
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* "$STAGING/.trigger"* \
        "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

mkdir -p "$STAGING/root"
install -m755 "$SCRIPT_DIR/tests/developer-tools/smoke.sh" \
    "$STAGING/root/developer-tools-smoke.sh"

# Several GNU packages still install compatibility commands in /bin. The base
# image has BusyBox applet symlinks there, and a plain overlay copy would follow
# those destination links and overwrite BusyBox itself. Keep bash in /bin, move
# real GNU commands to /usr/bin, and let the base image retain its applets.
mkdir -p "$STAGING/usr/bin"
for entry in "$STAGING/bin/"*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=$(basename "$entry")
    [ "$name" = bash ] && continue
    if [ -f "$entry" ] && [ ! -L "$entry" ]; then
        rm -f "$STAGING/usr/bin/$name"
        mv "$entry" "$STAGING/usr/bin/$name"
    else
        rm -f "$entry"
    fi
done

# Vinix's dynamic loader currently needs shared-object aliases to be regular
# files. Preserve command aliases such as ninja -> samu and automake -> 1.17.
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

for binary in autoconf automake cmake diff file find gdb git grep \
    libtool m4 make meson ninja patch pkg-config r2 rabin2 radare2 sed strace \
    tar tmux xz; do
    if [ ! -x "$STAGING/usr/bin/$binary" ] \
        && [ ! -x "$STAGING/bin/$binary" ]; then
        echo "missing staged binary: $binary" >&2
        exit 1
    fi
done
if [ ! -x "$STAGING/bin/bash" ]; then
    echo "missing staged binary: bash" >&2
    exit 1
fi

echo
echo "staged: $(du -sh "$STAGING" | cut -f1)"
echo "packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
