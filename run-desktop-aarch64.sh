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
#   --no-disk-root  keep the old layout: a RAM system with a persistent /root
#   --reset-disk    reinstall the system volume from scratch, losing its data
#   --no-persist    use the full RAM-backed desktop instead of persistent /root
#   --ephemeral     isolate and automatically delete this run's boot image
#   gpuvm           boot with KekVM's accelerated VirGL GPU
#   --virgl         use KekVM's GPU backend with a RAM system and persistent /root
#   --venus         use KekVM's Venus Vulkan GPU (OpenGothic)
#   --mem=MB        guest RAM (default: 8192 MiB, or 12288 MiB for gpuvm)
#   --v=PATH        V compiler executable or checkout (for example ~/code/v/v)
#   --help
#
# Anything else is passed through to run-aarch64.sh, which is what actually
# starts QEMU: --mem=MB, --serial, --virtio-gpu, and --virgl.
#
# The two builds are done here rather than left to run-aarch64.sh so that a
# failure in either is reported plainly, and so the kernel build gets a V it
# can actually find.
# By default the whole system is installed onto a persistent volume and booted
# from it, so every write survives a restart and not only the ones below /root.
# The image is reinstalled when it changes, carrying /root across; --reset-disk
# asks for the clean install and --no-disk-root returns to the old layout, in
# which the system is loaded into RAM and only /root persists.
#
# The generic runner defaults to 2 GiB for small shell images. The desktop
# needs 8 GiB; its VirGL and full RAM images need 12 GiB while Limine loads
# them. An explicit environment setting or --mem=MB still wins.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

KERNEL_DIR="${VINIX_KERNEL_DIR:-$SCRIPT_DIR/kernel}"
# Overridable so a test can boot an image of its own without replacing the one
# build-desktop-aarch64.sh writes for the deployment scripts.
DESKTOP_INITRAMFS="${VINIX_DESKTOP_INITRAMFS:-$SCRIPT_DIR/build-support/init-aarch64/initramfs-desktop.tar}"
QEMU_DESKTOP_INITRAMFS="$SCRIPT_DIR/build/initramfs-desktop-qemu.tar"
QEMU_DESKTOP_PARTS="$SCRIPT_DIR/build/initramfs-desktop-qemu-parts"
QEMU_DESKTOP_FULL_PARTS="$SCRIPT_DIR/build/initramfs-desktop-full-parts"
QEMU_DESKTOP_ISO="$SCRIPT_DIR/build/initramfs-desktop-qemu.iso"
QEMU_DESKTOP_FULL_ISO="$SCRIPT_DIR/build/initramfs-desktop-full.iso"
DESKTOP_ROOT_SEED="$SCRIPT_DIR/build/desktop-root-seed.tar.gz"
DESKTOP_STORAGE_MANIFEST="$SCRIPT_DIR/build/desktop-qemu-storage.json"
DESKTOP_BUILD_KEY="$SCRIPT_DIR/build/run-desktop-aarch64.key"
# The desktop uses a 2x version of the normal QEMU framebuffer (1024x768),
# giving it a native 2048x1536 framebuffer without changing the standard
# shell runner.
export VINIX_QEMU_RESOLUTION="${VINIX_QEMU_RESOLUTION:-2048x1536x32}"
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
DISK_ROOT_DESKTOP="${VINIX_QEMU_ROOT_DISK:-1}"
EPHEMERAL_DESKTOP=0
ROOT_LAYOUT_EXPLICIT=0
VIRGL_DESKTOP=0
PASSTHROUGH=()

while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
        --no-build)   BUILD_KERNEL=0; BUILD_DESKTOP=0 ;;
        --no-kernel)  BUILD_KERNEL=0 ;;
        --no-desktop) BUILD_DESKTOP=0 ;;
        --monitor)    WITH_MONITOR=1 ;;
        --persist|--persist=*) PERSIST_DESKTOP=1; PASSTHROUGH+=("$arg") ;;
        --no-persist) PERSIST_DESKTOP=0; DISK_ROOT_DESKTOP=0; PASSTHROUGH+=("$arg") ;;
        --disk-root)    DISK_ROOT_DESKTOP=1; ROOT_LAYOUT_EXPLICIT=1 ;;
        --no-disk-root) DISK_ROOT_DESKTOP=0; ROOT_LAYOUT_EXPLICIT=1 ;;
        gpuvm|--virgl) VIRGL_DESKTOP=1; PASSTHROUGH+=(--virgl) ;;
        --venus) VIRGL_DESKTOP=1; PASSTHROUGH+=(--venus) ;;
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

