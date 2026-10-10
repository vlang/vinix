#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
sh "$repo/build-support/run-v-tool.sh" "$repo/tests/storage/test_split_desktop_initramfs.v"
"$repo/tests/storage/test-qemu-storage.sh"
