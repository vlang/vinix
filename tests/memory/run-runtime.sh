#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
cc=${CC:-clang}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-memory-runtime.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Test the actual freestanding implementation under private symbol names.
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
    -fno-strict-aliasing $registers $instrumentation \
    -Dmemcpy=vinix_memcpy -Dmemset=vinix_memset -Dmemmove=vinix_memmove \
    -Dmemcmp=vinix_memcmp -Datoi=vinix_atoi \
    -c "$repo/kernel/c/memory.c" -o "$work/memory.o"
# shellcheck disable=SC2086
"$cc" -std=gnu99 -O2 -Wall -Wextra -Werror $instrumentation \
    "$repo/tests/memory/runtime.c" "$work/memory.o" -o "$work/runtime"
"$work/runtime"
