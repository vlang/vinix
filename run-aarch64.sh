#!/bin/bash
# Fast build + run cycle for Vinix aarch64 in QEMU
# Usage: ./run-aarch64.sh [--no-build] [--serial] [--virtio-gpu|--virgl]
#                         [--fake-g17]
#                         [--guest-init=PATH]
#                         [--mem=MB]
#                         [--disk=MB] [--persist[=MB]|--no-persist]
#                         [--ephemeral] [--replace] [--grab-keys]
#
# --grab-keys hands the whole keyboard to the guest. macOS keeps Cmd-Tab for
# its own application switcher, so without it the desktop's Cmd-Tab is never
# seen -- at the price of Cmd-Q no longer quitting QEMU.
#
# --replace stops a VM already using the boot disk. Without it a second run
# refuses, rather than writing into the disk of a running one.
#
# --persist attaches a separate ext2 volume and mounts it at /root. The base
# system still comes from the initramfs, while files below /root survive QEMU
# restarts. --persist=MB chooses its one-time image size.
#
# --ephemeral gives this run an isolated temporary boot image and deletes it
# when QEMU exits. Newly created boot images below the host's temporary
# directory receive the same cleanup unless VINIX_KEEP_TEMP_BOOT_DISK=1.
#
# --guest-init=PATH overlays /sbin/init for this boot only. It is intended for
# automated VM tests: neither the selected initramfs nor a persistent volume is
# modified.
#
# --mem=MB (or VINIX_QEMU_MEM) sizes guest RAM. The virt machine places RAM
# from 1 GiB upwards, so anything past --mem=3072 lands above 4 GiB, which is
# where all of an Apple Silicon machine's RAM lives. 8192 exercises the same
# high-memory mapping path the M1 takes; the 2048 default keeps boots fast.
# QEMU supplies four CPUs, and its kernel build enables the Limine MP request
# needed for Vinix to bring all of them online.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/build-support/qemu-storage.sh"
if [ -x "$SCRIPT_DIR/link-worktree-build-dirs.sh" ]; then
    "$SCRIPT_DIR/link-worktree-build-dirs.sh"
fi
KERNEL_DIR="$SCRIPT_DIR/kernel"
BOOT_DIR="$SCRIPT_DIR/boot-image"
# The normal path is deliberately stable and is reused across launches.
# Isolated tests should use --ephemeral; an explicit path remains available
# for callers that manage their own image lifecycle.
BOOT_DISK="${VINIX_BOOT_DISK:-$BOOT_DIR/boot.img}"
BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-2048}"
OVMF_VARS="${VINIX_EFIVARS:-/tmp/vinix-efivars.fd}"
INIT_DIR="$SCRIPT_DIR/build-support/init-aarch64"
LIMINE_VERSION="12.8.0"
LIMINE_CONF_SRC="$SCRIPT_DIR/build-support/limine.conf"
# Keep command-line mutations private to this VM; concurrent runs may select
# different backends and must not overwrite each other's generated config.
LIMINE_CONF_QEMU="$(mktemp -t vinix-limine-qemu)"
QEMU_RESOLUTION="${VINIX_QEMU_RESOLUTION:-}"
# Package state and persistent /root have stable defaults independent of an
# ephemeral boot image. Desktop runs select their own fixed profile paths.
PACKAGE_STORE="${VINIX_QEMU_PACKAGE_STORE:-$BOOT_DIR/boot.img.packages.tar}"
PACKAGE_STORE_PORT="${VINIX_QEMU_PACKAGE_STORE_PORT:-18081}"
PERSIST_DISK="${VINIX_QEMU_PERSIST_DISK:-$BOOT_DIR/boot.img.root.ext2}"
PERSIST_SIZE_MB="${VINIX_QEMU_PERSIST_SIZE_MB:-1024}"
PERSIST_SEED="${VINIX_QEMU_PERSIST_SEED:-}"
PACKAGE_RUNTIME_DIR=""
PACKAGE_SERVER_PID=""
EPHEMERAL_RUNTIME_DIR=""
CLEANUP_BOOT_DISK=0
KEEP_TEMP_BOOT_DISK="${VINIX_KEEP_TEMP_BOOT_DISK:-0}"