if [ "$VIRGL_DESKTOP" -eq 1 ] || [ "$PERSIST_DESKTOP" -eq 0 ]; then
    export VINIX_QEMU_MEM="${VINIX_QEMU_MEM:-12288}"
else
    export VINIX_QEMU_MEM="${VINIX_QEMU_MEM:-8192}"
fi

if [ "$VIRGL_DESKTOP" -eq 1 ] && [ "$DISK_ROOT_DESKTOP" -eq 1 ]; then
    if [ "$ROOT_LAYOUT_EXPLICIT" -eq 1 ]; then
        echo "ERROR: --virgl needs --no-disk-root so its Mesa runtime overlays the guest image" >&2
        exit 1
    fi
    echo "==> VirGL uses a RAM system with a separate persistent /root volume"
    DISK_ROOT_DESKTOP=0
fi

case "$PERSIST_DESKTOP" in
    0|1) ;;
    *)
        echo "ERROR: VINIX_QEMU_PERSIST must be 0 or 1" >&2
        exit 1
        ;;
esac
case "$DISK_ROOT_DESKTOP" in
    0|1) ;;
    *)
        echo "ERROR: VINIX_QEMU_ROOT_DISK must be 0 or 1" >&2
        exit 1
        ;;
esac
if [ "$DISK_ROOT_DESKTOP" -eq 1 ] && [ "$PERSIST_DESKTOP" -eq 0 ]; then
    echo "ERROR: --no-persist and --disk-root ask for opposite things" >&2
    exit 1
fi

# Keep the chosen compiler in the environment so build-desktop-aarch64.sh
# resolves the same compiler after this runner invokes it.
if [ "$BUILD_KERNEL" -eq 1 ] || [ "$BUILD_DESKTOP" -eq 1 ]; then
    . "$SCRIPT_DIR/build-support/find-v.sh"
    echo "==> V compiler: $V ($("$V" -version 2>/dev/null || echo unknown version))"
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
# A warm desktop run used to spend most of its time regenerating byte-identical
# desktop binaries before build-desktop-aarch64.sh could discover that the
# final 7+ GiB archive was unchanged. Fingerprint all source/tool/layer inputs
# before entering that pipeline. The marker also records the image identity so
# a direct/manual image rebuild cannot leave a stale key that skips necessary
# work on the next runner invocation.
desktop_image_id() {
    local image="$1"
    local size mtime

    if size="$(stat -f%z "$image" 2>/dev/null)"; then
        mtime="$(stat -f%m "$image")"
    else
        size="$(stat -c%s "$image")"
        mtime="$(stat -c%Y "$image")"
    fi
    printf '%s-%s\n' "$size" "$mtime"
}

desktop_build_key() {
    python3 "$SCRIPT_DIR/build-support/desktop-build-key.py" \
        --root "$SCRIPT_DIR" --v "$V"
}

write_desktop_build_key() {
    local key="$1"
    local temp

    [ -n "$key" ] || return 0
    mkdir -p "$SCRIPT_DIR/build"
    temp="$(mktemp "$SCRIPT_DIR/build/.run-desktop-aarch64.key.XXXXXX")"
    {
        printf '%s\n' "$key"
        printf '%s\n' "$DESKTOP_INITRAMFS"
        desktop_image_id "$DESKTOP_INITRAMFS"
    } > "$temp"
    mv -f "$temp" "$DESKTOP_BUILD_KEY"
}

