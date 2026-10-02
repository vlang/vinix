#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_dir=${LINUXKPI_SOURCE_DIR:-"$repo/third_party/linux-i915/linux-6.6.157"}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-linuxkpi-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
python3 -B "$repo/kernel/linuxkpi/upstream.py" verify --base "$(dirname "$source_dir")"
# Upstream Linux enables -Wall/-Wextra but disables unused-parameter warnings.
${CC:-clang} -std=gnu11 -O1 -g -fwrapv -fno-strict-aliasing -Wall -Wextra -Werror -Wno-unused-parameter \
    -fsanitize=address,undefined -fno-omit-frame-pointer -pthread \
    -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -D__KERNEL__ \
    -include "$repo/tests/linuxkpi/host_types.h" -include linux/kconfig.h \
    -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
    -I"$source_dir/arch/x86/include" -I"$source_dir/arch/x86/include/uapi" \
    "$repo/kernel/c/linuxkpi.c" "$repo/kernel/c/linuxkpi_refcount.c" "$repo/kernel/c/linuxkpi_string.c" \
    "$repo/kernel/c/linuxkpi_percpu.c" "$repo/kernel/c/linuxkpi_bitmap.c" "$repo/kernel/c/linuxkpi_task.c" \
    "$repo/kernel/c/linuxkpi_sync.c" "$repo/kernel/c/linuxkpi_time.c" \
    "$repo/kernel/c/linuxkpi_timer.c" "$repo/kernel/c/linuxkpi_workqueue.c" \
    "$repo/kernel/c/linuxkpi_srcu.c" "$repo/kernel/c/linuxkpi_ww_mutex.c" "$repo/kernel/c/linuxkpi_wait_bit.c" "$repo/kernel/c/linuxkpi_io.c" "$repo/kernel/c/linuxkpi_cache.c" "$repo/tests/linuxkpi/test.c" \
    "$source_dir/lib/list_sort.c" "$source_dir/lib/sort.c" "$source_dir/lib/rbtree.c" \
    "$source_dir/lib/find_bit.c" "$source_dir/lib/hweight.c" \
    -o "$work/test"
"$work/test"
# Each translation unit keeps its public Linux/DRM header first. Building
# separately catches missing transitive includes that the runtime test's
# broader include list would conceal.
for helper in helper_kernel helper_drm_color task_header_sched task_header_ww; do
    ${CC:-clang} -std=gnu11 -O1 -g -fwrapv -fno-strict-aliasing -Wall -Wextra -Werror -Wno-unused-parameter \
        -fsanitize=address,undefined -fno-omit-frame-pointer \
        -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -D__KERNEL__ \
        -include "$repo/tests/linuxkpi/host_types.h" -include linux/kconfig.h \
        -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
        -I"$source_dir/arch/x86/include" -I"$source_dir/arch/x86/include/uapi" \
        "$repo/tests/linuxkpi/${helper}_test.c" -o "$work/$helper"
    "$work/$helper"
done
printf '%s\n' 'LinuxKPI: upstream integer helpers and standalone DRM LUT tests passed'
python3 -B "$repo/tests/linuxkpi/upstream_test.py"
