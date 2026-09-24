#!/bin/bash
# Assemble an amd64 ISO around an already-built kernel and initramfs. It boots
# through either BIOS or UEFI, from a CD or written to a disk: VirtualBox VMs
# start in BIOS mode unless EFI is switched on. Limine's pinned release
# binaries are downloaded directly; only its small host installer is compiled.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${VINIX_AMD64_ISO_BUILD_DIR:-$SCRIPT_DIR/build-amd64-iso}"
KERNEL="${VINIX_AMD64_KERNEL:-$SCRIPT_DIR/build-amd64-kernel/bin/vinix}"
INITRAMFS="${VINIX_AMD64_INITRAMFS:-$SCRIPT_DIR/build-amd64-userland/initramfs.tar}"
OUTPUT_ISO="${VINIX_AMD64_ISO:-$SCRIPT_DIR/vinix.iso}"
LIMINE_COMMIT=ee5d29cd0a8034612dcd1df3f00052480db785c5
BOOTX64_SHA256=c1d6c34cf827e0c5cb0f3546d2db8568dd29aae26833a6332db5532b823503c3
UEFI_CD_SHA256=7751a48fde8ec040f3ac079a9893dbbe0687af3e3c0a96619d69ae2eba9b1478
BIOS_CD_SHA256=f1b97df69d0a2723a8a849e915665b1a9a7c5988f2245400aac9891adb4725c1
BIOS_SYS_SHA256=39f4619ae75e31432aea0ddd14ad3206f7c5b2b637e879bec090fc8bb546f309
LIMINE_C_SHA256=e015228283ad9a373b88041a18f8714eba109f4f08b2f3a39d7bf3a8d12de32f
BIOS_HDD_H_SHA256=21303b2f510e50dffec4fd2fb3a3e4acf889db8cf48c2ae6882b0a2b173e2e10

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe amd64 ISO build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac

for command_name in cc curl xorriso; do
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

fetch_limine_file BOOTX64.EFI "$BOOTX64_SHA256"
fetch_limine_file limine-uefi-cd.bin "$UEFI_CD_SHA256"
fetch_limine_file limine-bios-cd.bin "$BIOS_CD_SHA256"
fetch_limine_file limine-bios.sys "$BIOS_SYS_SHA256"
fetch_limine_file limine.c "$LIMINE_C_SHA256"
fetch_limine_file limine-bios-hdd.h "$BIOS_HDD_H_SHA256"

# The host tool that writes the BIOS boot sector of a hybrid image.
LIMINE_TOOL="$BUILD_DIR/limine/limine"
if [ ! -x "$LIMINE_TOOL" ] || [ "$LIMINE_TOOL" -ot "$BUILD_DIR/limine/limine.c" ]; then
    echo "==> Building the Limine host installer..."
    cc -O2 -std=c99 -o "$LIMINE_TOOL" "$BUILD_DIR/limine/limine.c"
fi

ISO_ROOT="$BUILD_DIR/iso-root"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot" "$ISO_ROOT/EFI/BOOT"
install -m644 "$KERNEL" "$ISO_ROOT/boot/vinix"
install -m644 "$INITRAMFS" "$ISO_ROOT/boot/initramfs.tar"
install -m644 "$SCRIPT_DIR/build-support/limine.conf" "$ISO_ROOT/boot/limine.conf"
install -m644 "$BUILD_DIR/limine/limine-uefi-cd.bin" \
    "$ISO_ROOT/boot/limine-uefi-cd.bin"
install -m644 "$BUILD_DIR/limine/limine-bios-cd.bin" \
    "$ISO_ROOT/boot/limine-bios-cd.bin"
install -m644 "$BUILD_DIR/limine/limine-bios.sys" \
    "$ISO_ROOT/boot/limine-bios.sys"
install -m644 "$BUILD_DIR/limine/BOOTX64.EFI" "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI"

mkdir -p "$(dirname "$OUTPUT_ISO")"
OUTPUT_ISO_TMP="$(mktemp "$(dirname "$OUTPUT_ISO")/.vinix-amd64.iso.XXXXXX")"
trap 'rm -f "$OUTPUT_ISO_TMP"' EXIT
echo "==> Assembling $OUTPUT_ISO..."
# ISO level 3 lets the initramfs grow past 4 GiB.
xorriso -as mkisofs -iso-level 3 -R -r -J \
    -b boot/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --efi-boot boot/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$ISO_ROOT" -o "$OUTPUT_ISO_TMP"
"$LIMINE_TOOL" bios-install "$OUTPUT_ISO_TMP"
mv -f "$OUTPUT_ISO_TMP" "$OUTPUT_ISO"
trap - EXIT
echo "    $OUTPUT_ISO ($(wc -c < "$OUTPUT_ISO" | tr -d ' ') bytes)"
