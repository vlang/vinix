#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
cc=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-execinfo.XXXXXX")

cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

"$cc" -std=c11 -g -O2 -fno-omit-frame-pointer -funwind-tables \
	-Wall -Wextra -Werror -I"$root/desktop" \
	"$root/desktop/execinfo_compat.c" \
	"$root/desktop/tools/tests/execinfo_compat_test.c" \
	-o "$work/execinfo-test"
"$work/execinfo-test"
