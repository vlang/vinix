#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

cc=${CC:-cc}
flags='-std=c11 -O2 -g -Wall -Wextra -Werror'
if [ "${SANITIZE:-0}" = 1 ]; then
    flags="$flags -O1 -fno-omit-frame-pointer -fsanitize=address,undefined"
fi

# Intentional word splitting for compiler flags.
# shellcheck disable=SC2086
"$cc" $flags \
    "$repo/tests/agx-fake-g17/test.c" \
    "$repo/kernel/c/agx_fake_g17.c" \
    -o "$work/test"
"$work/test"

# Exercise the generated recovered-ABI encoder against the exact verifier.
# Intentional word splitting for compiler flags.
# shellcheck disable=SC2086
"$cc" $flags \
    "$repo/tests/agx-fake-g17/test_encode.c" \
    "$repo/kernel/c/agx_fake_g17_encode.c" \
    "$repo/kernel/c/agx_fake_g17.c" \
    -o "$work/test-encode"
"$work/test-encode"
