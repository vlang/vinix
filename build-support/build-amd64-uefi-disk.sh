#!/bin/bash
# Assemble a raw FAT32 UEFI disk for the amd64 QEMU runner. This is the
# portable fallback when xorriso is unavailable; release artifacts remain ISO.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${VINIX_AMD64_DISK_BUILD_DIR:-$SCRIPT_DIR/build-amd64-disk}"
KERNEL="${VINIX_AMD64_KERNEL:-$SCRIPT_DIR/build-amd64-kernel/bin/vinix}"
INITRAMFS="${VINIX_AMD64_INITRAMFS:-$SCRIPT_DIR/build-amd64-userland/initramfs.tar}"
OUTPUT_DISK="${VINIX_AMD64_DISK:-$SCRIPT_DIR/vinix-amd64.img}"
DISK_SIZE_MB="${VINIX_AMD64_DISK_SIZE_MB:-64}"
LIMINE_COMMIT=ee5d29cd0a8034612dcd1df3f00052480db785c5
BOOTX64_SHA256=c1d6c34cf827e0c5cb0f3546d2db8568dd29aae26833a6332db5532b823503c3

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe amd64 disk build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac
case "$DISK_SIZE_MB" in
    ''|*[!0-9]*|0)
        echo "ERROR: VINIX_AMD64_DISK_SIZE_MB must be a positive integer" >&2
        exit 1
        ;;
esac
for command_name in curl truncate mformat mmd mcopy; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $command_name" >&2
        exit 1
    }
done
for input in "$KERNEL" "$INITRAMFS" "$SCRIPT_DIR/build-support/limine.conf"; do
    if [ ! -f "$input" ]; then
        echo "ERROR: required UEFI disk input not found: $input" >&2
        exit 1
    fi
done

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

mkdir -p "$BUILD_DIR/limine"
BOOTX64="$BUILD_DIR/limine/BOOTX64.EFI"
if [ ! -s "$BOOTX64" ]; then
    echo "==> Fetching pinned Limine BOOTX64.EFI..."
    curl -fL --retry 3 \
        "https://raw.githubusercontent.com/limine-bootloader/limine/$LIMINE_COMMIT/BOOTX64.EFI" \
        -o "$BOOTX64"
fi
actual="$(sha256_file "$BOOTX64")"
if [ "$actual" != "$BOOTX64_SHA256" ]; then
    echo "ERROR: Limine BOOTX64.EFI checksum mismatch." >&2
    echo "Expected: $BOOTX64_SHA256" >&2
    echo "Actual:   $actual" >&2
    exit 1
fi

payload_bytes=$(($(wc -c < "$KERNEL") + $(wc -c < "$INITRAMFS") + $(wc -c < "$BOOTX64")))
disk_bytes=$((DISK_SIZE_MB * 1024 * 1024))
if [ "$disk_bytes" -lt $((payload_bytes + 8 * 1024 * 1024)) ]; then
    echo "ERROR: ${DISK_SIZE_MB} MiB disk is too small for the boot payload" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_DISK")"
OUTPUT_TMP="$(mktemp "$(dirname "$OUTPUT_DISK")/.vinix-amd64.img.XXXXXX")"
trap 'rm -f "$OUTPUT_TMP"' EXIT
truncate -s "${DISK_SIZE_MB}M" "$OUTPUT_TMP"
mformat -i "$OUTPUT_TMP" -F ::
mmd -i "$OUTPUT_TMP" ::/EFI ::/EFI/BOOT ::/boot
mcopy -o -i "$OUTPUT_TMP" "$BOOTX64" ::/EFI/BOOT/BOOTX64.EFI
mcopy -o -i "$OUTPUT_TMP" "$KERNEL" ::/boot/vinix
mcopy -o -i "$OUTPUT_TMP" "$INITRAMFS" ::/boot/initramfs.tar
mcopy -o -i "$OUTPUT_TMP" "$SCRIPT_DIR/build-support/limine.conf" ::/boot/limine.conf
mv -f "$OUTPUT_TMP" "$OUTPUT_DISK"
trap - EXIT
echo "    $OUTPUT_DISK ($(wc -c < "$OUTPUT_DISK" | tr -d ' ') bytes)"
