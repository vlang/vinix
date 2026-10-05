#!/bin/bash
# Build AArch64 OVMF with a real 2048x1536 ramfb GOP mode for desktop QEMU.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
    echo "==> Fetching edk2 $EDK2_TAG..."
    git clone --depth 1 --branch "$EDK2_TAG" \
        https://github.com/tianocore/edk2.git "$SOURCE_DIR"
fi

# EDK2 needs only its direct submodules; recursive updates fetch unused test
# dependencies. Update existing checkouts too, so an interrupted fetch recovers.
echo "==> Fetching edk2's required submodules..."
git -C "$SOURCE_DIR" submodule update --init --depth 1

# EDK2 uses CRLF line endings; the patch in this repository uses LF. Ignore
# that difference in context lines when checking and applying the patch.
if git -C "$SOURCE_DIR" apply --ignore-space-change --check "$PATCH" 2>/dev/null; then
    git -C "$SOURCE_DIR" apply --ignore-space-change "$PATCH"
elif git -C "$SOURCE_DIR" apply --ignore-space-change --reverse --check "$PATCH" 2>/dev/null; then
    echo "==> The 2048x1536 ramfb patch is already applied."
else
    echo "ERROR: cannot apply $PATCH to $SOURCE_DIR" >&2
    git -C "$SOURCE_DIR" apply --ignore-space-change --check "$PATCH" >&2 || true
    exit 1
fi

# Respect an explicit toolchain, otherwise use Homebrew's keg-only LLVM when
# available. Query its prefix instead of assuming LLVM's installation path.
if [ -z "${CLANGDWARF_BIN:-}" ] && command -v brew >/dev/null; then
    LLVM_PREFIX=$(brew --prefix llvm 2>/dev/null || true)
    if [ -n "$LLVM_PREFIX" ] && [ -x "$LLVM_PREFIX/bin/clang" ]; then
        CLANGDWARF_BIN="$LLVM_PREFIX/bin/"
    fi
fi
if [ -n "${CLANGDWARF_BIN:-}" ]; then
    export CLANGDWARF_BIN="${CLANGDWARF_BIN%/}/"
fi
for tool in clang llvm-ar llvm-objcopy; do
    if ! command -v "${CLANGDWARF_BIN:-}$tool" >/dev/null; then
        echo "ERROR: EDK2 requires ${CLANGDWARF_BIN:-}$tool (on macOS: brew install llvm lld)." >&2
        exit 1
    fi
done

# RELEASE_CLANGDWARF links AArch64 ELF with -fuse-ld=lld. Homebrew ships
# LLD separately from LLVM; it may also be installed without being on PATH.
CLANG_DIR=$(dirname "$(command -v "${CLANGDWARF_BIN:-}clang")")
if [ -x "$CLANG_DIR/ld.lld" ]; then
    # Clang resolves symlinks before searching beside itself, so expose this
    # directory on PATH too when the selected clang is a symlink.
    export PATH="$CLANG_DIR:$PATH"
elif ! command -v ld.lld >/dev/null; then
    LLD_PREFIX=""
    if command -v brew >/dev/null; then
        LLD_PREFIX=$(brew --prefix lld 2>/dev/null || true)
    fi
    if [ -n "$LLD_PREFIX" ] && [ -x "$LLD_PREFIX/bin/ld.lld" ]; then
        export PATH="$LLD_PREFIX/bin:$PATH"
    else
        echo "ERROR: EDK2 requires the LLVM linker ld.lld (on macOS: brew install llvm lld)." >&2
        echo "Put ld.lld on PATH, or install it beside the selected clang." >&2
        exit 1
    fi
fi

echo "==> Building edk2 BaseTools..."
make -C "$SOURCE_DIR/BaseTools" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

echo "==> Building the AArch64 2048x1536 ramfb driver..."
(
    cd "$SOURCE_DIR"
    # EDK2's setup probes optional variables that are unset on a fresh shell.
    set +u
    # shellcheck disable=SC1091
    source edksetup.sh >/dev/null
    set -u
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
(
    cd "$SOURCE_DIR"
    PATH="$SOURCE_DIR/BaseTools/Source/C/bin:$PATH" PYTHON_COMMAND=python3 \
        "$SOURCE_DIR/BaseTools/BinWrappers/PosixLike/FMMT" \
        -r "$STOCK_FIRMWARE" dce1b094-7dc6-45d0-9fdd-d7fc3cc3e4ef \
        "$RAMFB_FFS" "$FIRMWARE"
)
echo "==> Wrote $FIRMWARE"
