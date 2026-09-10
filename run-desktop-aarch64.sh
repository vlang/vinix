#!/bin/bash
# Build and boot Vinix into its desktop, in QEMU. One command for the GUI.
#
# Usage: ./run-desktop-aarch64.sh [options]
#
#   --no-build      boot what is already built
#   --no-kernel     skip the kernel build (the desktop is what you changed)
#   --no-desktop    skip the desktop build (the kernel is what you changed)
#   --monitor       open a QEMU monitor and QMP socket, so the tools under
#                   desktop/tools can drive and photograph the running desktop
#   --no-persist    use the full RAM-backed desktop instead of persistent /root
#   --ephemeral     isolate and automatically delete this run's boot image
#   --mem=MB        guest RAM (default: 8192 MiB for the desktop image)
#   --v=PATH        V compiler executable or checkout (for example ~/code/v7)
#   --help
#
# Anything else is passed through to run-aarch64.sh, which is what actually
# starts QEMU: --mem=MB, --serial, --virtio-gpu, --virgl, --grab-keys. The
# last of those is what Cmd-Tab needs on a Mac: macOS keeps the chord for its
# own application switcher unless QEMU is allowed to capture every key.
#
# The two builds are done here rather than left to run-aarch64.sh so that a
# failure in either is reported plainly, and so the kernel build gets a V it
# can actually find.
# The immutable desktop system is loaded into RAM during boot, while the normal
# QEMU profile mounts a persistent /root. The generic runner defaults to 2 GiB
# for small shell images, whereas this image needs at least 8 GiB. An explicit
# environment setting or --mem=MB still wins.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

KERNEL_DIR="$SCRIPT_DIR/kernel"
DESKTOP_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar"
QEMU_DESKTOP_INITRAMFS="$SCRIPT_DIR/build/initramfs-desktop-qemu.tar"
DESKTOP_ROOT_SEED="$SCRIPT_DIR/build/desktop-root-seed.tar.gz"
DESKTOP_STORAGE_MANIFEST="$SCRIPT_DIR/build/desktop-qemu-storage.json"
export VINIX_QEMU_MEM="${VINIX_QEMU_MEM:-8192}"
# The desktop uses a 2x version of the normal QEMU framebuffer (1024x768),
# giving it a native 2048x1536 framebuffer without changing the standard
# shell runner.
export VINIX_QEMU_RESOLUTION="${VINIX_QEMU_RESOLUTION:-2048x1536x32}"
# Do not scale the guest display: the custom OVMF below exposes 2048x1536 to
# Limine and the kernel. On Retina Macs this naturally occupies 1024x768
# points while retaining all 2048x1536 guest pixels.
export VINIX_QEMU_COCOA_OPTIONS="${VINIX_QEMU_COCOA_OPTIONS:-zoom-to-fit=off}"
if [ -z "${VINIX_OVMF_CODE:-}" ]; then
    export VINIX_OVMF_CODE="$SCRIPT_DIR/boot-image/edk2-aarch64-code-2048x1536.fd"
    if [ ! -f "$VINIX_OVMF_CODE" ]; then
        "$SCRIPT_DIR/build-qemu-ovmf-aarch64.sh"
    fi
fi
MONITOR_SOCKET="${VINIX_MONITOR_SOCKET:-/tmp/vinix-monitor}"
QMP_SOCKET="${VINIX_QMP_SOCKET:-/tmp/vinix-qmp}"

BUILD_KERNEL=1
BUILD_DESKTOP=1
WITH_MONITOR=0
PERSIST_DESKTOP="${VINIX_QEMU_PERSIST:-1}"
EPHEMERAL_DESKTOP=0
PASSTHROUGH=()

while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
        --no-build)   BUILD_KERNEL=0; BUILD_DESKTOP=0 ;;
        --no-kernel)  BUILD_KERNEL=0 ;;
        --no-desktop) BUILD_DESKTOP=0 ;;
        --monitor)    WITH_MONITOR=1 ;;
        --persist|--persist=*) PERSIST_DESKTOP=1; PASSTHROUGH+=("$arg") ;;
        --no-persist) PERSIST_DESKTOP=0; PASSTHROUGH+=("$arg") ;;
        --ephemeral)  EPHEMERAL_DESKTOP=1; PASSTHROUGH+=("$arg") ;;
        --v=*)        VINIX_V_COMPILER="${arg#*=}" ;;
        --v)
            shift
            if [ "$#" -eq 0 ]; then
                echo "ERROR: --v requires a compiler executable or checkout path" >&2
                exit 1
            fi
            VINIX_V_COMPILER="$1"
            ;;
        --help|-h)    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
        *)            PASSTHROUGH+=("$arg") ;;
    esac
    shift
