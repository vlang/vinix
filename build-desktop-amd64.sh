#!/bin/bash
# Build the native Vinix desktop for amd64 and assemble a dedicated boot ISO.
#
# The amd64 distribution uses its mlibc cross-toolchain, unlike the Linux/musl
# ABI used by the aarch64 image. Run `make all` first so sysroot, the host cross
# compiler, Limine and the base ISO tree are available.
#
# Usage: ./build-desktop-amd64.sh [--no-iso]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AMD64_DESKTOP_BUILD_DIR:-$SCRIPT_DIR/build-amd64-desktop}"
SYSROOT="${VINIX_AMD64_SYSROOT:-$SCRIPT_DIR/sysroot}"
CROSS_CC="${VINIX_AMD64_CC:-$SCRIPT_DIR/host-pkgs/gcc/usr/local/bin/x86_64-vinix-mlibc-gcc}"
BASE_ISO_ROOT="${VINIX_AMD64_BASE_ISO_ROOT:-$SCRIPT_DIR/iso_root}"
LIMINE="${VINIX_AMD64_LIMINE:-$SCRIPT_DIR/host-pkgs/limine/usr/local/bin/limine}"
OUTPUT_ISO="${VINIX_AMD64_DESKTOP_ISO:-$SCRIPT_DIR/vinix-desktop-amd64.iso}"
MAKE_ISO=1

for arg in "$@"; do
    case "$arg" in
        --no-iso) MAKE_ISO=0 ;;
        --help|-h)
            sed -n '2,/^set -/s/^# \{0,1\}//p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

V="${V:-}"
if [ -z "$V" ] && [ -x "$SCRIPT_DIR/host-pkgs/v/usr/local/bin/v" ]; then
    V="$SCRIPT_DIR/host-pkgs/v/usr/local/bin/v"
fi
. "$SCRIPT_DIR/build-support/find-v.sh"

if [ "$(uname -s)" != Linux ]; then
    echo "ERROR: the amd64 distro toolchain is built by Jinx on a Linux host." >&2
    echo "Run this script on Linux after 'make all'." >&2
    exit 1
