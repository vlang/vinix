#!/bin/bash
# Build the native Vinix desktop for amd64 and assemble a dedicated boot ISO.
#
# The desktop is linked against the same official Alpine/musl packages as the
# base image. No Vinix-specific GCC, libc, or userspace build is required.
#
# Usage: ./build-desktop-amd64.sh [--no-iso]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AMD64_DESKTOP_BUILD_DIR:-$SCRIPT_DIR/build-amd64-desktop}"
USERLAND_DIR="${VINIX_AMD64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-amd64-userland}"
SYSROOT="${VINIX_AMD64_SYSROOT:-$USERLAND_DIR/staging}"
KERNEL_BUILD_DIR="${VINIX_AMD64_BUILD_DIR:-$SCRIPT_DIR/build-amd64-kernel}"
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
. "$SCRIPT_DIR/build-support/find-v.sh"

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe desktop build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac

CLANG="${VINIX_AMD64_CLANG:-}"
LLVM_STRIP="${VINIX_AMD64_STRIP:-}"
for llvm_prefix in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
    if [ -z "$CLANG" ] && [ -x "$llvm_prefix/clang" ]; then
        CLANG="$llvm_prefix/clang"
    fi
    if [ -z "$LLVM_STRIP" ] && [ -x "$llvm_prefix/llvm-strip" ]; then
        LLVM_STRIP="$llvm_prefix/llvm-strip"
    fi
done
CLANG="${CLANG:-$(command -v clang || true)}"
LLVM_STRIP="${LLVM_STRIP:-$(command -v llvm-strip || command -v strip || true)}"
if [ -z "$CLANG" ] || [ -z "$LLVM_STRIP" ] || ! command -v ld.lld >/dev/null 2>&1; then
    echo "ERROR: clang, ld.lld, and llvm-strip (or strip) are required." >&2
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

echo "==> Staging Alpine's prebuilt amd64 userland and toolchain..."
VINIX_AMD64_USERLAND_BUILD_DIR="$USERLAND_DIR" VINIX_ALPINE_DEVTOOLS=1 \
    "$SCRIPT_DIR/build-userland-amd64.sh"
if [ ! -f "$SYSROOT/usr/lib/libc.a" ] || [ ! -d "$SYSROOT/usr/include" ]; then
    echo "ERROR: Alpine development sysroot is incomplete: $SYSROOT" >&2
    exit 1
fi
GCCLIB="$(find "$SYSROOT/usr/lib/gcc/x86_64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1)"
if [ -z "$GCCLIB" ] || [ ! -f "$GCCLIB/libgcc.a" ]; then
    echo "ERROR: Alpine GCC runtime not found below $SYSROOT/usr/lib/gcc" >&2
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

echo "==> Translating the amd64 desktop to C..."
BUILD_STAMP="${VINIX_BUILD_STAMP:-$(date '+%m-%d %H:%M')}"
"$V" -new-compiler -os linux -arch x64 \
    -gc none -manualfree -enable-globals -prod \
    -d ui2_headless \
    -d "vinix_build_stamp=$BUILD_STAMP" \
    -path "@vlib|$UI2_MODULES|@vmodules|$SCRIPT_DIR|$SCRIPT_DIR/third_party" \
    -o "$BUILD_DIR/desktop.c" "$APP_SRC"

echo "==> Compiling for x86_64-linux-musl..."
"$CLANG" --target=x86_64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/usr/include" \
    -I "$APP_SRC" \
    -O2 -fno-stack-protector -w \
    "$SYSROOT/usr/lib/crt1.o" "$SYSROOT/usr/lib/crti.o" "$GCCLIB/crtbeginT.o" \
    "$BUILD_DIR/desktop.c" \
    -L"$SYSROOT/usr/lib" -L"$GCCLIB" -lc -lgcc -lm \
    "$GCCLIB/crtend.o" "$SYSROOT/usr/lib/crtn.o" \
    -fuse-ld=lld -o "$BUILD_DIR/vinix-desktop"
"$LLVM_STRIP" "$BUILD_DIR/vinix-desktop"

echo "==> Staging the amd64 desktop initramfs..."
STAGING="$BUILD_DIR/initramfs-root"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -a "$SYSROOT/." "$STAGING/"
mkdir -p "$STAGING/usr/bin" "$STAGING/usr/share/vinix/wallpapers" \
    "$STAGING/root/desktop" "$STAGING/run"
install -m755 "$BUILD_DIR/vinix-desktop" "$STAGING/usr/bin/vinix-desktop"
rm -f "$STAGING/sbin/init"
install -m755 "$SCRIPT_DIR/build-support/init-amd64/desktop-init" "$STAGING/sbin/init"

# One immutable multicall image, with the same per-application process names as
# the aarch64 desktop image.
for app_name in vinix-files vinix-calculator vinix-terminal vinix-settings \
    vinix-activity vinix-editor vinix-calendar vinix-clock vinix-cocoa-calculator \
    vinix-minecraft vinix-wine-calculator vinix-wine-notepad vinix-wine-word2010 \
    vinix-capture; do
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
VINIX_AMD64_BUILD_DIR="$KERNEL_BUILD_DIR" \
    "$SCRIPT_DIR/build-amd64.sh" --no-userland --no-iso
VINIX_AMD64_KERNEL="$KERNEL_BUILD_DIR/bin/vinix" \
VINIX_AMD64_INITRAMFS="$INITRAMFS" \
VINIX_AMD64_ISO="$OUTPUT_ISO" \
VINIX_AMD64_ISO_BUILD_DIR="$BUILD_DIR/iso" \
    "$SCRIPT_DIR/build-support/build-amd64-iso.sh"
