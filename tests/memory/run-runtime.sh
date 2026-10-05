#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
cc=${CC:-clang}
. "$repo/build-support/find-v.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-memory-runtime.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Generate C from the actual V implementation under private symbol names.
# Exclude builtin runtime code so the primitives cannot rely on allocations.
sed -e "s/export: 'memcpy'/export: 'vinix_memcpy'/" \
    -e "s/export: 'memset'/export: 'vinix_memset'/" \
    -e "s/export: 'memmove'/export: 'vinix_memmove'/" \
    -e "s/export: 'memcmp'/export: 'vinix_memcmp'/" \
    -e "s/export: 'atoi'/export: 'vinix_atoi'/" \
    "$repo/kernel/lib/stubs/memory.v" > "$work/memory.v"
V_C_ERROR_BUG_REPORT_DISABLED=1 "$V" -shared -no-builtin -os vinix \
    -target-libc-headers -nofloat -gc none -manualfree \
    -o "$work/memory.c" "$work/memory.v"

# Keep the kernel's general-register-only requirement on both architectures.
case $(uname -m) in
    arm64|aarch64) registers='-mgeneral-regs-only' ;;
    x86_64|amd64) registers='-mno-80387 -mno-mmx -mno-sse -mno-sse2 -mno-red-zone' ;;
    *) echo 'Unsupported host architecture for kernel memory runtime test' >&2; exit 1 ;;
esac
sanitizers=${VINIX_MEMORY_SANITIZERS:-address,undefined}
case $sanitizers in
    none) instrumentation= ;;
    *) instrumentation="-fsanitize=$sanitizers -fno-omit-frame-pointer" ;;
esac
# These variables intentionally hold compiler flag lists, never shell code.
# shellcheck disable=SC2086
"$cc" -std=gnu99 -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin \
    -Wno-unused-function \
    -fno-strict-aliasing $registers $instrumentation \
    -c "$work/memory.c" -o "$work/memory.o"
# shellcheck disable=SC2086
"$cc" -std=gnu99 -O2 -Wall -Wextra -Werror $instrumentation \
    "$repo/tests/memory/runtime.c" "$work/memory.o" -o "$work/runtime"
"$work/runtime"
