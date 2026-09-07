#!/bin/sh
# Host tests must use libc's <...> headers, not the kernel's stubs.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
CC=${CC:-clang}
case ${SANITIZE:-1} in
    1) SAN_FLAGS='-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer' ;;
    0) SAN_FLAGS='-O2' ;;
    *) echo 'SANITIZE must be 0 or 1' >&2; exit 2 ;;
esac
# Intentional word splitting: SAN_FLAGS is selected above, not arbitrary input.
for source in test platform_test; do
    "$CC" -D_POSIX_C_SOURCE=200809L -std=c99 -Wall -Wextra -Werror $SAN_FLAGS \
        -iquote "$ROOT/kernel/c" "$ROOT/tests/m1-wifi/$source.c" \
        "$ROOT/kernel/c/brcm_wifi.c" -o "$TMP/$source"
    "$TMP/$source"
done
