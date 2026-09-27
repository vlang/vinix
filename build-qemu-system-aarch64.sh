#!/bin/bash
# Stage a native AArch64 QEMU system emulator and UEFI firmware for Vinix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    qemu-system-aarch64 > "$BUILD_DIR/packages"

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

echo "staged QEMU: $(du -sh "$STAGING" | cut -f1)"