prepare_qemu_initramfs_parts() {
    local source="$1"
    local directory="$2"
    local output part
    local -a parts=()

    output="$(python3 "$SCRIPT_DIR/tools/split-qemu-initramfs.py" "$source" "$directory")"
    while IFS= read -r part; do
        [ -z "$part" ] || parts+=("$part")
    done <<< "$output"
    if [ "${#parts[@]}" -eq 0 ]; then
        echo "ERROR: no QEMU desktop modules were produced" >&2
        return 1
    fi
    export VINIX_INITRAMFS="${parts[0]}"
    export VINIX_INITRAMFS_COMPRESSED=0
    export VINIX_QEMU_BASE_ARCHIVE="$source"
    export VINIX_QEMU_MODULE_MANIFEST="$directory/manifest.json"
    export VINIX_QEMU_MODULE_ISO=""
    export VINIX_QEMU_EXTRA_MODULES=""
    if [ "${#parts[@]}" -gt 1 ]; then
        export VINIX_QEMU_EXTRA_MODULES="$(printf '%s\n' "${parts[@]:1}")"
    fi
}

prepare_qemu_initramfs() {
    local source="$1"
    local iso="$2"
    local parts="$3"

    if command -v xorriso >/dev/null 2>&1; then
        python3 "$SCRIPT_DIR/tools/build-qemu-module-iso.py" "$source" "$iso"
        export VINIX_INITRAMFS="$source"
        export VINIX_INITRAMFS_COMPRESSED=0
        export VINIX_QEMU_MODULE_ISO="$iso"
        export VINIX_QEMU_BASE_ARCHIVE=""
        export VINIX_QEMU_MODULE_MANIFEST=""
        export VINIX_QEMU_EXTRA_MODULES=""
    else
        echo "==> xorriso is unavailable; using split FAT32 modules"
        prepare_qemu_initramfs_parts "$source" "$parts"
    fi
}

if [ "$BUILD_DESKTOP" -eq 1 ]; then
    DESKTOP_INPUT_KEY=""
    if [ "${VINIX_REFRESH_DESKTOP_STAGING:-0}" != 1 ] &&
       [ -f "$SCRIPT_DIR/build-support/desktop-build-key.py" ]; then
        DESKTOP_INPUT_KEY="$(desktop_build_key 2>/dev/null || true)"
    fi

    DESKTOP_KEY_MATCH=0
    if [ -n "$DESKTOP_INPUT_KEY" ] && [ -s "$DESKTOP_INITRAMFS" ] &&
       [ -s "$DESKTOP_BUILD_KEY" ]; then
        DESKTOP_KEY_EXPECTED="$(mktemp "$SCRIPT_DIR/build/.run-desktop-aarch64.expected.XXXXXX")"
        {
            printf '%s\n' "$DESKTOP_INPUT_KEY"
            printf '%s\n' "$DESKTOP_INITRAMFS"
            desktop_image_id "$DESKTOP_INITRAMFS"
        } > "$DESKTOP_KEY_EXPECTED"
        if cmp -s "$DESKTOP_KEY_EXPECTED" "$DESKTOP_BUILD_KEY"; then
            DESKTOP_KEY_MATCH=1
        fi
        rm -f "$DESKTOP_KEY_EXPECTED"
    fi

    if [ "$DESKTOP_KEY_MATCH" -eq 1 ]; then
        echo "==> Desktop build inputs unchanged; reusing existing image"
    else
        "$SCRIPT_DIR/build-desktop-aarch64.sh"
        # Recompute after a successful build because the builder may refresh an
        # old base userland as part of satisfying its prerequisites.
        if [ -f "$SCRIPT_DIR/build-support/desktop-build-key.py" ]; then
            DESKTOP_INPUT_KEY="$(desktop_build_key 2>/dev/null || true)"
            write_desktop_build_key "$DESKTOP_INPUT_KEY"
        fi
    fi
fi

if [ ! -f "$DESKTOP_INITRAMFS" ]; then
    echo "ERROR: $DESKTOP_INITRAMFS not found." >&2
    echo "Run ./build-desktop-aarch64.sh, or drop --no-build/--no-desktop." >&2
    exit 1
fi

