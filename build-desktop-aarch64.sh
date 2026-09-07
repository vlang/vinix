#!/bin/bash
# Cross-compile the Vinix desktop environment for aarch64 and stage it into an
# initramfs that boots straight into it.
#
# Usage: ./build-desktop-aarch64.sh [--no-initramfs] [--wifi-bundle=DIR]
#
# V translates the program to C; clang compiles that C against the static musl
# sysroot extracted from the userland image. The result is a freestanding
# static binary that needs nothing from the target but /dev/fb0 and
# /dev/pointer.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/build-support/find-v.sh"

BUILD_DIR="$SCRIPT_DIR/build"
SYSROOT="$SCRIPT_DIR/build-aarch64-musl/aarch64-linux-musl-native"
GCCLIB="$SYSROOT/lib/gcc/aarch64-linux-musl/11.2.1"
LLVM_BIN="/opt/homebrew/opt/llvm/bin"
# <stdatomic.h> has to be ours. See build-support/aarch64-cc-shim/stdatomic.h:
# -nostdinc leaves GCC 11's on the path, whose atomics clang rejects on the
# _Atomic pointers V generates, and clang's own header forwards straight back
# to it. This only started to matter when the desktop began importing os and
# time, which pull in sync.stdatomic.
CC_SHIM="$SCRIPT_DIR/build-support/aarch64-cc-shim"
BASE_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar"
DESKTOP_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar"

MAKE_INITRAMFS=1
WIFI_BUNDLE="${VINIX_WIFI_BUNDLE:-}"
for arg in "$@"; do
    case "$arg" in
        --no-initramfs) MAKE_INITRAMFS=0 ;;
        --wifi-bundle=*) WIFI_BUNDLE="${arg#*=}" ;;
        --help|-h)
            echo "usage: $0 [--no-initramfs] [--wifi-bundle=DIR]"
            echo "  --wifi-bundle stages a package.py output and loads it before the desktop"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$MAKE_INITRAMFS" -eq 0 ] && [ -n "$WIFI_BUNDLE" ]; then
    echo "ERROR: --wifi-bundle requires initramfs generation" >&2
    exit 1
fi

if [ -n "$WIFI_BUNDLE" ]; then
    for name in manifest.bin firmware.bin nvram.txt clm.blob txcap.blob; do
        if [ ! -f "$WIFI_BUNDLE/$name" ]; then
            echo "ERROR: Wi-Fi bundle is missing $WIFI_BUNDLE/$name" >&2
            exit 1
        fi
    done
fi

# ── The musl sysroot ──
# The aarch64 userland image carries a complete native musl toolchain; its
# headers and libraries are all a cross build needs, so they are unpacked here
# instead of rebuilding musl from source.
if [ ! -f "$SYSROOT/lib/libc.a" ]; then
    if [ ! -f "$BASE_INITRAMFS" ]; then
        echo "ERROR: $BASE_INITRAMFS not found."
        echo "Run ./build-userland-aarch64.sh first, or link the one from the main checkout."
        exit 1
    fi
    echo "==> Extracting the musl sysroot from the userland image..."
    mkdir -p "$SCRIPT_DIR/build-aarch64-musl"
    tar xf "$BASE_INITRAMFS" -C "$SCRIPT_DIR/build-aarch64-musl" \
        ./aarch64-linux-musl-native/include ./aarch64-linux-musl-native/lib
fi

# ── ui2 ──
# The desktop is built on ui2's declarative element tree. It is not vendored;
# check it out beside the sources and point V's module path at it.
if [ ! -f "$SCRIPT_DIR/third_party/ui2/v.mod" ]; then
    echo "ERROR: ui2 not found at third_party/ui2. Clone it there:"
    echo "    git clone https://github.com/vlang/ui2 third_party/ui2"
    exit 1
fi

# The desktop hosts ui2 applications through QmlApp, ui2's embeddable QML host.
# A checkout without it fails deep inside the V build with an error about an
# unknown type, which says nothing about the real problem.
if [ ! -f "$SCRIPT_DIR/third_party/ui2/ui/qml_embed.v" ]; then
    echo "ERROR: this ui2 checkout has no QmlApp (ui/qml_embed.v)."
    echo "The desktop hosts ui2 applications through it. Update the checkout:"
    echo "    git -C third_party/ui2 pull"
    exit 1
fi

if [ ! -x "$LLVM_BIN/clang" ]; then
    echo "ERROR: Homebrew LLVM not found at $LLVM_BIN (brew install llvm)"
    exit 1
