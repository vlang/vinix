#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
# shellcheck disable=SC2086
"$cc" -std=c99 -Wall -Wextra -Werror -Wconversion -pedantic ${CFLAGS:--O2} \
    -I"$root/desktop" -I"$root/kernel/c" \
    "$root/desktop/tools/tests/test_battery_client.c" \
    "$root/kernel/c/apple_smc.c" -o "$work/test-battery"
"$work/test-battery"
