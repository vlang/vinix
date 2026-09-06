#!/bin/bash
# Cross-compile the Vinix desktop environment for aarch64 and stage it into an
# initramfs that boots straight into it.
#
# Usage: ./build-desktop-aarch64.sh [--no-initramfs]
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
BASE_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar"
DESKTOP_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar"

MAKE_INITRAMFS=1
for arg in "$@"; do
    case "$arg" in
        --no-initramfs) MAKE_INITRAMFS=0 ;;
    esac
done

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
"$V" -os linux -gc none -enable-globals -prod \
    -d ui2_headless \
    -path "@vlib|@vmodules|$SCRIPT_DIR/third_party" \
    -o "$BUILD_DIR/desktop.c" "$APP_SRC"

# ── C -> aarch64 static binary ──
echo "==> Compiling for aarch64-linux-musl..."
"$LLVM_BIN/clang" --target=aarch64-linux-musl -static -nostdinc -nostdlib \
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

echo "==> Building the desktop init..."
"$LLVM_BIN/clang" --target=aarch64-linux-none -nostdlib -ffreestanding -O2 -c \
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
chmod +x "$STAGING/sbin/init" "$STAGING/usr/bin/vinix-desktop"

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
ln -sf busybox "$STAGING/bin/sh"

# COPYFILE_DISABLE keeps macOS from adding ._ resource-fork members that the
# kernel's tar reader would try to unpack as real files.
COPYFILE_DISABLE=1 tar --format=ustar -cf "$DESKTOP_INITRAMFS" -C "$STAGING" .
echo "    $DESKTOP_INITRAMFS ($(stat -f%z "$DESKTOP_INITRAMFS") bytes)"
