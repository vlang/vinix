#!/bin/bash
# Deploy Vinix ARM64 boot files to an already-mounted EFI System Partition.
# Usage: ./deploy-m1-efi.sh [--apple-gpu] /path/to/mounted/esp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ESP_MOUNT=""
ENABLE_APPLE_GPU=0

for argument in "$@"; do
    case "$argument" in
        --apple-gpu)
            ENABLE_APPLE_GPU=1
            ;;
        --help|-h)
            echo "usage: $0 [--apple-gpu] <mounted_esp_path>"
            exit 0
            ;;
        --*)
            echo "error: unknown option: $argument" >&2
            exit 1
            ;;
        *)
            if [ -n "$ESP_MOUNT" ]; then
                echo "error: multiple ESP paths supplied" >&2
                exit 1
            fi
            ESP_MOUNT="$argument"
            ;;
    esac
done

if [ -z "$ESP_MOUNT" ]; then
    echo "usage: $0 [--apple-gpu] <mounted_esp_path>"
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

RUNTIME_CONF="$(mktemp "${TMPDIR:-/tmp}/vinix-limine.XXXXXX")"
trap 'rm -f "$RUNTIME_CONF"' EXIT
if [ "$ENABLE_APPLE_GPU" -eq 1 ]; then
    awk '
        /^[[:space:]]*cmdline:/ {
            found = 1
            if ($0 !~ /vinix\.apple_gpu=1/) $0 = $0 " vinix.apple_gpu=1"
        }
        { print }
        END {
            if (!found) print "    cmdline: vinix.apple_gpu=1"
        }
    ' "$LIMINE_CONF" > "$RUNTIME_CONF"
    echo "Apple GPU bring-up enabled (experimental M1/G13 path)"
else
    cp "$LIMINE_CONF" "$RUNTIME_CONF"
fi

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
cp "$RUNTIME_CONF" "$ESP_MOUNT/boot/limine.conf"
cp "$RUNTIME_CONF" "$ESP_MOUNT/limine.conf"
cp "$RUNTIME_CONF" "$ESP_MOUNT/EFI/BOOT/limine.conf"
cp "$RUNTIME_CONF" "$ESP_MOUNT/limine/limine.conf"
cp "$KERNEL" "$ESP_MOUNT/boot/vinix"
cp "$INITRAMFS" "$ESP_MOUNT/boot/initramfs.tar"

sync
echo "Deployed Vinix boot files to: $ESP_MOUNT"