done

case "$PERSIST_DESKTOP" in
    0|1) ;;
    *)
        echo "ERROR: VINIX_QEMU_PERSIST must be 0 or 1" >&2
        exit 1
        ;;
esac

# Keep the chosen compiler in the environment so build-desktop-aarch64.sh
# resolves the same compiler after this runner invokes it.
if [ "$BUILD_KERNEL" -eq 1 ] || [ "$BUILD_DESKTOP" -eq 1 ]; then
    . "$SCRIPT_DIR/build-support/find-v.sh"
fi

# ── The kernel ──
# The desktop needs /dev/fb0 and /dev/pointer, both of which live in it.
if [ "$BUILD_KERNEL" -eq 1 ]; then
    echo "==> Building the kernel..."
    make -C "$KERNEL_DIR" CC=clang ARCH=aarch64 V="$V" LIMINE_MP=1 \
        -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
fi

if [ ! -f "$KERNEL_DIR/bin/vinix" ]; then
    echo "ERROR: $KERNEL_DIR/bin/vinix not found; build the kernel first" >&2
    exit 1
fi

# ── The desktop ──
if [ "$BUILD_DESKTOP" -eq 1 ]; then
    "$SCRIPT_DIR/build-desktop-aarch64.sh"
fi

if [ ! -f "$DESKTOP_INITRAMFS" ]; then
    echo "ERROR: $DESKTOP_INITRAMFS not found." >&2
    echo "Run ./build-desktop-aarch64.sh, or drop --no-build/--no-desktop." >&2
    exit 1
fi

# QEMU keeps mutable desktop data on one stable ext2 volume. The hardware
# initramfs remains self-contained; this cached QEMU view removes /root from
# the boot payload and turns it into the one-time seed for that volume.
if [ "$PERSIST_DESKTOP" -eq 1 ]; then
    python3 "$SCRIPT_DIR/tools/split-desktop-initramfs.py" \
        "$DESKTOP_INITRAMFS" "$QEMU_DESKTOP_INITRAMFS" \
        "$DESKTOP_ROOT_SEED" "$DESKTOP_STORAGE_MANIFEST"
    export VINIX_INITRAMFS="$QEMU_DESKTOP_INITRAMFS"
    export VINIX_QEMU_PERSIST=1
    if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
        export VINIX_QEMU_PERSIST_DISK="${VINIX_QEMU_PERSIST_DISK:-$SCRIPT_DIR/boot-image/desktop-root.ext2}"
    fi
    export VINIX_QEMU_PERSIST_SIZE_MB="${VINIX_QEMU_PERSIST_SIZE_MB:-3072}"
    export VINIX_QEMU_PERSIST_SEED="${VINIX_QEMU_PERSIST_SEED:-$DESKTOP_ROOT_SEED}"
    if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
        export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop-qemu.img}"
    fi
    export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-3072}"
else
    export VINIX_INITRAMFS="$DESKTOP_INITRAMFS"
    export VINIX_QEMU_PERSIST=0
    if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
        export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop-full.img}"
    fi
    export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-4096}"
fi
if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
    export VINIX_QEMU_PACKAGE_STORE="${VINIX_QEMU_PACKAGE_STORE:-$SCRIPT_DIR/boot-image/boot-desktop-4096.img.packages.tar}"
fi

# ── Boot ──
# run-aarch64.sh owns the QEMU invocation — the loader, the firmware, the boot
# disk and the devices. It is told not to build, because both builds are
# already done and its own kernel build would run without a usable V.
if [ "$WITH_MONITOR" -eq 1 ]; then
    # QEMU will not bind a socket path that already exists.
    rm -f "$MONITOR_SOCKET" "$QMP_SOCKET"
    export VINIX_QEMU_EXTRA="${VINIX_QEMU_EXTRA} -monitor unix:${MONITOR_SOCKET},server,nowait -qmp unix:${QMP_SOCKET},server,nowait"
    echo "==> Monitor: ${MONITOR_SOCKET}   QMP: ${QMP_SOCKET}"
    echo "    python3 desktop/tools/input.py click X Y"
    echo "    ./desktop/tools/screenshot.sh /tmp/shot.png"
fi

echo "==> Starting the desktop (Ctrl-A X to quit)..."
exec "$SCRIPT_DIR/run-aarch64.sh" --no-build "${PASSTHROUGH[@]}"
