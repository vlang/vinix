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
ISO="${VINIX_AMD64_ISO:-$BUILD_DIR/vinix.iso}"
SERIAL_LOG="$BUILD_DIR/serial.log"
BUILD=1
INTERACTIVE=0

for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        --interactive) INTERACTIVE=1 ;;
        --help|-h)
            echo "usage: $0 [--no-build] [--interactive]"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

for command_name in "$QEMU"; do
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

if [ "$BUILD" -eq 1 ]; then
    VINIX_AMD64_BUILD_DIR="$BUILD_DIR/kernel" \
    VINIX_AMD64_USERLAND_BUILD_DIR="$USERLAND_DIR" \
    VINIX_AMD64_ISO="$ISO" \
        "$SCRIPT_DIR/build-amd64.sh"
elif [ ! -f "$ISO" ]; then
    echo "ERROR: $ISO not found; omit --no-build to create it." >&2
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

if [ "$INTERACTIVE" -eq 1 ]; then
    echo "==> Starting Alpine amd64 on Vinix (Ctrl-A X to quit)..."
    exec "$QEMU_BIN" \
        -machine q35,smm=off \
        -accel "${VINIX_QEMU_ACCEL:-tcg}" \
        -cpu "${VINIX_QEMU_CPU:-max}" \
        -m "${VINIX_QEMU_MEM:-8192}" \
        -smp "${VINIX_QEMU_SMP:-4}" \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
        -cdrom "$ISO" \
        -vga std \
        -serial stdio
fi

mkdir -p "$BUILD_DIR"
: > "$SERIAL_LOG"
echo "==> Booting Alpine amd64 on Vinix in QEMU..."
"$QEMU_BIN" \
    -machine q35,smm=off \
    -accel "${VINIX_QEMU_ACCEL:-tcg}" \
    -cpu "${VINIX_QEMU_CPU:-max}" \
    -m "${VINIX_QEMU_MEM:-512}" \
    -smp 1 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -cdrom "$ISO" \
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