cleanup_runtime() {
    if [ -n "$PACKAGE_SERVER_PID" ]; then
        kill "$PACKAGE_SERVER_PID" 2>/dev/null || true
        wait "$PACKAGE_SERVER_PID" 2>/dev/null || true
        PACKAGE_SERVER_PID=""
    fi
    if [ -n "$PACKAGE_RUNTIME_DIR" ]; then
        rm -rf "$PACKAGE_RUNTIME_DIR"
        PACKAGE_RUNTIME_DIR=""
    fi
    if [ -n "$EPHEMERAL_RUNTIME_DIR" ]; then
        if vinix_storage_is_temporary_path "$EPHEMERAL_RUNTIME_DIR"; then
            case "$(basename "$EPHEMERAL_RUNTIME_DIR")" in
                vinix-qemu.*)
                    rm -rf "$EPHEMERAL_RUNTIME_DIR"
                    ;;
            esac
        fi
        EPHEMERAL_RUNTIME_DIR=""
    elif [ "$CLEANUP_BOOT_DISK" -eq 1 ]; then
        rm -f "$BOOT_DISK"
    fi
    rm -f "$LIMINE_CONF_QEMU"
}
trap cleanup_runtime EXIT INT TERM

NO_BUILD=0
SERIAL_ONLY=0
VIRTIO_GPU=0
FAKE_G17=0
GUEST_INIT="${VINIX_QEMU_GUEST_INIT:-}"
GUEST_INIT_REQUESTED=0
REPLACE_RUNNING=0
GRAB_KEYS=0
EPHEMERAL_BOOT=0
PERSIST_ENABLED="${VINIX_QEMU_PERSIST:-0}"
QEMU_MEM="${VINIX_QEMU_MEM:-2048}"
for arg in "$@"; do
    case "$arg" in
        --no-build)   NO_BUILD=1 ;;
        --serial)     SERIAL_ONLY=1 ;;
        --virtio-gpu) VIRTIO_GPU=1 ;;
        --virgl)      VIRTIO_GPU=2 ;;
        --fake-g17)   FAKE_G17=1 ;;
        --guest-init=*) GUEST_INIT="${arg#*=}"; GUEST_INIT_REQUESTED=1 ;;
        --mem=*)      QEMU_MEM="${arg#*=}" ;;
        --disk=*)     BOOT_DISK_SIZE_MB="${arg#*=}" ;;
        --persist)    PERSIST_ENABLED=1 ;;
        --persist=*)  PERSIST_ENABLED=1; PERSIST_SIZE_MB="${arg#*=}" ;;
        --no-persist) PERSIST_ENABLED=0 ;;
        --ephemeral)  EPHEMERAL_BOOT=1 ;;
        --replace)    REPLACE_RUNNING=1 ;;
        --grab-keys)  GRAB_KEYS=1 ;;
        --help|-h)
            awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
            exit 0
            ;;
    esac
done

if [ "$EPHEMERAL_BOOT" -eq 1 ]; then
    if [ -n "${VINIX_BOOT_DISK:-}" ]; then
        echo "ERROR: --ephemeral cannot be combined with VINIX_BOOT_DISK" >&2
        exit 1
    fi
    EPHEMERAL_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vinix-qemu.XXXXXX")"
    BOOT_DISK="$EPHEMERAL_RUNTIME_DIR/boot.img"
    if [ -z "${VINIX_EFIVARS:-}" ]; then
        OVMF_VARS="$EPHEMERAL_RUNTIME_DIR/efivars.fd"
    fi
    if [ -z "${VINIX_QEMU_PACKAGE_STORE:-}" ]; then
        PACKAGE_STORE="$EPHEMERAL_RUNTIME_DIR/packages.tar"
    fi
    if [ "$PERSIST_ENABLED" -eq 1 ] && [ -z "${VINIX_QEMU_PERSIST_DISK:-}" ]; then
        PERSIST_DISK="$EPHEMERAL_RUNTIME_DIR/root.ext2"
    fi
    if [ -z "${VINIX_QEMU_PACKAGE_STORE_PORT:-}" ]; then
        if ! command -v python3 >/dev/null 2>&1; then
            echo "ERROR: --ephemeral needs python3 to allocate an isolated package-store port" >&2
            exit 1
        fi
        PACKAGE_STORE_PORT="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
    fi
