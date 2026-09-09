#!/bin/bash
# Build and boot the Vinix Hyprland desktop in QEMU.
#
# First build the Hyprland layer in the Debian ARM64 build VM with
# ./build-hyprland-aarch64.sh. All options are passed to run-desktop-aarch64.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HYPRLAND_STAGING="${VINIX_HYPRLAND_STAGING:-$SCRIPT_DIR/build-aarch64-hyprland/staging}"

if [ ! -x "$HYPRLAND_STAGING/usr/bin/start-hyprland-vinix" ] || \
   [ ! -f "$HYPRLAND_STAGING/usr/lib/libaquamarine.so.11" ]; then
    echo "ERROR: the Vinix Hyprland layer is not built at $HYPRLAND_STAGING" >&2
    echo "Run ./build-hyprland-aarch64.sh in the Debian ARM64 build VM first." >&2
    exit 1
fi

export VINIX_HYPRLAND_STAGING="$HYPRLAND_STAGING"
export VINIX_BOOT_HYPRLAND=1
exec "$SCRIPT_DIR/run-desktop-aarch64.sh" "$@"
