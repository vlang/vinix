#!/bin/bash
# Deploy Vinix ARM64 boot files to an already-mounted EFI System Partition.
# Usage: ./deploy-m1-efi.sh /path/to/mounted/esp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ESP_MOUNT="${1:-}"

if [ -z "$ESP_MOUNT" ]; then
    echo "usage: $0 <mounted_esp_path>"
    exit 1
fi

if [ ! -d "$ESP_MOUNT" ]; then
    echo "error: ESP mount path does not exist: $ESP_MOUNT"
    exit 1
fi

KERNEL="$SCRIPT_DIR/kernel/bin/vinix"
INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar"
LIMINE_EFI_BUILT="$SCRIPT_DIR/boot-image/limine-9.3.0/bin/BOOTAA64.EFI"
LIMINE_EFI_BIN="$SCRIPT_DIR/boot-image/limine-bin/BOOTAA64.EFI"
LIMINE_CONF="$SCRIPT_DIR/build-support/limine.conf"

if [ -f "$LIMINE_EFI_BUILT" ] && { [ ! -f "$LIMINE_EFI_BIN" ] || [ "$LIMINE_EFI_BUILT" -nt "$LIMINE_EFI_BIN" ]; }; then
    LIMINE_EFI="$LIMINE_EFI_BUILT"
else
    LIMINE_EFI="$LIMINE_EFI_BIN"
fi

for f in "$KERNEL" "$INITRAMFS" "$LIMINE_EFI" "$LIMINE_CONF"; do
    if [ ! -f "$f" ]; then
        echo "error: missing required file: $f"
        exit 1
    fi
done

echo "using limine EFI: $LIMINE_EFI"

KERNEL_FILE_INFO="$(file -b "$KERNEL" || true)"
if ! echo "$KERNEL_FILE_INFO" | grep -Eiq 'ELF 64-bit'; then
    echo "error: kernel is not an ELF64 image: $KERNEL_FILE_INFO"
    exit 1
fi
if ! echo "$KERNEL_FILE_INFO" | grep -Eiq '(ARM aarch64|ARM64|AArch64)'; then
    echo "error: kernel is not AArch64: $KERNEL_FILE_INFO"
    echo "hint: rebuild with: make -C kernel ARCH=aarch64 CC=clang"
    exit 1
fi

mkdir -p "$ESP_MOUNT/EFI/BOOT"
mkdir -p "$ESP_MOUNT/boot"
mkdir -p "$ESP_MOUNT/limine"

if [ -f "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI" ]; then
    cp "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI" "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI.bak"
fi

cp "$LIMINE_EFI" "$ESP_MOUNT/EFI/BOOT/BOOTAA64.EFI"
cp "$LIMINE_CONF" "$ESP_MOUNT/boot/limine.conf"
cp "$LIMINE_CONF" "$ESP_MOUNT/limine.conf"
cp "$LIMINE_CONF" "$ESP_MOUNT/EFI/BOOT/limine.conf"
cp "$LIMINE_CONF" "$ESP_MOUNT/limine/limine.conf"
cp "$KERNEL" "$ESP_MOUNT/boot/vinix"
cp "$INITRAMFS" "$ESP_MOUNT/boot/initramfs.tar"

sync
echo "Deployed Vinix boot files to: $ESP_MOUNT"
