#!/bin/bash
# Build the amd64 Alpine userland, Vinix kernel, and bootable UEFI ISO. The
# userland is prebuilt Alpine; the kernel uses the host clang directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AMD64_BUILD_DIR:-$SCRIPT_DIR/build-amd64-kernel}"
USERLAND_DIR="${VINIX_AMD64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-amd64-userland}"
OUTPUT_ISO="${VINIX_AMD64_ISO:-$SCRIPT_DIR/vinix.iso}"
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
        echo "ERROR: refusing unsafe amd64 kernel build directory: $BUILD_DIR" >&2
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
    echo "==> Building the Alpine x86_64 userland..."
    VINIX_AMD64_USERLAND_BUILD_DIR="$USERLAND_DIR" \
        "$SCRIPT_DIR/build-userland-amd64.sh"
elif [ "$BUILD_ISO" -eq 1 ] && [ ! -f "$USERLAND_DIR/initramfs.tar" ]; then
    echo "ERROR: --no-userland needs $USERLAND_DIR/initramfs.tar" >&2
    exit 1
fi

echo "==> Building the amd64 Vinix kernel..."
mkdir -p "$BUILD_DIR"
# Keep architecture-specific objects outside kernel/. Excluded generated
# directories survive rsync so repeated builds remain incremental.
rsync -a --delete \
    --exclude '/bin/' \
    --exclude '/obj/' \
    --exclude '/cc-runtime-x86_64/' \
    --exclude '/cc-runtime-aarch64/' \
    "$SCRIPT_DIR/kernel/" "$BUILD_DIR/"

LD_X86_64="${VINIX_LD_X86_64:-$(command -v ld.lld)}"
LLVM_AR="${VINIX_LLVM_AR:-/opt/homebrew/opt/llvm/bin/llvm-ar}"
if [ ! -x "$LLVM_AR" ]; then
    LLVM_AR="$(command -v llvm-ar || true)"
fi
if [ -z "$LLVM_AR" ]; then
    echo "ERROR: llvm-ar is required for the amd64 kernel runtime." >&2
    exit 1
fi
KERNEL_MAKE=(make -C "$BUILD_DIR" ARCH=x86_64 CC=clang "AR=$LLVM_AR" \
    "LD_X86_64=$LD_X86_64" V="$V")
if [ -n "${PROD:-}" ]; then
    KERNEL_MAKE+=("PROD=$PROD")
fi
"${KERNEL_MAKE[@]}" -j"$NPROC"

if [ "$BUILD_ISO" -eq 1 ]; then
    VINIX_AMD64_KERNEL="$BUILD_DIR/bin/vinix" \
    VINIX_AMD64_INITRAMFS="$USERLAND_DIR/initramfs.tar" \
    VINIX_AMD64_ISO="$OUTPUT_ISO" \
        "$SCRIPT_DIR/build-support/build-amd64-iso.sh"
fi
