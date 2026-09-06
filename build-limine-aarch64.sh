#!/bin/bash
# Build the Limine aarch64 UEFI loader used by both run-aarch64.sh and
# deploy-m1-efi.sh, with the local patches applied.
#
# Why a local build: the upstream 9.3.0 binary boots this kernel on QEMU but
# not on Apple Silicon. Its EL2-to-EL1 hand-off assumes it can switch VHE off,
# and Apple cores cannot (HCR_EL2.E2H reads as 1 whatever is written). The
# patch under build-support/limine/ makes the hand-off follow the VHE register
# layouts in that case, so FP/SIMD and the physical timer stop trapping to EL2
# the moment the kernel or userland touches them.
#
# Usage: ./build-limine-aarch64.sh            build and install
#        ./build-limine-aarch64.sh --check    report which loader is installed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIMINE_VERSION="9.3.0"
BOOT_DIR="$SCRIPT_DIR/boot-image"
SRC_DIR="$BOOT_DIR/limine-src-${LIMINE_VERSION}"
PATCH_DIR="$SCRIPT_DIR/build-support/limine"
INSTALL_DIR="$BOOT_DIR/limine-bin"
INSTALLED="$INSTALL_DIR/BOOTAA64.EFI"

# The patched hand-off contains `mov x8, #0x330000; msr cptr_el2, x8`, which
# the upstream binary does not. Its encoding identifies a patched loader
# without needing the source tree.
PATCH_MARKER="6806a0d248111cd5"

loader_is_patched() {
    [ -f "$1" ] && xxd -p "$1" | tr -d '\n' | grep -q "$PATCH_MARKER"
}

describe_loader() {
    if [ ! -f "$1" ]; then
        echo "  $1: missing"
    elif loader_is_patched "$1"; then
        echo "  $1: patched for Apple Silicon (sha256 $(shasum -a 256 "$1" | cut -c1-16))"
    else
        echo "  $1: UPSTREAM, will not boot Apple Silicon (sha256 $(shasum -a 256 "$1" | cut -c1-16))"
    fi
}

if [ "${1:-}" = "--check" ]; then
    describe_loader "$INSTALLED"
    exit 0
fi

# Homebrew's LLVM provides llvm-objcopy, which Apple's clang does not ship and
# which the UEFI build needs to produce the PE image.
for candidate in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
    if [ -x "$candidate/llvm-objcopy" ]; then
        export PATH="$candidate:$PATH"
        break
    fi
done
if ! command -v llvm-objcopy >/dev/null 2>&1; then
    echo "error: llvm-objcopy not found; install it with: brew install llvm" >&2
    exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
    echo "==> Downloading Limine ${LIMINE_VERSION} source..."
    download_dir="$(mktemp -d)"
    curl -sL "https://github.com/limine-bootloader/limine/releases/download/v${LIMINE_VERSION}/limine-${LIMINE_VERSION}.tar.gz" \
        | tar xz -C "$download_dir"
    mkdir -p "$BOOT_DIR"
    mv "$download_dir/limine-${LIMINE_VERSION}" "$SRC_DIR"
    rm -rf "$download_dir"
fi

cd "$SRC_DIR"
for patch in "$PATCH_DIR"/${LIMINE_VERSION}-*.patch; do
    [ -f "$patch" ] || continue
    if patch -p1 -R --dry-run -s -f < "$patch" >/dev/null 2>&1; then
        echo "==> $(basename "$patch"): already applied"
    else
        echo "==> applying $(basename "$patch")"
        patch -p1 -N -s < "$patch"
    fi
done

# configure records its arguments in config.log; only re-run it when the
# tree was never configured for the LLVM toolchain.
if [ ! -f GNUmakefile ] || ! grep -q "ac_cv_env_TOOLCHAIN_FOR_TARGET_value=llvm" config.log 2>/dev/null; then
    echo "==> configuring (LLVM toolchain)"
    ./configure --enable-uefi-aarch64 --disable-uefi-cd --disable-bios \
        --disable-bios-cd --disable-bios-pxe TOOLCHAIN_FOR_TARGET=llvm \
        > /tmp/vinix-limine-configure.log 2>&1 \
        || { echo "error: configure failed, see /tmp/vinix-limine-configure.log" >&2; exit 1; }
fi

echo "==> building"
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" > /tmp/vinix-limine-make.log 2>&1 \
    || { echo "error: make failed, see /tmp/vinix-limine-make.log" >&2; exit 1; }

if ! loader_is_patched bin/BOOTAA64.EFI; then
    echo "error: built loader lacks the Apple Silicon patch marker" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
if [ -f "$INSTALLED" ] && ! loader_is_patched "$INSTALLED"; then
    cp "$INSTALLED" "$INSTALLED.upstream"
    echo "==> kept the upstream loader as $INSTALLED.upstream"
fi
cp bin/BOOTAA64.EFI "$INSTALLED"
echo "==> installed"
describe_loader "$INSTALLED"
