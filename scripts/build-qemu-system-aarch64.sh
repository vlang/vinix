#!/bin/bash
# Stage a native AArch64 QEMU system emulator and UEFI firmware for Vinix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${VINIX_QEMU_SYSTEM_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-qemu-system}"
DOWNLOADS="$BUILD_DIR/downloads"
STAGING="$BUILD_DIR/staging"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine/v3.21}"

for tool in curl python3 tar; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing build tool: $tool" >&2
        exit 1
    }
done

mkdir -p "$DOWNLOADS"
for repository in main community; do
    index="$DOWNLOADS/${repository}_APKINDEX"
    if [ ! -f "$index" ]; then
        archive="$DOWNLOADS/${repository}_APKINDEX.tar.gz"
        curl -fsSL --retry 3 -o "$archive.partial" \
            "$ALPINE_MIRROR/$repository/aarch64/APKINDEX.tar.gz"
        mv "$archive.partial" "$archive"
        tar xOf "$archive" APKINDEX > "$index"
    fi
done

python3 "$SCRIPT_DIR/build-support/alpine-resolve.py" \
    --index main "$DOWNLOADS/main_APKINDEX" \
    --index community "$DOWNLOADS/community_APKINDEX" \
    qemu-system-aarch64 libx11 > "$BUILD_DIR/packages"

rm -rf "$STAGING"
mkdir -p "$STAGING"
while IFS=$'\t' read -r repository filename; do
    [ -n "$filename" ] || continue
    archive="$DOWNLOADS/$filename"
    if [ ! -f "$archive" ]; then
        echo "  downloading $filename"
        curl -fsSL --retry 3 -o "$archive.partial" \
            "$ALPINE_MIRROR/$repository/aarch64/$filename"
        mv "$archive.partial" "$archive"
    fi
    echo "  extracting $filename"
    tar xzf "$archive" -C "$STAGING"
    rm -f "$STAGING/.PKGINFO" "$STAGING/.SIGN"* \
        "$STAGING/.trigger"* "$STAGING/.pre-"* "$STAGING/.post-"*
done < "$BUILD_DIR/packages"

# Vinix's loader opens DT_NEEDED objects without following symlinks.
for directory in "$STAGING/lib" "$STAGING/usr/lib"; do
    [ -d "$directory" ] || continue
    find "$directory" -type l | while IFS= read -r link; do
        target="$(readlink "$link")"
        case "$target" in
            /*) real="$STAGING$target" ;;
            *) real="$(dirname "$link")/$target" ;;
        esac
        if [ -f "$real" ]; then
            rm "$link"
            cp "$real" "$link"
        fi
    done
done

if [ ! -x "$STAGING/usr/bin/qemu-system-aarch64" ]; then
    echo "QEMU package did not install qemu-system-aarch64" >&2
    exit 1
fi

# Alpine packages QEMU's UEFI descriptor, but not the firmware images it
# references. Copy the host QEMU firmware into the runtime layer.
find_firmware() {
    local name="$1" candidate
    for candidate in \
        "$SCRIPT_DIR/boot-image/$name" \
        /opt/homebrew/share/qemu/"$name" \
        /usr/local/share/qemu/"$name" \
        /usr/share/qemu/"$name"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}
FIRMWARE_CODE="${VINIX_QEMU_FIRMWARE_CODE:-$(find_firmware edk2-aarch64-code.fd || true)}"
FIRMWARE_VARS="${VINIX_QEMU_FIRMWARE_VARS:-$(find_firmware edk2-arm-vars.fd || true)}"
if [ ! -f "$FIRMWARE_CODE" ] || [ ! -f "$FIRMWARE_VARS" ]; then
    echo "AArch64 QEMU UEFI firmware is missing; install host QEMU or set" >&2
    echo "VINIX_QEMU_FIRMWARE_CODE and VINIX_QEMU_FIRMWARE_VARS." >&2
    exit 1
fi
install -m644 "$FIRMWARE_CODE" "$STAGING/usr/share/qemu/edk2-aarch64-code.fd"
install -m644 "$FIRMWARE_VARS" "$STAGING/usr/share/qemu/edk2-arm-vars.fd"
install -m755 "$SCRIPT_DIR/build-support/qemu-system/vinix-qemu" \
    "$STAGING/usr/bin/vinix-qemu"
install -m755 "$SCRIPT_DIR/build-support/qemu-system/vinix-qemu-desktop" \
    "$STAGING/usr/bin/vinix-qemu-desktop"

# The desktop's Xvfb host needs a fixed-size RFB client. Compile it against
# the same AArch64 X11 sysroot used by the desktop instead of pulling in a
# larger toolkit with its own window resizing and graphics stack.
X11_SYSROOT="${VINIX_X11_SYSROOT:-$SCRIPT_DIR/build-aarch64-x11/sysroot}"
GCCLIB="$(find "$SCRIPT_DIR/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl" \
    -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -n1 || true)"
CLANG="${VINIX_QEMU_CLANG:-/opt/homebrew/opt/llvm/bin/clang}"
if [ ! -x "$CLANG" ]; then
    CLANG="$(command -v clang || true)"
fi
if [ -z "$CLANG" ] || [ -z "$GCCLIB" ] || \
   [ ! -f "$X11_SYSROOT/usr/include/X11/Xlib.h" ] || \
   [ ! -f "$X11_SYSROOT/usr/lib/libX11.so" ]; then
    echo "AArch64 X11 sysroot or cross compiler is missing; build the X11 layer first." >&2
    exit 1
fi
"$CLANG" --target=aarch64-linux-musl --sysroot="$X11_SYSROOT" \
    --gcc-install-dir="$GCCLIB" -static-libgcc -O2 -Wall -Wextra -Werror \
    -I"$X11_SYSROOT/usr/include" \
    "$SCRIPT_DIR/build-support/qemu-system/vinix-vnc-window.c" \
    -fuse-ld=lld -L"$X11_SYSROOT/usr/lib" -L"$X11_SYSROOT/lib" \
    -Wl,-rpath-link,"$X11_SYSROOT/usr/lib" \
    -Wl,-rpath-link,"$X11_SYSROOT/lib" \
    -lX11 -lxcb -o "$STAGING/usr/bin/vinix-vnc-window"

echo "staged QEMU: $(du -sh "$STAGING" | cut -f1)"
