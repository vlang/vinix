#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only OR MIT
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
# Intentional word splitting allows standard space-separated CFLAGS.
# shellcheck disable=SC2086
"$cc" -std=c99 -Wall -Wextra -Werror -Wconversion -pedantic \
    ${CFLAGS:--O2} -I"$root/kernel/c" \
    "$root/kernel/c/apple_dcp_backlight.c" \
    "$root/tools/apple-backlight/test_backlight.c" -o "$work/test"
"$work/test"
