#!/bin/bash
# Build AArch64 OVMF with a real 2048x1536 ramfb GOP mode for desktop QEMU.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EDK2_TAG="edk2-stable202511"
SOURCE_DIR="${VINIX_EDK2_SOURCE:-$SCRIPT_DIR/boot-image/edk2-$EDK2_TAG}"
FIRMWARE="$SCRIPT_DIR/boot-image/edk2-aarch64-code-2048x1536.fd"
PATCH="$SCRIPT_DIR/patches/edk2/qemu-ramfb-2048x1536.patch"

if [ ! -d "$SOURCE_DIR/.git" ]; then
    if [ -e "$SOURCE_DIR" ]; then
        echo "ERROR: $SOURCE_DIR exists but is not an edk2 checkout." >&2
        echo "Set VINIX_EDK2_SOURCE to a fresh location or remove it." >&2
        exit 1
    fi
    echo "==> Fetching edk2 $EDK2_TAG (including its required submodules)..."
    git clone --depth 1 --branch "$EDK2_TAG" --recurse-submodules \
        https://github.com/tianocore/edk2.git "$SOURCE_DIR"
fi

if git -C "$SOURCE_DIR" apply --check "$PATCH" 2>/dev/null; then
    git -C "$SOURCE_DIR" apply "$PATCH"
elif grep -q '2048, // HorizontalResolution' \
    "$SOURCE_DIR/OvmfPkg/QemuRamfbDxe/QemuRamfb.c"; then
    echo "==> The 2048x1536 ramfb patch is already applied."
else
    echo "ERROR: cannot apply $PATCH to $SOURCE_DIR" >&2
    exit 1
fi

if [ -d /opt/homebrew/opt/llvm/bin ]; then
    export CLANGDWARF_BIN=/opt/homebrew/opt/llvm/bin/
elif ! command -v clang >/dev/null || ! command -v llvm-ar >/dev/null; then
    echo "ERROR: LLVM is required (on macOS: brew install llvm)." >&2
    exit 1
fi

echo "==> Building edk2 BaseTools..."
make -C "$SOURCE_DIR/BaseTools" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

echo "==> Building the AArch64 2048x1536 ramfb driver..."
(
    cd "$SOURCE_DIR"
    # shellcheck disable=SC1091
    source edksetup.sh >/dev/null
    build -a AARCH64 -b RELEASE -t CLANGDWARF \
        -p ArmVirtPkg/ArmVirtQemu.dsc \
        -m OvmfPkg/QemuRamfbDxe/QemuRamfbDxe.inf \
        -n "$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
)

RAMFB_FFS="$SOURCE_DIR/Build/ArmVirtQemu-AArch64/RELEASE_CLANGDWARF/FV/Ffs/dce1b094-7dc6-45d0-9fdd-d7fc3cc3e4efQemuRamfbDxe/dce1b094-7dc6-45d0-9fdd-d7fc3cc3e4ef.ffs"
if [ ! -f "$RAMFB_FFS" ]; then
    echo "ERROR: edk2 build completed without $RAMFB_FFS" >&2
    exit 1
fi

STOCK_FIRMWARE=$(find /opt/homebrew -name 'edk2-aarch64-code.fd' 2>/dev/null | head -1)
if [ -z "$STOCK_FIRMWARE" ]; then
    echo "ERROR: QEMU's edk2-aarch64-code.fd was not found (brew install qemu)." >&2
    exit 1
fi

echo "==> Installing the driver into QEMU's AArch64 OVMF image..."
PATH="$SOURCE_DIR/BaseTools/Source/C/bin:$PATH" PYTHON_COMMAND=python3 \
    "$SOURCE_DIR/BaseTools/BinWrappers/PosixLike/FMMT" \
    -r "$STOCK_FIRMWARE" dce1b094-7dc6-45d0-9fdd-d7fc3cc3e4ef \
    "$RAMFB_FFS" "$FIRMWARE"
echo "==> Wrote $FIRMWARE"
