#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
python3 "$repo/tests/storage/test_split_desktop_initramfs.py"
"$repo/tests/storage/test-qemu-storage.sh"
