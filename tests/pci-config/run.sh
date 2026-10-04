#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-pci-config.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
for dialect in gnu99 gnu11; do
    "${CC:-clang}" -std="$dialect" -O1 -g -Wall -Wextra -Werror -pthread \
        -fsanitize=address,undefined -fno-omit-frame-pointer \
        -Dmalloc=vinix_pci_test_malloc -Dcalloc=vinix_pci_test_calloc \
        -Drealloc=vinix_pci_test_realloc -Dfree=vinix_pci_test_free \
        -c "$repo/kernel/c/pci_config.c" -o "$work/core-$dialect.o"
    "${CC:-clang}" -std="$dialect" -O1 -g -Wall -Wextra -Werror -pthread \
        -fsanitize=address,undefined -fno-omit-frame-pointer \
        "$repo/tests/pci-config/config_test.c" "$work/core-$dialect.o" -o "$work/test-$dialect"
    ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1}" \
    UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1}" "$work/test-$dialect"
done
