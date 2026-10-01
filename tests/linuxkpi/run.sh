#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_dir=${LINUXKPI_SOURCE_DIR:-"$repo/third_party/linux-i915/linux-6.6.157"}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-linuxkpi-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
python3 -B "$repo/kernel/linuxkpi/upstream.py" verify --base "$(dirname "$source_dir")"
# Upstream Linux enables -Wall/-Wextra but disables unused-parameter warnings.
${CC:-clang} -std=gnu11 -O1 -g -fwrapv -Wall -Wextra -Werror -Wno-unused-parameter \
    -fsanitize=address,undefined -fno-omit-frame-pointer -pthread \
    -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -D__KERNEL__ -include linux/kconfig.h \
    -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
    "$repo/kernel/c/linuxkpi.c" "$repo/kernel/c/linuxkpi_refcount.c" "$repo/kernel/c/linuxkpi_string.c" "$repo/tests/linuxkpi/test.c" \
    "$source_dir/lib/list_sort.c" "$source_dir/lib/sort.c" "$source_dir/lib/rbtree.c" \
    "$source_dir/lib/find_bit.c" "$source_dir/lib/hweight.c" \
    -o "$work/test"
"$work/test"
python3 -B "$repo/tests/linuxkpi/upstream_test.py"
