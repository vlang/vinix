#!/bin/bash
# Assemble an aarch64 UEFI ISO around an already-built kernel and initramfs.
# The pinned Limine binaries are downloaded directly; no target toolchain or
# Limine source build is part of the normal image path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${VINIX_AARCH64_ISO_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-iso}"
KERNEL="${VINIX_AARCH64_KERNEL:-$SCRIPT_DIR/build-aarch64-kernel/bin/vinix}"
INITRAMFS="${VINIX_AARCH64_INITRAMFS:-$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar}"
OUTPUT_ISO="${VINIX_AARCH64_ISO:-$SCRIPT_DIR/vinix-aarch64.iso}"
LIMINE_COMMIT=ee5d29cd0a8034612dcd1df3f00052480db785c5
BOOTAA64_SHA256=bc79bb7237ac7d57081f06bb714c5bedd0b1635645ec6c58d597e1a493999b81
UEFI_CD_SHA256=7751a48fde8ec040f3ac079a9893dbbe0687af3e3c0a96619d69ae2eba9b1478

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe aarch64 ISO build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac
for command_name in curl xorriso; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $command_name" >&2
        exit 1
    }
done
for input in "$KERNEL" "$INITRAMFS" "$SCRIPT_DIR/build-support/limine.conf"; do
    if [ ! -f "$input" ]; then
        echo "ERROR: required ISO input not found: $input" >&2
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

fetch_limine_file() {
    local filename="$1" expected="$2" destination="$BUILD_DIR/limine/$1"
    mkdir -p "$BUILD_DIR/limine"
    if [ ! -s "$destination" ]; then
        echo "==> Fetching pinned Limine $filename..."
        curl -fL --retry 3 \
            "https://raw.githubusercontent.com/limine-bootloader/limine/$LIMINE_COMMIT/$filename" \
            -o "$destination"
    fi
    actual="$(sha256_file "$destination")"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: Limine $filename checksum mismatch." >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
    fi
}

fetch_limine_file BOOTAA64.EFI "$BOOTAA64_SHA256"
fetch_limine_file limine-uefi-cd.bin "$UEFI_CD_SHA256"

ISO_ROOT="$BUILD_DIR/iso-root"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot" "$ISO_ROOT/EFI/BOOT"
install -m644 "$KERNEL" "$ISO_ROOT/boot/vinix"
install -m644 "$INITRAMFS" "$ISO_ROOT/boot/initramfs.tar"
install -m644 "$SCRIPT_DIR/build-support/limine.conf" "$ISO_ROOT/boot/limine.conf"
install -m644 "$BUILD_DIR/limine/limine-uefi-cd.bin" \
    "$ISO_ROOT/boot/limine-uefi-cd.bin"
install -m644 "$BUILD_DIR/limine/BOOTAA64.EFI" "$ISO_ROOT/EFI/BOOT/BOOTAA64.EFI"

mkdir -p "$(dirname "$OUTPUT_ISO")"
OUTPUT_ISO_TMP="$(mktemp "$(dirname "$OUTPUT_ISO")/.vinix-aarch64.iso.XXXXXX")"
trap 'rm -f "$OUTPUT_ISO_TMP"' EXIT
echo "==> Assembling $OUTPUT_ISO..."
xorriso -as mkisofs -R -r -J \
    --efi-boot boot/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$ISO_ROOT" -o "$OUTPUT_ISO_TMP"
mv -f "$OUTPUT_ISO_TMP" "$OUTPUT_ISO"
trap - EXIT
echo "    $OUTPUT_ISO ($(wc -c < "$OUTPUT_ISO" | tr -d ' ') bytes)"
