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
#   --mem=MB        guest RAM (default: 8192 MiB for the desktop image)
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
# The desktop's root filesystem is loaded into RAM during boot.  The generic
# runner defaults to 2 GiB for small shell images, whereas this image needs at
# least 8 GiB.  An explicit environment setting or --mem=MB still wins.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/build-support/find-v.sh"

KERNEL_DIR="$SCRIPT_DIR/kernel"
DESKTOP_INITRAMFS="$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar"
# The desktop archive is deliberately independent of the ordinary shell image
# and can be much larger.  Give it its own 2 GiB sparse disk so an existing
# small boot-image/boot.img remains usable for fast non-desktop QEMU boots.
# Honour an explicit path so callers can still run more than one desktop VM.
export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop.img}"
export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-2048}"
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
PASSTHROUGH=()

for arg in "$@"; do
    case "$arg" in
        --no-build)   BUILD_KERNEL=0; BUILD_DESKTOP=0 ;;
        --no-kernel)  BUILD_KERNEL=0 ;;
        --no-desktop) BUILD_DESKTOP=0 ;;
        --monitor)    WITH_MONITOR=1 ;;
        --help|-h)    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
        *)            PASSTHROUGH+=("$arg") ;;
    esac
done

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

export VINIX_INITRAMFS="$DESKTOP_INITRAMFS"
echo "==> Starting the desktop (Ctrl-A X to quit)..."
exec "$SCRIPT_DIR/run-aarch64.sh" --no-build "${PASSTHROUGH[@]}"
