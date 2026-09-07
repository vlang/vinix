#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out="${TMPDIR:-/tmp}/vinix-apple-display-hotplug-test.$$"
trap 'rm -f "$out"' EXIT HUP INT TERM

cc -std=c11 -Wall -Wextra -Werror \
    "$repo/tests/apple_display_hotplug/test_hotplug.c" \
    "$repo/kernel/c/apple_display_hotplug.c" \
    -o "$out"
"$out"
