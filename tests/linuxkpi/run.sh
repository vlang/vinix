#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_dir=${LINUXKPI_SOURCE_DIR:-"$repo/third_party/linux-i915/linux-6.6.157"}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-linuxkpi-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
python3 -B "$repo/kernel/linuxkpi/upstream.py" verify --base "$(dirname "$source_dir")"
"$repo/tests/pci-config/run.sh"
python3 "$repo/tests/linuxkpi/compile-v-core.py" "$work/compat.c"
${CC:-clang} -std=gnu11 -O2 -g -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-parameter \
    -fsanitize=address,undefined -fno-omit-frame-pointer -ffreestanding -fno-builtin \
    -fwrapv -fno-strict-aliasing -DVINIX_V_RUNTIME -I"$repo/kernel/c" \
    -c "$work/compat.c" -o "$work/compat.o"
python3 - "$work/compat.o" <<'CHECK'
import re, subprocess, sys
symbols = subprocess.check_output(["nm", "-u", sys.argv[1]], text=True)
assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
print("LinuxKPI: V core has no implicit allocator imports")
CHECK
# Upstream Linux enables -Wall/-Wextra but disables unused-parameter warnings.
${CC:-clang} -std=gnu11 -O1 -g -fwrapv -fno-strict-aliasing -Wall -Wextra -Werror -Wno-unused-parameter \
    -fsanitize=address,undefined -fno-omit-frame-pointer -pthread \
    -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -DVINIX_LINUXKPI_FORMAT_HOST_TEST -D__KERNEL__ \
    -include "$repo/tests/linuxkpi/host_types.h" -include linux/kconfig.h -include "$source_dir/include/linux/compiler_types.h" \
    -I"$source_dir/drivers/gpu/drm/i915" -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
    -I"$source_dir/arch/x86/include" -I"$source_dir/arch/x86/include/uapi" \
    "$work/compat.o" "$repo/kernel/c/linuxkpi_v_primitives.c" "$repo/kernel/c/linuxkpi.c" \
    "$repo/kernel/c/linuxkpi_task.c" \
    "$repo/kernel/c/linuxkpi_sync.c" "$repo/kernel/c/linuxkpi_time.c" \
    "$repo/kernel/c/linuxkpi_timer.c" "$repo/kernel/c/linuxkpi_workqueue.c" \
    "$repo/kernel/c/linuxkpi_srcu.c" "$repo/kernel/c/linuxkpi_ww_mutex.c" "$repo/kernel/c/linuxkpi_wait_bit.c" "$repo/kernel/c/linuxkpi_format.c" \
    "$repo/kernel/c/linuxkpi_printk.c" "$repo/tests/linuxkpi/test.c" \
    "$source_dir/lib/list_sort.c" "$source_dir/lib/sort.c" "$source_dir/lib/rbtree.c" \
    "$source_dir/lib/find_bit.c" "$source_dir/lib/hweight.c" "$source_dir/lib/ctype.c" "$source_dir/lib/siphash.c" \
    "$source_dir/drivers/gpu/drm/i915/i915_config.c" \
    "$source_dir/drivers/gpu/drm/i915/display/intel_qp_tables.c" \
    -include linux/export.h \
    -o "$work/test"
"$work/test"
python3 - "$work/test" <<'PY'
import resource
import signal
import subprocess
import sys

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
for case in ("reversed", "huge", "clock-horizon", "absolute-overflow", "state", "atomic", "valid-horizon"):
    result = subprocess.run([sys.argv[1], case], capture_output=True, text=True, timeout=30)
    expected = 0 if case == "valid-horizon" else -signal.SIGABRT
    assert result.returncode == expected, (case, result.returncode, result.stderr)
    if expected:
        assert "usleep boundary BUG with no published records or pages" in result.stderr, (case, result.stderr)
print("LinuxKPI: invalid sleep ranges, contexts and signed clock boundaries passed")
PY
# Each translation unit keeps its public Linux/DRM header first. Building
# separately catches missing transitive includes that the runtime test's
# broader include list would conceal.
for helper in helper_kernel helper_drm_color task_header_sched task_header_ww compiler_header spinlock_header preempt_header; do
    ${CC:-clang} -std=gnu11 -O1 -g -fwrapv -fno-strict-aliasing -Wall -Wextra -Werror -Wno-unused-parameter \
        -fsanitize=address,undefined -fno-omit-frame-pointer \
        -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -D__KERNEL__ \
        -include "$repo/tests/linuxkpi/host_types.h" -include linux/kconfig.h -include "$source_dir/include/linux/compiler_types.h" \
        -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
        -I"$source_dir/arch/x86/include" -I"$source_dir/arch/x86/include/uapi" \
        "$repo/tests/linuxkpi/${helper}_test.c" -o "$work/$helper"
    "$work/$helper"
done
printf '%s\n' 'LinuxKPI: upstream helpers and standalone Linux/DRM header tests passed'
python3 -B "$repo/tests/linuxkpi/upstream_test.py"
