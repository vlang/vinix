#!/bin/bash
# Compatibility entry point for the former native-VM userland build.
#
# The regular builder is host-independent now that the base filesystem and
# toolchain are prebuilt Alpine packages, so there is no separate VM build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${VINIX_ARM64_RUNTIME_BUILD_DIR:-}" ] &&
   [ -z "${VINIX_AARCH64_USERLAND_BUILD_DIR:-}" ]; then
    export VINIX_AARCH64_USERLAND_BUILD_DIR="$VINIX_ARM64_RUNTIME_BUILD_DIR"
fi
if [ -n "${VINIX_ARM64_INITRAMFS:-}" ] &&
   [ -z "${VINIX_AARCH64_INITRAMFS:-}" ]; then
    export VINIX_AARCH64_INITRAMFS="$VINIX_ARM64_INITRAMFS"
fi

echo "build-userland-aarch64-vm.sh: using the Alpine package builder"
exec "$SCRIPT_DIR/build-userland-aarch64.sh" "$@"
