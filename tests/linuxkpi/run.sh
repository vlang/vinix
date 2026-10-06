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
    -fwrapv -fno-strict-aliasing -DVINIX_V_RUNTIME -DVINIX_LINUXKPI_HOST_TEST -I"$repo/kernel/c" \
    -c "$work/compat.c" -o "$work/compat.o"
python3 - "$work/compat.o" <<'CHECK'
import re, subprocess, sys
symbols = subprocess.check_output(["nm", "-u", sys.argv[1]], text=True)
assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
print("LinuxKPI: V core has no implicit allocator imports")
CHECK
case $(uname -m) in
    arm64|aarch64) native_asm=aarch64; native_v_arch=arm64 ;;
    x86_64|amd64) native_asm=x86_64; native_v_arch=amd64 ;;
    *) printf '%s\n' 'Unsupported LinuxKPI host assembly architecture' >&2; exit 1 ;;
esac
${CC:-clang} -DVINIX_LINUXKPI -I"$repo/kernel/asm/$native_asm" \
    -Dsnprintf=vinix_linuxkpi_format_test_snprintf \
    -Dscnprintf=vinix_linuxkpi_format_test_scnprintf \
    -Dsprintf=vinix_linuxkpi_format_test_sprintf \
    -c "$repo/kernel/asm/$native_asm/linuxkpi_varargs.S" -o "$work/varargs.o"
${CC:-clang} -DVINIX_LINUXKPI -I"$repo/kernel/asm/$native_asm" \
    -c "$repo/kernel/asm/$native_asm/linuxkpi_workqueue_abi.S" -o "$work/workqueue_abi.o"
${CC:-clang} -DVINIX_LINUXKPI -c "$repo/kernel/asm/$native_asm/linuxkpi_storage.S" -o "$work/storage.o"
python3 "$repo/tests/linuxkpi/compile-v-primitives.py" --host --arch "$native_v_arch" "$work/headercore.c"
# Keep upstream header algorithms in their native, separately compiled V object.
# Darwin's fortified macros are incompatible with Linux's string declarations;
# ASan/UBSan still cover every call and data access in this object.
${CC:-clang} -std=gnu11 -O1 -g -ffreestanding -fno-builtin -fwrapv -fno-strict-aliasing \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function -D_FORTIFY_SOURCE=0 -D__sputc=vkh_header_sputc \
    -fsanitize=address,undefined -fno-omit-frame-pointer -pthread \
    -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -D__KERNEL__ \
    -include "$repo/tests/linuxkpi/host_types.h" -include linux/kconfig.h -include "$source_dir/include/linux/compiler_types.h" \
    -iquote "$repo/kernel/c" -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
    -I"$source_dir/arch/x86/include" -I"$source_dir/arch/x86/include/uapi" \
    -c "$work/headercore.c" -o "$work/headercore.o"
python3 - "$work/headercore.o" <<'CHECK'
import re, subprocess, sys
symbols = subprocess.check_output(["nm", "-u", sys.argv[1]], text=True)
assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
print("LinuxKPI: native V header primitives have no implicit allocator imports")
CHECK
# Compile every independent fixture with native header layouts and sanitizers.
# GNU inline semantics keep Darwin libc's external inlines in libc when several
# separately generated V objects include its headers. Native builds use the
# kernel's unchanged GNU11/general-register flags.
for fixture_module in runtimefixture cachefixture pciconfigfixture i915policyfixture \
    taskfixture timefixture timerfixture syncfixture wwfixture iofixture seqfixture; do
    python3 "$repo/tests/linuxkpi/compile-v-fixture.py" "$fixture_module" \
        --host --arch "$native_v_arch" "$work/$fixture_module.c"
    ${CC:-clang} -std=gnu11 -fgnu89-inline -O1 -g -ffreestanding -fno-builtin -fwrapv -fno-strict-aliasing \
        -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function -Wno-deprecated-declarations \
        -D_FORTIFY_SOURCE=0 -D__sputc=vkf_${fixture_module}_sputc \
        -fsanitize=address,undefined -fno-omit-frame-pointer -pthread \
        -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -DVINIX_LINUXKPI_FORMAT_HOST_TEST -D__KERNEL__ \
        -include "$repo/tests/linuxkpi/host_types.h" -include linux/kconfig.h -include "$source_dir/include/linux/compiler_types.h" \
        -iquote "$repo/kernel/c" -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
        -I"$source_dir/arch/x86/include" -I"$source_dir/arch/x86/include/uapi" -I"$source_dir/drivers/gpu/drm/i915" \
        -c "$work/$fixture_module.c" -o "$work/$fixture_module.o"
    python3 - "$work/$fixture_module.o" <<'CHECK'
import re, subprocess, sys
symbols = subprocess.check_output(["nm", "-u", sys.argv[1]], text=True)
assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b", symbols), symbols
CHECK
done
printf '%s\n' 'LinuxKPI: independent V fixtures have no implicit allocator imports'
${CC:-clang} -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST \
    -c "$repo/kernel/asm/x86_64/linuxkpi_fixture_abi.S" -o "$work/fixture_storage.o"
python3 "$repo/tests/linuxkpi/fixture-goldens.py"
# Execute the native policy fixture too: compiling alone misses C macro
# expression signedness, since a foreign declaration cannot coerce macro args.
python3 "$repo/build-support/compile-v-module.py" "$repo/tests/linuxkpi/policyhost" \
    "$work/policyhost.c" --arch "$native_v_arch" -d nofloat
${CC:-clang} -std=gnu11 -O1 -g -ffreestanding -fno-builtin \
    -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-parameter \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    -c "$work/policyhost.c" -o "$work/policyhost.o"
# Link production implementations/bindings and the independent fixtures.
# Independent guest *_test.c fixtures are built only by the kernel.
set --
for source in "$repo"/kernel/c/linuxkpi*.c; do
    case "$source" in
        *_native_test.c) ;;
        *_test.c) continue ;;
    esac
    set -- "$@" "$source"
done
# Upstream Linux enables -Wall/-Wextra but disables unused-parameter warnings.
${CC:-clang} -std=gnu11 -O1 -g -fwrapv -fno-strict-aliasing -Wall -Wextra -Werror -Wno-unused-parameter \
    -fsanitize=address,undefined -fno-omit-frame-pointer -pthread \
    -DVINIX_LINUXKPI -DVINIX_LINUXKPI_HOST_TEST -DVINIX_LINUXKPI_FORMAT_HOST_TEST -D__KERNEL__ -Dmain=vinix_linuxkpi_host_original_main \
    -include "$repo/tests/linuxkpi/host_types.h" -include linux/kconfig.h -include "$source_dir/include/linux/compiler_types.h" \
    -I"$source_dir/drivers/gpu/drm/i915" -I"$repo/kernel/linuxkpi/include" -I"$source_dir/include" -I"$source_dir/include/uapi" \
    -I"$source_dir/arch/x86/include" -I"$source_dir/arch/x86/include/uapi" \
    "$work/policyhost.o" "$work/i915policyfixture.o" "$work/runtimefixture.o" "$work/syncfixture.o" "$work/fixture_storage.o" "$work/compat.o" "$work/headercore.o" "$work/varargs.o" "$work/storage.o" "$work/workqueue_abi.o" "$@" "$repo/tests/linuxkpi/test.c" \
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
