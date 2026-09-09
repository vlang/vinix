#!/bin/bash
# Build an Alpine x86_64 initramfs and boot it on Vinix under QEMU. The test
# succeeds only after unmodified, dynamically linked Alpine BusyBox binaries
# exercise exec, pipes, fork/wait, uname and ordinary shell execution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${VINIX_AMD64_QEMU_BUILD_DIR:-$SCRIPT_DIR/build-amd64-qemu}"
USERLAND_DIR="${VINIX_AMD64_USERLAND_BUILD_DIR:-$SCRIPT_DIR/build-amd64-userland}"
QEMU="${VINIX_QEMU_X86_64:-qemu-system-x86_64}"
TIMEOUT_SECONDS="${VINIX_QEMU_TIMEOUT:-120}"
LIMINE_COMMIT="ee5d29cd0a8034612dcd1df3f00052480db785c5"
LIMINE_SHA256="c1d6c34cf827e0c5cb0f3546d2db8568dd29aae26833a6332db5532b823503c3"
BOOT_IMAGE="$BUILD_DIR/boot.img"
SERIAL_LOG="$BUILD_DIR/serial.log"

for command_name in curl make mcopy mformat mmd qemu-img rsync "$QEMU"; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $command_name" >&2
        exit 1
    }
done

case "$BUILD_DIR" in
    ''|/|"$SCRIPT_DIR")
        echo "ERROR: refusing unsafe amd64 QEMU build directory: $BUILD_DIR" >&2
        exit 1
        ;;
esac

. "$SCRIPT_DIR/build-support/find-v.sh"

echo "==> Building the Alpine x86_64 initramfs..."
VINIX_AMD64_USERLAND_BUILD_DIR="$USERLAND_DIR" "$SCRIPT_DIR/build-userland-amd64.sh"

echo "==> Building the amd64 Vinix kernel..."
KERNEL_BUILD_DIR="$BUILD_DIR/kernel"
# Kernel builds use fixed bin/ and obj/ directories. Build from a snapshot so
# an ARM build in the source tree cannot replace these objects mid-test.
mkdir -p "$KERNEL_BUILD_DIR"
rsync -a --delete --delete-excluded \
    --exclude '/bin/' \
    --exclude '/obj/' \
    --exclude '/cc-runtime-x86_64/' \
    --exclude '/cc-runtime-aarch64/' \
    "$SCRIPT_DIR/kernel/" "$KERNEL_BUILD_DIR/"

KERNEL_MAKE=(make -C "$KERNEL_BUILD_DIR" ARCH=x86_64 V="$V")
if [ "$(uname -s)" = Darwin ]; then
    LD_X86_64="${VINIX_LD_X86_64:-$(command -v ld.lld || true)}"
    if [ -z "$LD_X86_64" ]; then
        echo "ERROR: ld.lld is required to cross-link the amd64 kernel on macOS." >&2
        exit 1
    fi
    KERNEL_MAKE+=(CC=clang "LD_X86_64=$LD_X86_64")
fi
"${KERNEL_MAKE[@]}" clean
"${KERNEL_MAKE[@]}" -j1

mkdir -p "$BUILD_DIR"
BOOTX64="$BUILD_DIR/BOOTX64.EFI"
if [ ! -f "$BOOTX64" ]; then
    echo "==> Fetching the pinned Limine UEFI loader..."
    curl -fL "https://raw.githubusercontent.com/limine-bootloader/limine/$LIMINE_COMMIT/BOOTX64.EFI" \
        -o "$BOOTX64"
fi
if command -v sha256sum >/dev/null 2>&1; then
    LIMINE_ACTUAL_SHA256="$(sha256sum "$BOOTX64" | awk '{print $1}')"
else
    LIMINE_ACTUAL_SHA256="$(shasum -a 256 "$BOOTX64" | awk '{print $1}')"
fi
if [ "$LIMINE_ACTUAL_SHA256" != "$LIMINE_SHA256" ]; then
    echo "ERROR: Limine UEFI loader checksum mismatch." >&2
    exit 1
fi

QEMU_BIN="$(command -v "$QEMU")"
if [ -n "${VINIX_OVMF_CODE:-}" ]; then
    OVMF_CODE="$VINIX_OVMF_CODE"
else
    QEMU_PREFIX="$(cd "$(dirname "$QEMU_BIN")/.." && pwd)"
    OVMF_CODE=''
    for candidate in \
        "$QEMU_PREFIX/share/qemu/edk2-x86_64-code.fd" \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/edk2/x64/OVMF_CODE.fd; do
        if [ -f "$candidate" ]; then
            OVMF_CODE="$candidate"
            break
        fi
    done
fi
if [ -z "$OVMF_CODE" ] || [ ! -f "$OVMF_CODE" ]; then
    echo "ERROR: x86_64 UEFI firmware not found; set VINIX_OVMF_CODE." >&2
    exit 1
fi

echo "==> Creating the QEMU UEFI boot image..."
qemu-img create -q -f raw "$BOOT_IMAGE" 64M
mformat -i "$BOOT_IMAGE" -F ::
mmd -i "$BOOT_IMAGE" ::/EFI ::/EFI/BOOT ::/boot
mcopy -i "$BOOT_IMAGE" "$BOOTX64" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$BOOT_IMAGE" "$KERNEL_BUILD_DIR/bin/vinix" ::/boot/vinix
mcopy -i "$BOOT_IMAGE" "$USERLAND_DIR/initramfs.tar" ::/boot/initramfs.tar
mcopy -i "$BOOT_IMAGE" "$SCRIPT_DIR/build-support/limine.conf" ::/boot/limine.conf

: > "$SERIAL_LOG"
echo "==> Booting Alpine amd64 on Vinix in QEMU..."
"$QEMU_BIN" \
    -machine q35,smm=off \
    -accel "${VINIX_QEMU_ACCEL:-tcg}" \
    -cpu "${VINIX_QEMU_CPU:-max}" \
    -m "${VINIX_QEMU_MEM:-512}" \
    -smp 1 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -drive "if=virtio,format=raw,file=$BOOT_IMAGE" \
    -display none \
    -monitor none \
    -serial "file:$SERIAL_LOG" \
    -no-reboot \
    -no-shutdown &
QEMU_PID=$!
trap 'kill "$QEMU_PID" 2>/dev/null || true; wait "$QEMU_PID" 2>/dev/null || true' EXIT

deadline=$((SECONDS + TIMEOUT_SECONDS))
while kill -0 "$QEMU_PID" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do
    if grep -Fq 'Shell arithmetic: 46' "$SERIAL_LOG"; then
        break
    fi
    sleep 1
done

for expected in \
    'VINIX_AMD64_ALPINE_OK' \
    'Alpine busybox: BusyBox v' \
    'Machine: x86_64' \
    'Shell arithmetic: 46'; do
    if ! grep -Fq "$expected" "$SERIAL_LOG"; then
        echo "ERROR: QEMU did not produce the expected Alpine marker: $expected" >&2
        tail -n 120 "$SERIAL_LOG" >&2
        exit 1
    fi
done

echo "==> Alpine amd64 QEMU smoke test passed:"
grep -E '^(VINIX_AMD64_ALPINE_OK|Alpine busybox:|Machine:|Shell arithmetic:)' "$SERIAL_LOG"
