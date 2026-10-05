#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Test the shared production implementation, including keyboard regressions.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-apple-spi.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
set -- -std=c11 -Wall -Wextra -Werror -g -fno-omit-frame-pointer
case ${SANITIZE:-0} in
    0) set -- "$@" -O2 ;;
    1) set -- "$@" -O1 -fsanitize=address,undefined -fno-sanitize-recover=all ;;
    *) echo 'SANITIZE must be 0 or 1' >&2; exit 2 ;;
esac
for suite in apple-spi-keyboard apple-spi-touchpad; do
    echo "==> $suite ($cc, SANITIZE=${SANITIZE:-0})"
    "$cc" "$@" "$root/tests/$suite/test.c" -o "$work/$suite"
    "$work/$suite"
done
