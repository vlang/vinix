#!/bin/bash
# Fast build + run cycle for Vinix aarch64 in QEMU
# Usage: ./run-aarch64.sh [--no-build] [--serial] [--virtio-gpu] [--mem=MB]
#                         [--disk=MB] [--replace] [--grab-keys]
#
# --grab-keys hands the whole keyboard to the guest. macOS keeps Cmd-Tab for
# its own application switcher, so without it the desktop's Cmd-Tab is never
# seen -- at the price of Cmd-Q no longer quitting QEMU.
#
# --replace stops a VM already using the boot disk. Without it a second run
# refuses, rather than writing into the disk of a running one.
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
# Both paths can be overridden so two QEMU runs on this machine (say, a CI
# check and a developer's boot) never share a disk image or NVRAM file: QEMU
# takes a write lock on the image, and a second run either fails to start or
# boots whatever the first one last copied in.
BOOT_DISK="${VINIX_BOOT_DISK:-$BOOT_DIR/boot.img}"
BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-2048}"
OVMF_VARS="${VINIX_EFIVARS:-/tmp/vinix-efivars.fd}"
INIT_DIR="$SCRIPT_DIR/build-support/init-aarch64"
LIMINE_VERSION="9.3.0"
LIMINE_CONF_SRC="$SCRIPT_DIR/build-support/limine.conf"
LIMINE_CONF_QEMU="/tmp/vinix-limine-qemu.conf"
QEMU_RESOLUTION="${VINIX_QEMU_RESOLUTION:-}"

NO_BUILD=0
SERIAL_ONLY=0
VIRTIO_GPU=0
REPLACE_RUNNING=0
GRAB_KEYS=0
QEMU_MEM="${VINIX_QEMU_MEM:-2048}"
for arg in "$@"; do
    case "$arg" in
        --no-build)   NO_BUILD=1 ;;
        --serial)     SERIAL_ONLY=1 ;;
        --virtio-gpu) VIRTIO_GPU=1 ;;
        --mem=*)      QEMU_MEM="${arg#*=}" ;;
        --disk=*)     BOOT_DISK_SIZE_MB="${arg#*=}" ;;
        --replace)    REPLACE_RUNNING=1 ;;
        --grab-keys)  GRAB_KEYS=1 ;;
    esac
done

case "$BOOT_DISK_SIZE_MB" in
    ''|*[!0-9]*)
        echo "ERROR: --disk must be a size in MiB" >&2
        exit 1
        ;;
esac

# ── Build init program (fallback if no busybox userland) ──
# VINIX_INITRAMFS selects a different image, e.g. the one
# ./build-desktop-aarch64.sh stages to boot straight into the desktop.
INITRAMFS="${VINIX_INITRAMFS:-$INIT_DIR/initramfs.tar}"
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

# A caller may request a QEMU-only GOP mode without changing the hardware-safe
# repository configuration. The desktop runner uses this for its 2x display.
if [ -n "$QEMU_RESOLUTION" ]; then
    if grep -Eq '^[[:space:]]*resolution:' "$LIMINE_CONF_QEMU"; then
        sed -E -i '' "s#^[[:space:]]*resolution:.*#    resolution: $QEMU_RESOLUTION#" "$LIMINE_CONF_QEMU"
    else
        sed -i '' '/^[[:space:]]*kaslr:/a\
    resolution: '"$QEMU_RESOLUTION"'
' "$LIMINE_CONF_QEMU"
    fi
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

# ── Refuse to touch a boot disk another VM is using ──
# QEMU takes a write lock on it and fails to start if it cannot; mtools takes
# no lock at all. So without this check the mcopy steps below would write a new
# kernel into the disk of a *running* VM, and only then would QEMU report the
# lock it could not get. Catching it here says which process to deal with, and
# says it before anything has been modified.
if [ -f "$BOOT_DISK" ] && command -v lsof >/dev/null 2>&1; then
    HOLDERS="$(lsof -t -- "$BOOT_DISK" 2>/dev/null | tr '\n' ' ')"
    if [ -n "${HOLDERS// /}" ]; then
        # Only a QEMU is safe to stop on the strength of holding this file.
        NON_QEMU=""
        for pid in $HOLDERS; do
            case "$(ps -o comm= -p "$pid" 2>/dev/null)" in
                *qemu*) ;;
                *)      NON_QEMU="$NON_QEMU $pid" ;;
            esac
        done

        if [ -n "${NON_QEMU// /}" ] || [ "$REPLACE_RUNNING" -eq 0 ]; then
            echo "ERROR: $BOOT_DISK is in use, so this VM cannot start." >&2
            for pid in $HOLDERS; do
                echo "    pid $pid: $(ps -o command= -p "$pid" 2>/dev/null | cut -c1-70)" >&2
            done
            if [ -n "${NON_QEMU// /}" ]; then
                echo "Something other than QEMU has it open; sort that out first." >&2
            else
                echo "Re-run with --replace to stop it, or: kill $HOLDERS" >&2
            fi
            exit 1
        fi

        echo "==> Stopping the VM already using the boot disk (pid $HOLDERS)..."
        kill $HOLDERS 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            [ -z "$(lsof -t -- "$BOOT_DISK" 2>/dev/null)" ] && break
            sleep 0.5
        done
        if [ -n "$(lsof -t -- "$BOOT_DISK" 2>/dev/null)" ]; then
            echo "ERROR: it did not let go of $BOOT_DISK; kill -9 $HOLDERS" >&2
            exit 1
        fi
    fi
