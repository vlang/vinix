#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
sh "$repo/build-support/run-v-tool.sh" "$repo/tests/qemu-initramfs-split/test_split.v"
sh "$repo/build-support/run-v-tool.sh" "$repo/tests/storage/test_split_desktop_initramfs.v"
sh "$repo/build-support/run-v-tool.sh" "$repo/tests/qemu-module-iso/test_iso.v"
