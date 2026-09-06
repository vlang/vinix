#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT HUP INT TERM
cc=${CC:-cc}
"$cc" -std=gnu99 -O2 -Wall -Wextra -Werror -I"$root/kernel/c" \
    "$root/kernel/c/apple_smc.c" "$root/tests/apple_smc/test_smc.c" -o "$build/test"
"$build/test"
if [ "${SANITIZE:-0}" = 1 ]; then
    "$cc" -std=gnu99 -O1 -g -Wall -Wextra -Werror \
        -fsanitize=address,undefined -fno-omit-frame-pointer -I"$root/kernel/c" \
        "$root/kernel/c/apple_smc.c" "$root/tests/apple_smc/test_smc.c" -o "$build/sanitized"
    "$build/sanitized"
fi
if command -v clang >/dev/null 2>&1; then
    clang --target=aarch64-none-elf -std=gnu99 -O2 -Wall -Wextra -Werror \
        -ffreestanding -fno-stack-protector -mgeneral-regs-only -I"$root/kernel/c" \
        -c "$root/kernel/c/apple_smc.c" -o "$build/apple_smc.aarch64.o"
    printf '#include "apple_smc.h"\nuint64_t check_counter(void) { return vinix_smc_counter(); }\n' \
        > "$build/counter.c"
    clang --target=aarch64-none-elf -std=gnu99 -Wall -Wextra -Werror \
        -ffreestanding -mgeneral-regs-only -I"$root/kernel/c" \
        -c "$build/counter.c" -o "$build/counter.aarch64.o"
    echo 'PASS AArch64 freestanding core and counter compilation'
fi
