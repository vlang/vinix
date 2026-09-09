#!/bin/bash
# Build and boot the amd64 Vinix desktop in QEMU.
#
# Usage: ./run-desktop-amd64.sh [options]
#
#   --no-build      boot the existing vinix-desktop-amd64.iso
#   --monitor       expose QEMU monitor and QMP Unix sockets
#   --mem=MB        guest RAM (default: 8192)
#   --help
#
# Remaining arguments are passed directly to qemu-system-x86_64.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO="${VINIX_AMD64_DESKTOP_ISO:-$SCRIPT_DIR/vinix-desktop-amd64.iso}"
QEMU="${VINIX_QEMU_X86_64:-qemu-system-x86_64}"
MEMORY="${VINIX_QEMU_MEM:-8192}"
MONITOR_SOCKET="${VINIX_MONITOR_SOCKET:-/tmp/vinix-amd64-monitor}"
QMP_SOCKET="${VINIX_QMP_SOCKET:-/tmp/vinix-amd64-qmp}"
BUILD=1
WITH_MONITOR=0
PASSTHROUGH=()

for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        --monitor) WITH_MONITOR=1 ;;
        --mem=*) MEMORY="${arg#*=}" ;;
        --help|-h)
            sed -n '2,/^set -/s/^# \{0,1\}//p' "$0"
            exit 0
            ;;
        *) PASSTHROUGH+=("$arg") ;;
    esac
done

if [ "$BUILD" -eq 1 ]; then
    "$SCRIPT_DIR/build-desktop-amd64.sh"
fi
if [ ! -f "$ISO" ]; then
    echo "ERROR: $ISO not found; build it with ./build-desktop-amd64.sh" >&2
    exit 1
fi
command -v "$QEMU" >/dev/null 2>&1 || {
    echo "ERROR: qemu-system-x86_64 is required." >&2
    exit 1
}

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

QEMU_OPTIONS=(-M q35,smm=off -m "$MEMORY" -smp 4 -vga std \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
    -cdrom "$ISO" -serial stdio)
if [ -n "${VINIX_QEMU_ACCEL:-}" ]; then
    QEMU_OPTIONS+=(-accel "$VINIX_QEMU_ACCEL")
elif [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    QEMU_OPTIONS+=(-enable-kvm -cpu host)
elif [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = x86_64 ]; then
    QEMU_OPTIONS+=(-accel hvf -cpu host)
else
    QEMU_OPTIONS+=(-accel tcg -cpu max)
fi

if [ "$WITH_MONITOR" -eq 1 ]; then
    rm -f "$MONITOR_SOCKET" "$QMP_SOCKET"
    QEMU_OPTIONS+=(-monitor "unix:${MONITOR_SOCKET},server,nowait")
    QEMU_OPTIONS+=(-qmp "unix:${QMP_SOCKET},server,nowait")
    echo "==> Monitor: $MONITOR_SOCKET   QMP: $QMP_SOCKET"
fi

echo "==> Starting the amd64 desktop (Ctrl-A X to quit)..."
exec "$QEMU_BIN" "${QEMU_OPTIONS[@]}" "${PASSTHROUGH[@]}"
