#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Host tests for the M1 Air speaker driver (kernel/c/apple_speakers.c).
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/vinix-apple-speakers.XXXXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
cc=${CC:-cc}
# SANITIZE=0 supports a host compiler without sanitizer runtimes.
sanitizers=
if [ "${SANITIZE:-1}" = 1 ]; then
    sanitizers='-fsanitize=address,undefined -fno-omit-frame-pointer'
fi
# CFLAGS and sanitizers intentionally undergo shell word splitting.
# shellcheck disable=SC2086
"$cc" -std=gnu11 -O1 -g -Wall -Wextra -Werror ${CFLAGS:-} $sanitizers \
    "$root/tests/apple-speakers/test.c" -o "$build/test" -lm
"$build/test"
