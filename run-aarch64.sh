#!/bin/bash
# Fast build + run cycle for Vinix aarch64 in QEMU
# Usage: ./run-aarch64.sh [--no-build] [--serial] [--virtio-gpu] [--mem=MB]
#
# --mem=MB (or VINIX_QEMU_MEM) sizes guest RAM. The virt machine places RAM
# from 1 GiB upwards, so anything past --mem=3072 lands above 4 GiB, which is
# where all of an Apple Silicon machine's RAM lives. 8192 exercises the same
# high-memory mapping path the M1 takes; the 2048 default keeps boots fast.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/link-worktree-build-dirs.sh" ]; then
    "$SCRIPT_DIR/link-worktree-build-dirs.sh"
fi
KERNEL_DIR="$SCRIPT_DIR/kernel"
BOOT_DIR="$SCRIPT_DIR/boot-image"
BOOT_DISK="$BOOT_DIR/boot.img"
OVMF_VARS="/tmp/vinix-efivars.fd"
INIT_DIR="$SCRIPT_DIR/build-support/init-aarch64"
LIMINE_VERSION="9.3.0"
LIMINE_CONF_SRC="$SCRIPT_DIR/build-support/limine.conf"
LIMINE_CONF_QEMU="/tmp/vinix-limine-qemu.conf"

NO_BUILD=0
SERIAL_ONLY=0
VIRTIO_GPU=0
QEMU_MEM="${VINIX_QEMU_MEM:-2048}"
for arg in "$@"; do
    case "$arg" in
        --no-build)   NO_BUILD=1 ;;
        --serial)     SERIAL_ONLY=1 ;;
        --virtio-gpu) VIRTIO_GPU=1 ;;
        --mem=*)      QEMU_MEM="${arg#*=}" ;;
    esac
done

# ── Build init program (fallback if no busybox userland) ──
INITRAMFS="$INIT_DIR/initramfs.tar"
if [ "$NO_BUILD" -eq 0 ] && [ ! -f "$INITRAMFS" ]; then
    echo "==> Building minimal init program..."
    echo "    (Run ./build-userland-aarch64.sh for full busybox userland)"
    mkdir -p "$INIT_DIR"
    clang -target aarch64-linux-none -nostdlib -ffreestanding -O2 -c \
        -o /tmp/vinix-init.o "$INIT_DIR/init.c"
    ld.lld -m aarch64elf --nostdlib -static \
        -o "$INIT_DIR/init" /tmp/vinix-init.o
fi

# ── Build kernel ──
if [ "$NO_BUILD" -eq 0 ]; then
    echo "==> Building kernel..."
    make -C "$KERNEL_DIR" CC=clang ARCH=aarch64 -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
fi

if [ ! -f "$KERNEL_DIR/bin/vinix" ]; then
    echo "ERROR: kernel/bin/vinix not found. Build failed?"
    exit 1
fi

mkdir -p "$BOOT_DIR"

if [ ! -f "$LIMINE_CONF_SRC" ]; then
    echo "ERROR: limine config not found: $LIMINE_CONF_SRC"
    exit 1
fi

# QEMU boots on this branch need explicit qemu MMIO enable for keyboard/GIC.
# Keep the repo limine.conf hardware-safe; generate a QEMU-only copy here.
cp "$LIMINE_CONF_SRC" "$LIMINE_CONF_QEMU"
if grep -Eq '^[[:space:]]*cmdline:' "$LIMINE_CONF_QEMU"; then
    if ! grep -Eq '^[[:space:]]*cmdline:.*vinix\.qemu_platform=1' "$LIMINE_CONF_QEMU"; then
        sed -E -i '' '/^[[:space:]]*cmdline:/ s#$# vinix.qemu_platform=1#' "$LIMINE_CONF_QEMU"
    fi
else
    sed -i '' '/^[[:space:]]*kaslr:/a\
    cmdline: vinix.qemu_platform=1
' "$LIMINE_CONF_QEMU"
fi

# ── Ensure the patched Limine BOOTAA64.EFI is available ──
# build-limine-aarch64.sh applies the Apple Silicon hand-off patch; the same
# loader is what deploy-m1-efi.sh ships, so QEMU exercises the deployed build.
LIMINE_EFI="$BOOT_DIR/limine-bin/BOOTAA64.EFI"
if [ ! -f "$LIMINE_EFI" ] || ! "$SCRIPT_DIR/build-limine-aarch64.sh" --check | grep -q "patched for Apple Silicon"; then
    echo "==> Building patched Limine ${LIMINE_VERSION}..."
    "$SCRIPT_DIR/build-limine-aarch64.sh" || exit 1
fi

# ── Find UEFI firmware from QEMU installation ──
OVMF=$(find /opt/homebrew -name "edk2-aarch64-code.fd" 2>/dev/null | head -1)
if [ -z "$OVMF" ]; then
    echo "ERROR: edk2-aarch64-code.fd not found."
    echo "Install: brew install qemu"
    exit 1
fi

# ── Create fresh EFI vars for each run ──
# QEMU modifies efivars during boot, so we always start from a clean template.
# Using the proper NVRAM template is critical: a zeroed-out file breaks GOP
# initialization (no framebuffer).
OVMF_VARS_TEMPLATE=$(find /opt/homebrew -name "edk2-arm-vars.fd" 2>/dev/null | head -1)
if [ -n "$OVMF_VARS_TEMPLATE" ]; then
    cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
