#!/bin/bash
# Build the Limine aarch64 UEFI loader used by both run-aarch64.sh and
# deploy-m1-efi.sh.
#
# Limine 12.x has an upstream VHE-aware EL2 hand-off for Apple Silicon, so it
# no longer needs Vinix's old 9.3.0 hand-off patch. Vinix still uses protocol
# base revision 2, however, so the local patch retains that compatibility while
# the kernel is migrated to revision 6 separately.
#
# Usage: ./build-limine-aarch64.sh            build and install
#        ./build-limine-aarch64.sh --check    report which loader is installed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIMINE_VERSION="12.8.0"
LIMINE_SHA256="6fe2209457cb342ccf102d270ba953153138a191546c7801ed8ee9a6b2dcee4b"
BOOT_DIR="$SCRIPT_DIR/boot-image"
SRC_DIR="$BOOT_DIR/limine-src-${LIMINE_VERSION}"
PATCH_DIR="$SCRIPT_DIR/build-support/limine"
INSTALL_DIR="$BOOT_DIR/limine-bin"
INSTALLED="$INSTALL_DIR/BOOTAA64.EFI"
EXPECTED_LOADER_LABEL="Limine ${LIMINE_VERSION} (aarch64, UEFI)"

loader_is_expected_version() {
    [ -f "$1" ] \
        && LC_ALL=C grep -aF "$EXPECTED_LOADER_LABEL" "$1" >/dev/null \
        && ! LC_ALL=C grep -aF \
            "Base revision %u is no longer supported for aarch64" "$1" >/dev/null
}

describe_loader() {
    if [ ! -f "$1" ]; then
        echo "  $1: missing"
    elif loader_is_expected_version "$1"; then
        echo "  $1: $EXPECTED_LOADER_LABEL with Vinix base revision 2 compatibility (sha256 $(shasum -a 256 "$1" | cut -c1-16))"
    else
        echo "  $1: unexpected Limine version (sha256 $(shasum -a 256 "$1" | cut -c1-16))"
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
    archive="$download_dir/limine-${LIMINE_VERSION}.tar.gz"
    curl -fsSL \
        "https://github.com/limine-bootloader/limine/releases/download/v${LIMINE_VERSION}/limine-${LIMINE_VERSION}.tar.gz" \
        -o "$archive"
    actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [ "$actual_sha256" != "$LIMINE_SHA256" ]; then
        echo "error: Limine source checksum mismatch" >&2
        echo "expected: $LIMINE_SHA256" >&2
        echo "actual:   $actual_sha256" >&2
        rm -rf "$download_dir"
        exit 1
    fi
    tar xzf "$archive" -C "$download_dir"
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

# Release sources default to Clang plus the llvm-* binutils. Only configure a
# newly extracted tree; the versioned directory prevents stale cross settings.
if [ ! -f GNUmakefile ]; then
    echo "==> configuring (LLVM toolchain)"
    ./configure --enable-uefi-aarch64 --disable-uefi-cd --disable-bios \
        --disable-bios-cd --disable-bios-pxe \
        > /tmp/vinix-limine-configure.log 2>&1 \
        || { echo "error: configure failed, see /tmp/vinix-limine-configure.log" >&2; exit 1; }
fi

echo "==> building"
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" > /tmp/vinix-limine-make.log 2>&1 \
    || { echo "error: make failed, see /tmp/vinix-limine-make.log" >&2; exit 1; }

if ! loader_is_expected_version bin/BOOTAA64.EFI; then
    echo "error: built loader does not identify itself as $EXPECTED_LOADER_LABEL" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
if [ -f "$INSTALLED" ] && ! cmp -s "$INSTALLED" bin/BOOTAA64.EFI; then
    cp "$INSTALLED" "$INSTALLED.previous"
    echo "==> kept the previous loader as $INSTALLED.previous"
fi
cp bin/BOOTAA64.EFI "$INSTALLED"
echo "==> installed"
describe_loader "$INSTALLED"
