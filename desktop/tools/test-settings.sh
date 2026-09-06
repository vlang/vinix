#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
# Intentional word splitting permits standard CFLAGS such as sanitizers.
# shellcheck disable=SC2086
"$cc" -std=c99 -Wall -Wextra -Werror -Wconversion -pedantic ${CFLAGS:--O2} \
    -I"$root/desktop" -I"$root/kernel/c" \
    "$root/desktop/tools/tests/test_backlight_client.c" \
    "$root/kernel/c/apple_dcp_backlight.c" -o "$work/test-client"
"$work/test-client"

v=${V:-v}
if command -v "$v" >/dev/null 2>&1 && [ -f "$root/third_party/ui2/v.mod" ]; then
    mkdir "$work/ui"
    cp "$root/desktop/settings.v" "$root/desktop/backlight_client.h" \
        "$root/desktop/theme.v" "$root/desktop/tools/tests/settings_test.v" "$work/ui/"
    printf "Module { name: 'settings_tests' }\n" > "$work/ui/v.mod"
    "$v" -gc none -enable-globals -d ui2_headless \
        -path "@vlib|@vmodules|$root/third_party" test "$work/ui"
else
    echo 'SKIP: V Settings UI tests require V and third_party/ui2.'
    if [ "${REQUIRE_V_TESTS:-0}" = 1 ]; then exit 1; fi
fi