fi

# A browser image is much larger than the old 512 MiB development disk. Do not
# let mcopy fail later with a cryptic FAT error or overwrite an existing image;
# tell the caller how to create a larger generated disk alongside it.
if [ -f "$INITRAMFS" ]; then
    if stat -f%z "$INITRAMFS" >/dev/null 2>&1; then
        initramfs_bytes="$(stat -f%z "$INITRAMFS")"
    else
        initramfs_bytes="$(stat -c%s "$INITRAMFS")"
    fi
    required_bytes=$((initramfs_bytes + 128 * 1024 * 1024))
    required_mb=$(((required_bytes + 1024 * 1024 - 1) / (1024 * 1024)))

    if [ -f "$BOOT_DISK" ]; then
        if stat -f%z "$BOOT_DISK" >/dev/null 2>&1; then
            boot_disk_bytes="$(stat -f%z "$BOOT_DISK")"
        else
            boot_disk_bytes="$(stat -c%s "$BOOT_DISK")"
        fi
    else
        boot_disk_bytes=$((BOOT_DISK_SIZE_MB * 1024 * 1024))
    fi

    if [ "$boot_disk_bytes" -lt "$required_bytes" ]; then
        echo "ERROR: $BOOT_DISK is too small for this initramfs." >&2
        echo "       Need at least ${required_mb} MiB." >&2
        if [ -f "$BOOT_DISK" ]; then
            echo "       Keep the existing disk and choose a new path, for example:" >&2
            echo "       VINIX_BOOT_DISK=/tmp/vinix-large.img $0 --disk=$BOOT_DISK_SIZE_MB" >&2
        else
            echo "       Re-run with --disk=$required_mb or larger." >&2
        fi
        exit 1
    fi
fi

# ── Create/update boot disk (fast: only mcopy the kernel) ──
if [ ! -f "$BOOT_DISK" ]; then
    echo "==> Creating ${BOOT_DISK_SIZE_MB} MiB boot disk image (one-time)..."
    disk_bytes=$((BOOT_DISK_SIZE_MB * 1024 * 1024))
    if command -v truncate >/dev/null 2>&1; then
        truncate -s "$disk_bytes" "$BOOT_DISK"
    elif command -v mkfile >/dev/null 2>&1; then
        mkfile -n "$disk_bytes" "$BOOT_DISK"
    else
        dd if=/dev/zero of="$BOOT_DISK" bs=1m count="$BOOT_DISK_SIZE_MB" 2>/dev/null
    fi
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
    # Whatever VINIX_INITRAMFS names, or the busybox one from
    # build-userland-aarch64.sh. Naming it matters: booting the desktop image
    # and booting the shell one look identical up to this line.
    echo "==> Using initramfs: $(basename "$INITRAMFS")"
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
    # System chords -- Cmd-Tab above all -- are the host's until QEMU is told
    # to capture every key, which is what the desktop's own Cmd-Tab needs.
    COCOA_OPTIONS="${VINIX_QEMU_COCOA_OPTIONS:-}"
    if [ "$GRAB_KEYS" -eq 1 ]; then
        COCOA_OPTIONS="${COCOA_OPTIONS:+${COCOA_OPTIONS},}full-grab=on"
    fi
    if [ -n "$COCOA_OPTIONS" ]; then
        DISPLAY_BACKEND_FLAGS="-display cocoa,$COCOA_OPTIONS"
    else
        DISPLAY_BACKEND_FLAGS="-display cocoa"
    fi
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

# VINIX_QEMU_EXTRA appends raw flags, e.g. a monitor socket to drive
# screendump from a script.
exec qemu-system-aarch64 \
    ${VINIX_QEMU_EXTRA} \
    -machine virt,gic-version=3 \
    $ACCEL_FLAGS \
    -m "$QEMU_MEM" \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive format=raw,file="$BOOT_DISK" \
    -device virtio-keyboard-device \
    -device virtio-tablet-device \
    -netdev user,id=net0 \
    -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56 \
    $DISPLAY_FLAGS \
    -no-reboot
