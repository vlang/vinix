#!/bin/sh
set -eu
cd "$(dirname "$0")"
CC=${CC:-cc}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
flags='-std=c11 -O2 -g -Wall -Wextra -Werror'
if [ "${SANITIZE:-0}" = 1 ]; then
    flags="$flags -O1 -fno-omit-frame-pointer -fsanitize=address,undefined"
fi
# Intentional word splitting for compiler flags.
# shellcheck disable=SC2086
"$CC" $flags test.c -o "$work/test"
"$work/test"
