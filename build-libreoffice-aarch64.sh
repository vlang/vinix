#!/bin/bash
# Stage LibreOffice and its Linux/aarch64 runtime for Vinix.
#
# LibreOffice's toolkit layer is VCL, which Alpine builds with a GTK 3 plugin
# (libreoffice-gtk). That is the same GTK the Firefox layer already qualifies,
# so the office suite runs as ordinary userspace on Vinix's hosted X11 display;
# no VCL or UNO ABI is implemented in the kernel or the native desktop.
#
# The suite also brings a UNO scripting runtime (python3) and a Qt 6 VCL plugin
# that libreoffice-common hard-depends on. Both come along in the closure; the
# launcher pins SAL_USE_VCLPLUGIN=gtk3 so the Qt plugin is never loaded.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_LIBREOFFICE_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-libreoffice}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"

# v3.22 is the branch the Firefox layer is on, and LibreOffice 25.2 wants the
# same ICU 76 and GTK 3 those packages carry. Mixing it with the v3.21 base
# userland is what the Firefox layer already does.
ALPINE_BRANCH="${ALPINE_BRANCH:-v3.22}"
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

# Writer and Calc are the two document types the desktop opens; both sit on
# the same 311 MiB libreoffice-common, so the second one is nearly free.
# libreoffice-gtk is the VCL plugin that draws them. The extra roots are what
# an office suite needs and Alpine does not make it depend on: metric-compatible
# document fonts, a UI icon theme, and a font with wide coverage.
ROOT_PACKAGES=(
    libreoffice-writer
    libreoffice-calc
    libreoffice-gtk
    libreoffice-lang-en_us
    ttf-liberation
    font-dejavu
    adwaita-icon-theme
)

echo "=== resolving LibreOffice for Vinix/$ALPINE_ARCH ($ALPINE_BRANCH) ==="
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
# links as hard links; Vinix's ustar unpacker preserves them, so LibreOffice's
# several hundred shared objects are not duplicated in the image.
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

mkdir -p "$STAGING/usr/bin" "$STAGING/root" "$STAGING/usr/share/vinix"
install -m755 "$SCRIPT_DIR/build-support/libreoffice/run-libreoffice" \
    "$STAGING/usr/bin/run-libreoffice"
# A persistent /root shadows whatever the image ships there, so the document
# the launcher opens lives under /usr/share as well as in the home directory.
install -m644 "$SCRIPT_DIR/build-support/libreoffice/welcome.fodt" \
    "$STAGING/usr/share/vinix/libreoffice-welcome.fodt"
install -m644 "$SCRIPT_DIR/build-support/libreoffice/welcome.fodt" \
    "$STAGING/root/libreoffice-welcome.fodt"
mkdir -p "$STAGING/etc/libreoffice"
install -m644 "$SCRIPT_DIR/build-support/libreoffice/vinix-registrymodifications.xcu" \
    "$STAGING/etc/libreoffice/vinix-registrymodifications.xcu"

# The launcher pins the GTK 3 plugin, so a missing one is a broken image
# rather than a silent fall back to a Qt plugin that needs a KDE session.
if [ ! -x "$STAGING/usr/lib/libreoffice/program/soffice.bin" ]; then
    echo "ERROR: the staged packages have no LibreOffice program binary" >&2
    exit 1
fi
if [ ! -e "$STAGING/usr/lib/libreoffice/program/libvclplug_gtk3lo.so" ]; then
    echo "ERROR: the staged packages have no GTK 3 VCL plugin" >&2
    exit 1
fi
if [ ! -e "$STAGING/usr/lib/libreoffice/program/libswlo.so" ]; then
    echo "ERROR: the staged packages have no Writer" >&2
    exit 1
fi

echo
echo "staged packages: $(wc -l < "$BUILD_DIR/packages" | tr -d ' ')"
echo "staged size: $(du -sh "$STAGING" | cut -f1)"
echo "manifest: $BUILD_DIR/packages"
echo "launcher: /usr/bin/run-libreoffice"
