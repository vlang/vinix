#!/bin/bash
# Build the aarch64 Alpine userland, Vinix kernel, and UEFI ISO without a
# source-built libc, command suite, or target GCC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AARCH64_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-kernel}"
USERLAND_DIR="${VINIX_AARCH64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-aarch64-userland}"
INITRAMFS="${VINIX_AARCH64_INITRAMFS:-$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar}"
OUTPUT_ISO="${VINIX_AARCH64_ISO:-$SCRIPT_DIR/vinix-aarch64.iso}"
NPROC="${NPROC:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)}"
BUILD_USERLAND=1
BUILD_ISO=1

for arg in "$@"; do
    case "$arg" in
        --no-userland) BUILD_USERLAND=0 ;;
        --no-iso) BUILD_ISO=0 ;;
        --help|-h)
            echo "usage: $0 [--no-userland] [--no-iso]"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe aarch64 kernel build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac
for command_name in clang ld.lld make rsync; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $command_name" >&2
        exit 1
    }
done

. "$SCRIPT_DIR/build-support/find-v.sh"

if [ ! -d "$SCRIPT_DIR/kernel/freestnd-c-hdrs" ] ||
   [ ! -d "$SCRIPT_DIR/kernel/cc-runtime" ] ||
   [ ! -d "$SCRIPT_DIR/kernel/c/flanterm" ] ||
   [ ! -f "$SCRIPT_DIR/kernel/c/nanoprintf.h" ] ||
   [ ! -f "$SCRIPT_DIR/kernel/c/lwip/include/lwip/init.h" ]; then
    echo "==> Fetching pinned kernel dependencies..."
    "$SCRIPT_DIR/kernel/get-deps"
fi

if [ "$BUILD_USERLAND" -eq 1 ]; then
    echo "==> Building the Alpine aarch64 userland..."
    VINIX_AARCH64_USERLAND_BUILD_DIR="$USERLAND_DIR" \
    VINIX_AARCH64_INITRAMFS="$INITRAMFS" \
    VINIX_ALPINE_BASE_ONLY="${VINIX_ALPINE_BASE_ONLY:-1}" \
        "$SCRIPT_DIR/build-userland-aarch64.sh"
elif [ "$BUILD_ISO" -eq 1 ] && [ ! -f "$INITRAMFS" ]; then
    echo "ERROR: --no-userland needs $INITRAMFS" >&2
    exit 1
fi

echo "==> Building the aarch64 Vinix kernel..."
mkdir -p "$BUILD_DIR"
rsync -a --delete \
    --exclude '/bin/' \
    --exclude '/obj/' \
    --exclude '/cc-runtime-x86_64/' \
    --exclude '/cc-runtime-aarch64/' \
    "$SCRIPT_DIR/kernel/" "$BUILD_DIR/"

LLVM_AR="${VINIX_LLVM_AR:-/opt/homebrew/opt/llvm/bin/llvm-ar}"
if [ ! -x "$LLVM_AR" ]; then
    LLVM_AR="$(command -v llvm-ar || true)"
fi
if [ -z "$LLVM_AR" ]; then
    echo "ERROR: llvm-ar is required for the aarch64 kernel runtime." >&2
    exit 1
fi
KERNEL_MAKE=(make -C "$BUILD_DIR" ARCH=aarch64 CC=clang AR="$LLVM_AR" \
    LD_AARCH64="${VINIX_LD_AARCH64:-$(command -v ld.lld)}" V="$V" LIMINE_MP=1)
if [ -n "${PROD:-}" ]; then
    KERNEL_MAKE+=("PROD=$PROD")
fi
"${KERNEL_MAKE[@]}" -j"$NPROC"

if [ "$BUILD_ISO" -eq 1 ]; then
    VINIX_AARCH64_KERNEL="$BUILD_DIR/bin/vinix" \
    VINIX_AARCH64_INITRAMFS="$INITRAMFS" \
    VINIX_AARCH64_ISO="$OUTPUT_ISO" \
        "$SCRIPT_DIR/build-support/build-aarch64-iso.sh"
fi
