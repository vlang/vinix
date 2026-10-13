#!/bin/sh
# Create a raw AArch64 UEFI boot image for QEMU running inside Vinix.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "$repo/build-support/run-v-tool.sh" "$repo/build-support/guest-disk.v" "$@"
