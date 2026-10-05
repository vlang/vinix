#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output=$(mktemp "${TMPDIR:-/tmp}/vinix-hypervisor-abi.XXXXXX")
trap 'rm -f "$output"' EXIT INT TERM

${CC:-cc} -std=c11 -Wall -Wextra -Werror \
    -I"$repo/base-files/usr/include" \
    "$repo/tests/hypervisor/abi_test.c" -o "$output"
"$output"