fi

if [ ! -e "$BOOT_DISK" ] && [ "$KEEP_TEMP_BOOT_DISK" -eq 0 ] &&
   vinix_storage_is_temporary_path "$BOOT_DISK"; then
    CLEANUP_BOOT_DISK=1
fi

if [ "$GUEST_INIT_REQUESTED" -eq 1 ] && [ -z "$GUEST_INIT" ]; then
    echo "ERROR: --guest-init needs a path" >&2
    exit 1
fi
if [ -n "$GUEST_INIT" ]; then
    case "$GUEST_INIT" in
        /*) ;;
        *) GUEST_INIT="$PWD/$GUEST_INIT" ;;
    esac
    if [ ! -f "$GUEST_INIT" ] || [ ! -x "$GUEST_INIT" ]; then
        echo "ERROR: --guest-init must name an executable regular file: $GUEST_INIT" >&2
        exit 1
    fi
fi

case "$BOOT_DISK_SIZE_MB" in
    ''|*[!0-9]*|0)
        echo "ERROR: --disk must be a size in MiB" >&2
        exit 1
        ;;
esac
case "$KEEP_TEMP_BOOT_DISK" in
    0|1) ;;
    *)
        echo "ERROR: VINIX_KEEP_TEMP_BOOT_DISK must be 0 or 1" >&2
        exit 1
        ;;
esac
case "$PERSIST_ENABLED" in
    0|1) ;;
    *)
        echo "ERROR: VINIX_QEMU_PERSIST must be 0 or 1" >&2
        exit 1
        ;;
esac
case "$PERSIST_SIZE_MB" in
    ''|*[!0-9]*|0)
        echo "ERROR: --persist must be a non-zero size in MiB" >&2
        exit 1
        ;;
esac
case "$PACKAGE_STORE_PORT" in
    ''|*[!0-9]*|0)
        echo "ERROR: VINIX_QEMU_PACKAGE_STORE_PORT must be between 1 and 65535" >&2
        exit 1
        ;;
esac
if [ "$PACKAGE_STORE_PORT" -gt 65535 ]; then
    echo "ERROR: VINIX_QEMU_PACKAGE_STORE_PORT must be between 1 and 65535" >&2
    exit 1
fi

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
    make -C "$KERNEL_DIR" CC=clang ARCH=aarch64 LIMINE_MP=1 \
        -j$(sysctl -n hw.ncpu) 2>&1 | tail -3
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

if [ "$PERSIST_ENABLED" -eq 1 ]; then
    if grep -Eq '^[[:space:]]*cmdline:' "$LIMINE_CONF_QEMU"; then
        if ! grep -Eq '^[[:space:]]*cmdline:.*vinix\.qemu_persist=1' "$LIMINE_CONF_QEMU"; then
            sed -E -i '' '/^[[:space:]]*cmdline:/ s#$# vinix.qemu_persist=1#' "$LIMINE_CONF_QEMU"
        fi
    else
        sed -i '' '/^[[:space:]]*kaslr:/a\
    cmdline: vinix.qemu_persist=1
' "$LIMINE_CONF_QEMU"
    fi
fi

if [ "$FAKE_G17" -eq 1 ]; then
    sed -E -i '' '/^[[:space:]]*cmdline:/ s#$# vinix.fake_g17=1#' "$LIMINE_CONF_QEMU"
fi

# ── Create the opt-in persistent ext2 home volume ──
# It is deliberately a different image from the UEFI/FAT boot disk: the
# kernel's persistent block driver only considers an ext2 volume, so firmware
# updates and rebuilds cannot accidentally become user-data writes.
PERSIST_DEVICE_ARGS=()
if [ "$PERSIST_ENABLED" -eq 1 ]; then
    if [ -e "$PERSIST_DISK" ] && [ ! -f "$PERSIST_DISK" ]; then
        echo "ERROR: persistent disk is not a regular file: $PERSIST_DISK" >&2
        exit 1
    fi
    if [ ! -f "$PERSIST_DISK" ]; then
        echo "==> Creating ${PERSIST_SIZE_MB} MiB persistent ext2 volume (one-time)..."
        if ! vinix_storage_create_ext2 "$PERSIST_DISK" "$PERSIST_SIZE_MB" "$PERSIST_SEED"; then
            echo "ERROR: could not create persistent volume: $PERSIST_DISK" >&2
            exit 1
        fi
        if [ -n "$PERSIST_SEED" ]; then
            echo "    seeded from $PERSIST_SEED"
        fi
    fi
    PERSIST_DEVICE_ARGS=(
        -drive "if=none,format=raw,file=$PERSIST_DISK,id=vinix-persist"
        -device virtio-blk-device,drive=vinix-persist
    )
    echo "==> Persistent /root volume: $PERSIST_DISK"
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

# Limine supplies modules in configuration order. The kernel unpacks the base,
# the last successfully saved package overlay, and this run's small control
# layer into the same RAM-backed root.
if [ -s "$PACKAGE_STORE" ]; then
    printf '%s\n' '    module_path: boot():/boot/packages.tar' >> "$LIMINE_CONF_QEMU"
fi
printf '%s\n' '    module_path: boot():/boot/qemu-runtime.tar' >> "$LIMINE_CONF_QEMU"

# ── Ensure the selected Limine BOOTAA64.EFI is available ──
# The same source-built loader is what deploy-m1-efi.sh ships, so QEMU
# exercises the deployed build.
LIMINE_EFI="$BOOT_DIR/limine-bin/BOOTAA64.EFI"
if [ ! -f "$LIMINE_EFI" ] || ! "$SCRIPT_DIR/build-limine-aarch64.sh" --check \
    | grep -Fq "Vinix base revision 2 compatibility"; then
    echo "==> Building Limine ${LIMINE_VERSION}..."
    "$SCRIPT_DIR/build-limine-aarch64.sh" || exit 1
fi

# ── Find UEFI firmware ──
# Desktop QEMU can supply a custom OVMF with a larger ramfb GOP mode. Keep the
# packaged firmware as the default for the ordinary shell runner.
OVMF="${VINIX_OVMF_CODE:-}"
if [ -z "$OVMF" ]; then
    OVMF=$(find /opt/homebrew -name "edk2-aarch64-code.fd" 2>/dev/null | head -1)
fi
if [ -z "$OVMF" ] || [ ! -f "$OVMF" ]; then
    echo "ERROR: AArch64 OVMF firmware not found: ${OVMF:-edk2-aarch64-code.fd}."
    echo "Install QEMU (brew install qemu), or set VINIX_OVMF_CODE."
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

if [ "$PERSIST_ENABLED" -eq 1 ] && command -v lsof >/dev/null 2>&1; then
    PERSIST_HOLDERS="$(lsof -t -- "$PERSIST_DISK" 2>/dev/null | tr '\n' ' ')"
    if [ -n "${PERSIST_HOLDERS// /}" ]; then
        echo "ERROR: persistent disk is already in use: $PERSIST_DISK" >&2
        for pid in $PERSIST_HOLDERS; do
            echo "    pid $pid: $(ps -o command= -p "$pid" 2>/dev/null | cut -c1-70)" >&2
        done
        echo "Stop the VM using it before starting another one." >&2
        exit 1
    fi
fi

# Size a new boot disk from the actual initramfs and package archive. Existing
# disks are never reformatted behind the caller's back; an undersized legacy
# image gets a direct migration error instead of a cryptic mcopy failure.
if [ -f "$INITRAMFS" ]; then
    if stat -f%z "$INITRAMFS" >/dev/null 2>&1; then
        initramfs_bytes="$(stat -f%z "$INITRAMFS")"
    else
        initramfs_bytes="$(stat -c%s "$INITRAMFS")"
    fi
    if [ "$initramfs_bytes" -gt 4294967295 ]; then
        echo "ERROR: $INITRAMFS exceeds FAT32's 4 GiB single-file limit." >&2
        echo "       Use a split initramfs and persistent volume, as run-desktop-aarch64.sh does." >&2
        exit 1
    fi
    package_overlay_bytes=0
    if [ -s "$PACKAGE_STORE" ]; then
        if stat -f%z "$PACKAGE_STORE" >/dev/null 2>&1; then
            package_overlay_bytes="$(stat -f%z "$PACKAGE_STORE")"
        else
            package_overlay_bytes="$(stat -c%s "$PACKAGE_STORE")"
        fi
        if [ "$package_overlay_bytes" -gt 4294967295 ]; then
            echo "ERROR: $PACKAGE_STORE exceeds FAT32's 4 GiB single-file limit." >&2
            exit 1
        fi
    fi
    required_bytes=$((initramfs_bytes + package_overlay_bytes + 128 * 1024 * 1024))
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

    if [ ! -f "$BOOT_DISK" ] && [ "$boot_disk_bytes" -lt "$required_bytes" ]; then
        echo "==> Increasing new boot disk to ${required_mb} MiB for the selected initramfs"
        BOOT_DISK_SIZE_MB="$required_mb"
        boot_disk_bytes=$((BOOT_DISK_SIZE_MB * 1024 * 1024))
    elif [ "$boot_disk_bytes" -lt "$required_bytes" ]; then
        echo "ERROR: $BOOT_DISK is too small for this initramfs and package overlay." >&2
        echo "       Need at least ${required_mb} MiB." >&2
        echo "       Remove or archive that old image, then rerun with --disk=$required_mb." >&2
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
    ACTIVE_INITRAMFS="$INITRAMFS"
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
    ACTIVE_INITRAMFS=/tmp/vinix-initramfs.tar
else
    echo "ERROR: no initramfs or fallback init program is available" >&2
    exit 1
fi

# Build a tiny per-run module containing the package frontend, persistence
# helper, store address and a manifest of the immutable base archive. Injecting
# it here makes persistence work with an already-built desktop initramfs.
PACKAGE_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vinix-qemu-runtime.XXXXXX")"
PACKAGE_RUNTIME_ROOT="$PACKAGE_RUNTIME_DIR/root"
PACKAGE_RUNTIME_TAR="$PACKAGE_RUNTIME_DIR/qemu-runtime.tar"
PACKAGE_SERVER_READY="$PACKAGE_RUNTIME_DIR/server.ready"
PACKAGE_SERVER_LOG="$PACKAGE_RUNTIME_DIR/server.log"
PACKAGE_BASE_FILES_RAW="$PACKAGE_RUNTIME_DIR/base-files.raw"
mkdir -p "$PACKAGE_RUNTIME_ROOT/etc/vinix-pkg" \
    "$PACKAGE_RUNTIME_ROOT/usr/bin" "$PACKAGE_RUNTIME_ROOT/usr/libexec"

# Tests may replace PID 1 without copying and rewriting a multi-gigabyte base
# image. Limine loads this per-run module last, so the override exists only in
# the guest's RAM-backed root for this boot.
if [ -n "$GUEST_INIT" ]; then
    mkdir -p "$PACKAGE_RUNTIME_ROOT/sbin"
    install -m755 "$GUEST_INIT" "$PACKAGE_RUNTIME_ROOT/sbin/init"
    echo "==> Injecting test init: $GUEST_INIT"
fi

# Hyprland is an explicit alternate desktop session. Keep the selection in
# this per-run module rather than the image itself: a staged Hyprland runtime
# must not turn the ordinary desktop launcher into its full-screen terminal.
case "${VINIX_BOOT_HYPRLAND:-0}" in
    0|'') ;;
    1)
        mkdir -p "$PACKAGE_RUNTIME_ROOT/etc/vinix"
        : > "$PACKAGE_RUNTIME_ROOT/etc/vinix/boot-hyprland"
        ;;
    *)
        echo "ERROR: VINIX_BOOT_HYPRLAND must be 0 or 1" >&2
        exit 1
        ;;
esac

# Old full-userland archives can contain the Asahi Gallium library and smoke
# test while missing the tiny DRI loader symlink.  A fake-G17 boot is useful
# only when Mesa can open that loader, so carry the matching staged pair in
# the per-run overlay instead of requiring a 1+ GiB userland rebuild.
if [ "$FAKE_G17" -eq 1 ] \
    && ! tar -tf "$ACTIVE_INITRAMFS" \
        | sed 's#^\./##' \
        | grep -qx 'usr/lib/dri/asahi_dri.so'; then
    ASAHI_RUNTIME="$SCRIPT_DIR/build-aarch64-asahi/staging/usr/lib"
    if [ ! -f "$ASAHI_RUNTIME/libgallium-25.0.5.so" ] \
        || [ ! -f "$ASAHI_RUNTIME/dri/libdril_dri.so" ]; then
        echo "ERROR: --fake-g17 needs the staged Mesa Asahi runtime." >&2
        echo "       Run build-asahi-aarch64.sh in the ARM64 build VM first." >&2
        exit 1
    fi
    mkdir -p "$PACKAGE_RUNTIME_ROOT/usr/lib/dri"
    install -m755 "$ASAHI_RUNTIME/libgallium-25.0.5.so" \
        "$PACKAGE_RUNTIME_ROOT/usr/lib/"
    install -m755 "$ASAHI_RUNTIME/dri/libdril_dri.so" \
        "$PACKAGE_RUNTIME_ROOT/usr/lib/dri/"
    ln -sf libdril_dri.so "$PACKAGE_RUNTIME_ROOT/usr/lib/dri/asahi_dri.so"
    echo "==> Injecting Mesa Asahi DRI runtime for fake G17"
fi

# Keep the fake-backend lifecycle smoke test in sync with the kernel under
# test, even when the selected desktop archive predates --submit-only.
if [ "$FAKE_G17" -eq 1 ]; then
    ASAHI_STAGING="$SCRIPT_DIR/build-aarch64-asahi/staging"
    if [ ! -x "$ASAHI_STAGING/usr/bin/gl-triangle-agx" ] \
        || [ ! -f "$ASAHI_STAGING/usr/lib/libvinix-agx-fault.so" ]; then
        echo "ERROR: --fake-g17 needs the staged Mesa lifecycle test." >&2
        echo "       Run build-asahi-aarch64.sh in the ARM64 build VM first." >&2
        exit 1
    fi
    if ! LC_ALL=C grep -aFq \
        'render submit and fence completed successfully; pixels unchecked' \
        "$ASAHI_STAGING/usr/bin/gl-triangle-agx"; then
        echo "ERROR: the staged Mesa lifecycle test predates --submit-only." >&2
        echo "       Re-run build-asahi-aarch64.sh in the ARM64 build VM." >&2
        exit 1
    fi
    if ! LC_ALL=C grep -aFq 'Vinix Fake G17C (M5 Max ABI)' \
        "$ASAHI_STAGING/usr/lib/libgallium-25.0.5.so"; then
        echo "ERROR: the staged Mesa runtime predates fake-G17 identification." >&2
        echo "       Re-run build-asahi-aarch64.sh in the ARM64 build VM." >&2
        exit 1
    fi
    mkdir -p "$PACKAGE_RUNTIME_ROOT/usr/share/examples/gl-triangle"
    install -m755 "$ASAHI_STAGING/usr/bin/gl-triangle-agx" \
        "$PACKAGE_RUNTIME_ROOT/usr/bin/"
    install -m755 "$ASAHI_STAGING/usr/lib/libvinix-agx-fault.so" \
        "$PACKAGE_RUNTIME_ROOT/usr/lib/"
    install -m644 "$SCRIPT_DIR/gl-triangle/egl_triangle.c" \
        "$PACKAGE_RUNTIME_ROOT/usr/share/examples/gl-triangle/"
    install -m755 "$SCRIPT_DIR/gl-triangle/run-gl-triangle-agx" \
        "$PACKAGE_RUNTIME_ROOT/usr/bin/"
fi

if ! tar -tf "$ACTIVE_INITRAMFS" > "$PACKAGE_BASE_FILES_RAW"; then
    echo "ERROR: cannot read the initramfs while building its package manifest" >&2
    exit 1
fi
sed -e 's#^\./##' -e 's#/$##' -e '/^\.$/d' -e '/^$/d' \
    "$PACKAGE_BASE_FILES_RAW" | LC_ALL=C sort -u \
    > "$PACKAGE_RUNTIME_ROOT/etc/vinix-pkg/base-files"
# These parent directories belong to the injected runtime module. Treating
# them as part of the immutable base prevents recursive tar from pulling the
# control files themselves into an installed-package overlay.
printf '%s\n' etc/vinix-pkg usr/bin usr/libexec \
    >> "$PACKAGE_RUNTIME_ROOT/etc/vinix-pkg/base-files"
LC_ALL=C sort -u -o "$PACKAGE_RUNTIME_ROOT/etc/vinix-pkg/base-files" \
    "$PACKAGE_RUNTIME_ROOT/etc/vinix-pkg/base-files"
install -m755 "$SCRIPT_DIR/build-support/vinix-pkg" \
    "$PACKAGE_RUNTIME_ROOT/usr/libexec/vinix-pkg-core"
install -m755 "$SCRIPT_DIR/build-support/vinix-pkg-wrapper" \
    "$PACKAGE_RUNTIME_ROOT/usr/bin/pkg"
install -m755 "$SCRIPT_DIR/build-support/vinix-persist-packages" \
    "$PACKAGE_RUNTIME_ROOT/usr/libexec/vinix-persist-packages"
printf 'http://10.0.2.100:%s\n' "$PACKAGE_STORE_PORT" \
    > "$PACKAGE_RUNTIME_ROOT/etc/vinix-pkg/qemu-store-url"
COPYFILE_DISABLE=1 tar --format=ustar -cf "$PACKAGE_RUNTIME_TAR" \
    -C "$PACKAGE_RUNTIME_ROOT" .
mcopy -o -i "$BOOT_DISK" "$PACKAGE_RUNTIME_TAR" ::/boot/qemu-runtime.tar

if [ -s "$PACKAGE_STORE" ]; then
    if ! tar -tf "$PACKAGE_STORE" >/dev/null 2>&1; then
        echo "ERROR: saved QEMU package overlay is not a readable tar: $PACKAGE_STORE" >&2
        exit 1
    fi
    echo "==> Loading saved package overlay: $PACKAGE_STORE"
    mcopy -o -i "$BOOT_DISK" "$PACKAGE_STORE" ::/boot/packages.tar
fi

# ── Update kernel (the only step on rebuilds) ──
echo "==> Copying Limine config to boot disk..."
mcopy -o -i "$BOOT_DISK" "$LIMINE_CONF_QEMU" ::/boot/limine.conf

echo "==> Copying kernel to boot disk..."
mcopy -o -i "$BOOT_DISK" "$KERNEL_DIR/bin/vinix" ::/boot/vinix

# ── Launch QEMU ──
if [ "$VIRTIO_GPU" -eq 2 ]; then
    # KekVM's compact VirGL build omits libslirp. Keep this mode offline rather
    # than failing QEMU startup on the normal user-network backend.
    NETWORK_FLAGS="-nic none"
    echo "==> VirGL VM is offline (KekVM QEMU has no libslirp backend)"
else
    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is required for QEMU package persistence" >&2
        exit 1
    fi
    python3 "$SCRIPT_DIR/tools/qemu-package-store.py" \
        --store "$PACKAGE_STORE" --port "$PACKAGE_STORE_PORT" \
        --ready-file "$PACKAGE_SERVER_READY" >"$PACKAGE_SERVER_LOG" 2>&1 &
    PACKAGE_SERVER_PID=$!
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [ -s "$PACKAGE_SERVER_READY" ] && break
        if ! kill -0 "$PACKAGE_SERVER_PID" 2>/dev/null; then
            break
        fi
        sleep 0.05
    done
    if [ ! -s "$PACKAGE_SERVER_READY" ]; then
        cat "$PACKAGE_SERVER_LOG" >&2
        echo "ERROR: QEMU package store could not start on port $PACKAGE_STORE_PORT" >&2
        exit 1
    fi
    NETWORK_FLAGS="-netdev user,id=net0,guestfwd=tcp:10.0.2.100:${PACKAGE_STORE_PORT}-tcp:127.0.0.1:${PACKAGE_STORE_PORT} -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56"
    echo "==> Package installs persist in: $PACKAGE_STORE"
fi
echo "==> Starting QEMU (Ctrl-A X to quit)..."

if [ "$VIRTIO_GPU" -eq 2 ] && [ "$SERIAL_ONLY" -eq 1 ]; then
    echo "ERROR: --virgl needs a GL-capable display; do not combine it with --serial" >&2
    exit 1
elif [ "$VIRTIO_GPU" -eq 2 ]; then
    # KekVM's QEMU build provides a Cocoa OpenGL context backed by Metal.
    # virglrenderer uses that context to execute the guest's Gallium commands.
    DISPLAY_BACKEND_FLAGS="-display ${QEMU_DISPLAY_BACKEND:-cocoa,gl=core}"
elif [ "$SERIAL_ONLY" -eq 1 ]; then
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

if [ "$VIRTIO_GPU" -eq 2 ]; then
    DISPLAY_DEVICE_FLAGS="-device ramfb -device virtio-gpu-gl-device,max_outputs=1"
elif [ "$VIRTIO_GPU" -eq 1 ]; then
    # Keep ramfb as primary scanout so firmware/GOP always exposes a visible
    # framebuffer, then expose the MMIO transport used by the ARM64 driver.
    DISPLAY_DEVICE_FLAGS="-device ramfb -device virtio-gpu-device,max_outputs=1"
else
    DISPLAY_DEVICE_FLAGS="-device ramfb"
fi

# Multiplex the serial console and QEMU monitor so Ctrl-A X exits as advertised.
DISPLAY_FLAGS="$DISPLAY_DEVICE_FLAGS $DISPLAY_BACKEND_FLAGS -serial mon:stdio"

ACCEL_FLAGS="-accel hvf -cpu host"
if [ "${USE_TCG:-0}" -eq 1 ]; then
    # The kernel is compiled for ARMv8.4-A. cortex-a72 only implements an
    # older architecture level and can stall before the serial console.
    ACCEL_FLAGS="-accel tcg -cpu ${VINIX_QEMU_CPU:-max}"
fi

# VINIX_QEMU_EXTRA appends raw flags, e.g. a monitor socket to drive
# screendump from a script. Keep the runner alive to own the loopback package
# store for the lifetime of the VM.
QEMU_BIN="${VINIX_QEMU_BIN:-qemu-system-aarch64}"
if [ "$VIRTIO_GPU" -eq 2 ]; then
    QEMU_BIN="${VINIX_VIRGL_QEMU:-$SCRIPT_DIR/../kekvm/.tools/qemu-virgl/bin/qemu-system-aarch64}"
    if [ ! -x "$QEMU_BIN" ]; then
        echo "ERROR: KekVM's VirGL QEMU was not found at $QEMU_BIN" >&2
        echo "       Run 'make setup-gpu' in ../kekvm or set VINIX_VIRGL_QEMU." >&2
        exit 1
    fi
fi

set +e
"$QEMU_BIN" \
    ${VINIX_QEMU_EXTRA} \
    -machine virt,gic-version=3 \
    $ACCEL_FLAGS \
    -m "$QEMU_MEM" \
    -smp 4 \
    -object rng-random,filename=/dev/urandom,id=vinix-rng \
    -device virtio-rng-device,rng=vinix-rng \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive format=raw,file="$BOOT_DISK" \
    "${PERSIST_DEVICE_ARGS[@]}" \
    -device virtio-keyboard-device \
    -device virtio-tablet-device \
    $NETWORK_FLAGS \
    $DISPLAY_FLAGS \
    -no-reboot
qemu_status=$?
set -e
exit "$qemu_status"
