#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec sh "$repo/build-support/run-v-tool.sh" "$repo/tests/qemu-initramfs-split/test_split.v" "$@"