# The whole system goes on one ext2 volume and the machine boots from it, so a
# write anywhere survives a restart. The hardware initramfs is unchanged and
# stays self-contained; what the boot payload carries here shrinks to a
# recovery shell, avoiding a large Limine module on every boot.
if [ "$DISK_ROOT_DESKTOP" -eq 1 ]; then
    export VINIX_QEMU_ROOT_DISK=1
    export VINIX_QEMU_ROOT_IMAGE="$DESKTOP_INITRAMFS"
    export VINIX_INITRAMFS="$DESKTOP_INITRAMFS"
    export VINIX_INITRAMFS_COMPRESSED=0
    export VINIX_QEMU_MODULE_ISO=""
    export VINIX_QEMU_EXTRA_MODULES=""
    export VINIX_QEMU_BASE_ARCHIVE=""
    export VINIX_QEMU_MODULE_MANIFEST=""
    export VINIX_QEMU_PERSIST=1
    if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
        # A different file from the /root-only volume on purpose: that one has
        # no system on it, and the installer refuses it rather than writing a
        # system over somebody's home directory.
        export VINIX_QEMU_PERSIST_DISK="${VINIX_QEMU_PERSIST_DISK:-$SCRIPT_DIR/boot-image/desktop-system.ext2}"
        export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop-disk.img}"
        # Machines that ran the /root-only layout keep their home: the first
        # install takes it out of that volume, which is left untouched.
        export VINIX_QEMU_ROOT_ADOPT_HOME="${VINIX_QEMU_ROOT_ADOPT_HOME:-$SCRIPT_DIR/boot-image/desktop-root.ext2}"
    fi
    # The volume is this machine's disk, not a copy of the image: leave room
    # for what gets installed on it later. It is sparse, so the size is a
    # ceiling rather than a cost.
    export VINIX_QEMU_PERSIST_SIZE_MB="${VINIX_QEMU_PERSIST_SIZE_MB:-8192}"
    # Only Limine, the kernel and a recovery shell live here now.
    export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-512}"
elif [ "$PERSIST_DESKTOP" -eq 1 ]; then
    export VINIX_QEMU_ROOT_DISK=0
    python3 "$SCRIPT_DIR/tools/split-desktop-initramfs.py" \
        "$DESKTOP_INITRAMFS" "$QEMU_DESKTOP_INITRAMFS" \
        "$DESKTOP_ROOT_SEED" "$DESKTOP_STORAGE_MANIFEST"
    prepare_qemu_initramfs "$QEMU_DESKTOP_INITRAMFS" "$QEMU_DESKTOP_ISO" "$QEMU_DESKTOP_PARTS"
    export VINIX_QEMU_PERSIST=1
    if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
        export VINIX_QEMU_PERSIST_DISK="${VINIX_QEMU_PERSIST_DISK:-$SCRIPT_DIR/boot-image/desktop-root.ext2}"
    fi
    export VINIX_QEMU_PERSIST_SIZE_MB="${VINIX_QEMU_PERSIST_SIZE_MB:-3072}"
    export VINIX_QEMU_PERSIST_SEED="${VINIX_QEMU_PERSIST_SEED:-$DESKTOP_ROOT_SEED}"
    if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
        if [ -n "$VINIX_QEMU_MODULE_ISO" ]; then
            export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop-qemu-iso.img}"
        else
            export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop-qemu-uncompressed.img}"
        fi
    fi
    if [ -n "$VINIX_QEMU_MODULE_ISO" ]; then
        # Leave room for packages installed after the first boot. The FAT
        # image is sparse, and the base desktop module stays on the ISO.
        export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-3072}"
    else
        export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-6144}"
    fi
else
    export VINIX_QEMU_ROOT_DISK=0
    prepare_qemu_initramfs "$DESKTOP_INITRAMFS" "$QEMU_DESKTOP_FULL_ISO" "$QEMU_DESKTOP_FULL_PARTS"
    export VINIX_QEMU_PERSIST=0
    if [ "$EPHEMERAL_DESKTOP" -eq 0 ]; then
        if [ -n "$VINIX_QEMU_MODULE_ISO" ]; then
            export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop-full-iso.img}"
        else
            export VINIX_BOOT_DISK="${VINIX_BOOT_DISK:-$SCRIPT_DIR/boot-image/boot-desktop-full-uncompressed.img}"
        fi
    fi
    if [ -n "$VINIX_QEMU_MODULE_ISO" ]; then
        export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-4096}"
    else
        export VINIX_BOOT_DISK_SIZE_MB="${VINIX_BOOT_DISK_SIZE_MB:-8192}"
    fi
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