fi

mkdir -p "$BUILD_DIR"

# ── Stage the sources ──
# The desktop hosts ui2 applications in its windows, and an application's model
# is V code that has to be compiled in. The staging step takes each example's
# source straight from the ui2 checkout — everything but its `fn main()`, which
# only opens a platform window — so what runs is the example itself.
echo "==> Staging sources..."
APP_SRC="$BUILD_DIR/app-src"
python3 "$SCRIPT_DIR/desktop/tools/stage_app.py" "$APP_SRC" "$SCRIPT_DIR/desktop" \
    "$SCRIPT_DIR/third_party/ui2/examples/calculator"

# ── V -> C ──
# -gc none because Vinix has no Boehm GC, and -d ui2_headless so importing ui2
# brings in its declarative core without its gg/Sokol backend.
echo "==> Translating V to C..."
# The build stamp the taskbar shows beside the clock. Deploying to real
# hardware and rebooting looks the same whether the new image landed or not,
# so the desktop says when it was built.
BUILD_STAMP="${VINIX_BUILD_STAMP:-$(date '+%m-%d %H:%M')}"
echo "    build stamp: $BUILD_STAMP"
"$V" -os linux -gc none -enable-globals -prod \
    -d ui2_headless \
    -d "vinix_build_stamp=$BUILD_STAMP" \
    -path "@vlib|@vmodules|$SCRIPT_DIR/third_party" \
    -o "$BUILD_DIR/desktop.c" "$APP_SRC"

# ── C -> aarch64 static binary ──
echo "==> Compiling for aarch64-linux-musl..."
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$CC_SHIM" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/include" \
    -I "$APP_SRC" \
    -O2 -fno-stack-protector -w \
    "$SYSROOT/lib/crt1.o" "$SYSROOT/lib/crti.o" "$GCCLIB/crtbegin.o" \
    "$BUILD_DIR/desktop.c" \
    -L"$SYSROOT/lib" -L"$GCCLIB" -lc -lgcc -lm \
    "$GCCLIB/crtend.o" "$SYSROOT/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" \
    -o "$BUILD_DIR/vinix-desktop"

"$LLVM_BIN/llvm-strip" "$BUILD_DIR/vinix-desktop"
echo "    $BUILD_DIR/vinix-desktop ($(stat -f%z "$BUILD_DIR/vinix-desktop") bytes)"

if [ "$MAKE_INITRAMFS" -eq 0 ]; then
    exit 0
fi

# ── Stage an initramfs that boots into the desktop ──
# A purpose-built image rather than an overlay on the full userland: the
# kernel's initramfs unpacker panics on a duplicate path, so a tar that
# appended a second /etc or /sbin/init could not be booted at all. Building
# the image from scratch also keeps it at a couple of megabytes.
if [ ! -f "$BASE_INITRAMFS" ]; then
    echo "ERROR: $BASE_INITRAMFS not found; it is where BusyBox comes from."
    exit 1
fi

# `package.py` produces the only supported bundle format. Its manifest binds
# the opaque vendor files to identity captured from the target, and wifi-ctl
# repeats that identity check on the M1 before uploading a byte.
echo "==> Building wifi-ctl for aarch64-linux-musl..."
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
    -isystem "$CC_SHIM" \
    -isystem "$GCCLIB/include" -isystem "$SYSROOT/include" \
    -iquote "$SCRIPT_DIR/kernel/c" \
    -std=c11 -O2 -fno-stack-protector -Wall -Wextra -Werror \
    "$SYSROOT/lib/crt1.o" "$SYSROOT/lib/crti.o" "$GCCLIB/crtbegin.o" \
    "$SCRIPT_DIR/tools/m1-wifi/wifi-ctl.c" \
    -L"$SYSROOT/lib" -L"$GCCLIB" -lc -lgcc \
    "$GCCLIB/crtend.o" "$SYSROOT/lib/crtn.o" \
    -fuse-ld=lld -B"$LLVM_BIN" \
    -o "$BUILD_DIR/wifi-ctl"
"$LLVM_BIN/llvm-strip" "$BUILD_DIR/wifi-ctl"
echo "    $BUILD_DIR/wifi-ctl ($(stat -f%z "$BUILD_DIR/wifi-ctl") bytes)"

echo "==> Building the desktop init..."
INIT_DEFINES=()
if [ -n "$WIFI_BUNDLE" ]; then
    INIT_DEFINES=(-DVINIX_WIFI_BUNDLE=1)