else
    echo "WARNING: edk2-arm-vars.fd template not found, GOP/framebuffer may not work"
    dd if=/dev/zero of="$OVMF_VARS" bs=1m count=64 2>/dev/null
fi

# ── Create/update boot disk (fast: only mcopy the kernel) ──
if [ ! -f "$BOOT_DISK" ]; then
    echo "==> Creating boot disk image (one-time)..."
    dd if=/dev/zero of="$BOOT_DISK" bs=1m count=512 2>/dev/null
    mformat -F -i "$BOOT_DISK" ::
    mmd -i "$BOOT_DISK" ::/EFI
    mmd -i "$BOOT_DISK" ::/EFI/BOOT
    mmd -i "$BOOT_DISK" ::/boot

    if [ ! -f "$LIMINE_EFI" ]; then
        echo "ERROR: BOOTAA64.EFI not found at $LIMINE_EFI"
        exit 1
    fi
    mcopy -i "$BOOT_DISK" "$LIMINE_EFI" ::/EFI/BOOT/BOOTAA64.EFI

    mcopy -i "$BOOT_DISK" "$LIMINE_CONF_QEMU" ::/boot/limine.conf

    tar cf /tmp/vinix-initramfs.tar --files-from /dev/null
    mcopy -i "$BOOT_DISK" /tmp/vinix-initramfs.tar ::/boot/initramfs.tar
fi

# The loader is refreshed on every run, not only when the disk is created, so
# a rebuilt Limine is what actually boots.
mcopy -o -i "$BOOT_DISK" "$LIMINE_EFI" ::/EFI/BOOT/BOOTAA64.EFI

# ── Build initramfs with /sbin/init ──
if [ -f "$INITRAMFS" ]; then
    # Use pre-built initramfs from build-userland-aarch64.sh (busybox)
    echo "==> Using busybox initramfs..."
    mcopy -o -i "$BOOT_DISK" "$INITRAMFS" ::/boot/initramfs.tar
elif [ -f "$INIT_DIR/init" ]; then
    # Fallback: minimal init only
    echo "==> Creating minimal initramfs with /sbin/init..."
    INITRAMFS_STAGING="/tmp/vinix-initramfs-staging"
    rm -rf "$INITRAMFS_STAGING"
    mkdir -p "$INITRAMFS_STAGING/sbin"
    cp "$INIT_DIR/init" "$INITRAMFS_STAGING/sbin/init"
    chmod +x "$INITRAMFS_STAGING/sbin/init"
    COPYFILE_DISABLE=1 tar --format=ustar -cf /tmp/vinix-initramfs.tar -C "$INITRAMFS_STAGING" .
    mcopy -o -i "$BOOT_DISK" /tmp/vinix-initramfs.tar ::/boot/initramfs.tar
    rm -rf "$INITRAMFS_STAGING"
fi

# ── Update kernel (the only step on rebuilds) ──
echo "==> Copying Limine config to boot disk..."
mcopy -o -i "$BOOT_DISK" "$LIMINE_CONF_QEMU" ::/boot/limine.conf

echo "==> Copying kernel to boot disk..."
mcopy -o -i "$BOOT_DISK" "$KERNEL_DIR/bin/vinix" ::/boot/vinix

# ── Launch QEMU ──
echo "==> Starting QEMU (Ctrl-A X to quit)..."

if [ "$SERIAL_ONLY" -eq 1 ]; then
    # Use -display none (not -nographic) to keep ramfb for framebuffer/GOP
    # while hiding the QEMU window. -nographic removes display devices entirely.
    DISPLAY_BACKEND_FLAGS="-display none"
elif [ -n "${QEMU_DISPLAY_BACKEND:-}" ]; then
    DISPLAY_BACKEND_FLAGS="-display ${QEMU_DISPLAY_BACKEND}"
elif [ "$(uname -s)" = "Darwin" ]; then
    DISPLAY_BACKEND_FLAGS="-display cocoa"
else
    DISPLAY_BACKEND_FLAGS="-display default"
fi

if [ "$VIRTIO_GPU" -eq 1 ]; then
    # Keep ramfb as primary scanout so firmware/GOP always exposes a visible
    # framebuffer, then add virtio-gpu for future guest-side acceleration.
    DISPLAY_DEVICE_FLAGS="-device ramfb -device virtio-gpu-pci,max_outputs=1"
else
    DISPLAY_DEVICE_FLAGS="-device ramfb"
fi

# Multiplex the serial console and QEMU monitor so Ctrl-A X exits as advertised.
DISPLAY_FLAGS="$DISPLAY_DEVICE_FLAGS $DISPLAY_BACKEND_FLAGS -serial mon:stdio"

ACCEL_FLAGS="-accel hvf -cpu host"
if [ "${USE_TCG:-0}" -eq 1 ]; then
    ACCEL_FLAGS="-accel tcg -cpu cortex-a72"
fi

exec qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    $ACCEL_FLAGS \
    -m "$QEMU_MEM" \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive format=raw,file="$BOOT_DISK" \
    -device virtio-keyboard-device \
    $DISPLAY_FLAGS \
    -no-reboot