fi
case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe desktop build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac
if [ ! -x "$CROSS_CC" ] || [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: the amd64 cross-toolchain and sysroot are not built." >&2
    echo "Run 'make all' first, or set VINIX_AMD64_CC and VINIX_AMD64_SYSROOT." >&2
    exit 1
fi
if [ ! -f "$SCRIPT_DIR/third_party/ui2/v.mod" ]; then
    echo "ERROR: ui2 not found at third_party/ui2. Clone it there:" >&2
    echo "    git clone https://github.com/vlang/ui2 third_party/ui2" >&2
    exit 1
fi
if [ ! -f "$SCRIPT_DIR/third_party/ui2/ui/vml_compiled.v" ] || \
   [ ! -f "$SCRIPT_DIR/third_party/ui2/examples/calculator/calculator.vml" ]; then
    echo "ERROR: this ui2 checkout has no compile-time VML support; update it." >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
UI2_MODULES="$BUILD_DIR/vmodules"
python3 "$SCRIPT_DIR/desktop/tools/stage_ui2.py" \
    "$UI2_MODULES/ui2" "$SCRIPT_DIR/third_party/ui2" \
    "$SCRIPT_DIR/desktop/tools/ui2_headless_bounds.v"

echo "==> Staging desktop sources..."
APP_SRC="$BUILD_DIR/app-src"
python3 "$SCRIPT_DIR/desktop/tools/stage_app.py" "$APP_SRC" "$SCRIPT_DIR/desktop" \
    "$SCRIPT_DIR/third_party/ui2/examples/calculator"

echo "==> Building vinix-desktop for x86_64-vinix-mlibc..."
BUILD_STAMP="${VINIX_BUILD_STAMP:-$(date '+%m-%d %H:%M')}"
VCROSS_COMPILER_NAME="$CROSS_CC" "$V" \
    -os vinix -arch x64 -cc "$CROSS_CC" \
    -gc none -manualfree -enable-globals -prod \
    -cflags "--sysroot=$SYSROOT" -ldflags "--sysroot=$SYSROOT" \
    -d ui2_headless \
    -d "vinix_build_stamp=$BUILD_STAMP" \
    -path "@vlib|@vmodules|$UI2_MODULES|$SCRIPT_DIR|$SCRIPT_DIR/third_party" \
    -o "$BUILD_DIR/vinix-desktop" "$APP_SRC"
STRIP="${VINIX_AMD64_STRIP:-$SCRIPT_DIR/host-pkgs/binutils/usr/local/bin/x86_64-vinix-mlibc-strip}"
if [ ! -x "$STRIP" ]; then
    echo "ERROR: amd64 cross-strip tool not found at $STRIP" >&2
    exit 1
fi
"$STRIP" "$BUILD_DIR/vinix-desktop"

echo "==> Staging the amd64 desktop initramfs..."
STAGING="$BUILD_DIR/initramfs-root"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -a "$SYSROOT/." "$STAGING/"
mkdir -p "$STAGING/usr/bin" "$STAGING/usr/share/vinix/wallpapers" \
    "$STAGING/root/desktop" "$STAGING/run"
install -m755 "$BUILD_DIR/vinix-desktop" "$STAGING/usr/bin/vinix-desktop"
install -m755 "$SCRIPT_DIR/build-support/init-amd64/desktop-init" "$STAGING/usr/bin/init"

# One immutable multicall image, with the same per-application process names as
# the aarch64 desktop image.
for app_name in vinix-files vinix-calculator vinix-terminal vinix-settings \
    vinix-activity vinix-editor vinix-calendar vinix-clock vinix-cocoa-calculator \
    vinix-minecraft vinix-wine-calculator vinix-wine-notepad vinix-wine-word2010; do
    ln -sf vinix-desktop "$STAGING/usr/bin/$app_name"
done

echo "==> Wallpapers..."
python3 "$SCRIPT_DIR/desktop/tools/fetch_wallpapers.py" "$BUILD_DIR/wallpapers" \
    --cache "$BUILD_DIR/wallpapers-cache" || true
if [ -d "$BUILD_DIR/wallpapers" ]; then
    cp "$BUILD_DIR/wallpapers"/*.vwp "$BUILD_DIR/wallpapers"/index.txt \
        "$BUILD_DIR/wallpapers"/SOURCES.txt \
        "$STAGING/usr/share/vinix/wallpapers/" 2>/dev/null || true
fi
cp "$SCRIPT_DIR/desktop"/*.v "$SCRIPT_DIR/desktop"/*.c "$SCRIPT_DIR/desktop"/*.h \
    "$SCRIPT_DIR/desktop/README.md" "$STAGING/root/desktop/"

INITRAMFS="$BUILD_DIR/initramfs-desktop.tar"
INITRAMFS_TMP="$(mktemp "$BUILD_DIR/.initramfs-desktop.tar.XXXXXX")"
trap 'rm -f "$INITRAMFS_TMP"' EXIT
tar --format=ustar -cf "$INITRAMFS_TMP" -C "$STAGING" .
mv -f "$INITRAMFS_TMP" "$INITRAMFS"
trap - EXIT
echo "    $INITRAMFS ($(wc -c < "$INITRAMFS" | tr -d ' ') bytes)"

if [ "$MAKE_ISO" -eq 0 ]; then
    exit 0
fi
if [ ! -f "$BASE_ISO_ROOT/boot/limine-bios-cd.bin" ] || [ ! -x "$LIMINE" ]; then
    echo "ERROR: the base ISO tree or Limine host tool is missing." >&2
    echo "Run 'make all' first, or use --no-iso." >&2
    exit 1
fi
command -v xorriso >/dev/null 2>&1 || {
    echo "ERROR: xorriso is required to assemble $OUTPUT_ISO" >&2
    exit 1
}

echo "==> Assembling $OUTPUT_ISO..."
DESKTOP_ISO_ROOT="$BUILD_DIR/iso-root"
rm -rf "$DESKTOP_ISO_ROOT"
mkdir -p "$DESKTOP_ISO_ROOT"
cp -a "$BASE_ISO_ROOT/." "$DESKTOP_ISO_ROOT/"
install -m644 "$INITRAMFS" "$DESKTOP_ISO_ROOT/boot/initramfs.tar"

OUTPUT_ISO_TMP="$(mktemp "$(dirname "$OUTPUT_ISO")/.vinix-desktop-amd64.iso.XXXXXX")"
trap 'rm -f "$OUTPUT_ISO_TMP"' EXIT
xorriso -as mkisofs -R -r -J -b boot/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
    -apm-block-size 2048 --efi-boot boot/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$DESKTOP_ISO_ROOT" -o "$OUTPUT_ISO_TMP"
"$LIMINE" bios-install "$OUTPUT_ISO_TMP"
mv -f "$OUTPUT_ISO_TMP" "$OUTPUT_ISO"
trap - EXIT
echo "    $OUTPUT_ISO ($(wc -c < "$OUTPUT_ISO" | tr -d ' ') bytes)"