fi
"$LLVM_BIN/clang" --target=aarch64-linux-none -nostdlib -ffreestanding -O2 -c \
    "${INIT_DEFINES[@]}" \
    -o "$BUILD_DIR/desktop-init.o" \
    "$SCRIPT_DIR/build-support/init-aarch64/desktop-init.c"
# lld is installed as a separate formula, so it is on PATH rather than in
# the llvm keg the other tools come from.
"${LD_LLD:-ld.lld}" -m aarch64elf --nostdlib -static \
    -o "$BUILD_DIR/desktop-init" "$BUILD_DIR/desktop-init.o"

echo "==> Staging the desktop initramfs..."
STAGING="$BUILD_DIR/initramfs-root"
rm -rf "$STAGING"
mkdir -p "$STAGING/sbin" "$STAGING/bin" "$STAGING/usr/bin" "$STAGING/dev" \
    "$STAGING/tmp" "$STAGING/root"

cp "$BUILD_DIR/desktop-init" "$STAGING/sbin/init"
cp "$BUILD_DIR/vinix-desktop" "$STAGING/usr/bin/vinix-desktop"
cp "$BUILD_DIR/wifi-ctl" "$STAGING/usr/bin/wifi-ctl"
chmod +x "$STAGING/sbin/init" "$STAGING/usr/bin/vinix-desktop" \
    "$STAGING/usr/bin/wifi-ctl"

if [ -n "$WIFI_BUNDLE" ]; then
    echo "==> Staging the selected Wi-Fi firmware bundle..."
    mkdir -p "$STAGING/usr/share/vinix/wifi"
    for name in manifest.bin firmware.bin nvram.txt clm.blob txcap.blob; do
        cp "$WIFI_BUNDLE/$name" "$STAGING/usr/share/vinix/wifi/$name"
    done
    if [ -f "$WIFI_BUNDLE/provenance.json" ]; then
        cp "$WIFI_BUNDLE/provenance.json" "$STAGING/usr/share/vinix/wifi/provenance.json"
    fi
fi

# ── Wallpapers ──
# Vinix has no JPEG decoder, so the photographs are downloaded and decoded here
# and shipped as raw pixels. Downloads are cached, so this costs nothing after
# the first build; with neither network nor cache it writes none and the
# desktop offers only its colours.
echo "==> Wallpapers..."
python3 "$SCRIPT_DIR/desktop/tools/fetch_wallpapers.py" "$BUILD_DIR/wallpapers" \
    --cache "$BUILD_DIR/wallpapers-cache" || true

mkdir -p "$STAGING/usr/share/vinix/wallpapers"
if [ -d "$BUILD_DIR/wallpapers" ]; then
    cp "$BUILD_DIR/wallpapers"/*.vwp "$BUILD_DIR/wallpapers"/index.txt \
        "$BUILD_DIR/wallpapers"/SOURCES.txt "$STAGING/usr/share/vinix/wallpapers/" 2>/dev/null || true
fi

# The desktop's own source travels with the image, so the file browser has
# something real to show and so the machine carries the code it is running.
mkdir -p "$STAGING/root/desktop"
cp "$SCRIPT_DIR/desktop"/*.v "$SCRIPT_DIR/desktop/README.md" \
    "$STAGING/root/desktop/"

# BusyBox comes along so init has a shell to fall back to when the desktop
# exits or fails to start.
tar xf "$BASE_INITRAMFS" -C "$BUILD_DIR" ./bin/busybox
mv "$BUILD_DIR/bin/busybox" "$STAGING/bin/busybox"
rmdir "$BUILD_DIR/bin" 2>/dev/null || true
chmod +x "$STAGING/bin/busybox"
# BusyBox dispatches on argv[0], so an applet is a link to it. Without these a
# terminal can only run `busybox ls`, which is a poor sort of shell.
for applet in sh ls cat echo pwd cd mkdir rmdir rm cp mv ln touch head tail \
              grep wc sort uniq find du df date uname ps kill sleep env printf \
              basename dirname clear true false test more less hexdump; do
    ln -sf busybox "$STAGING/bin/$applet"
done

# COPYFILE_DISABLE keeps macOS from adding ._ resource-fork members that the
# kernel's tar reader would try to unpack as real files.
COPYFILE_DISABLE=1 tar --format=ustar -cf "$DESKTOP_INITRAMFS" -C "$STAGING" .
echo "    $DESKTOP_INITRAMFS ($(stat -f%z "$DESKTOP_INITRAMFS") bytes)"
