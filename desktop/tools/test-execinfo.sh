#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
cc=${CC:-cc}
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-execinfo.XXXXXX")

cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT INT TERM

defines=
if [ "$(uname -s)" = Darwin ]; then
    defines='-d execinfo_darwin'
fi
python3 "$root/build-support/compile-v-module.py" \
    "$root/desktop/execinfocore" "$work/execinfo.c" $defines \
    --header "$work/execinfo_compat.h"
python3 "$root/build-support/compile-v-module.py" \
    "$root/desktop/tools/tests/execinfofixture" "$work/test.c"
"$cc" -std=c11 -g -O2 -fno-omit-frame-pointer -funwind-tables \
	-D_GNU_SOURCE \
	-Wall -Wextra -Werror -Wno-unused-function -Wno-unused-label \
	-Wno-unused-parameter -I"$work" ${CFLAGS:-} \
	"$work/execinfo.c" "$work/test.c" \
	${LDFLAGS:-} \
	-o "$work/execinfo-test"
"$work/execinfo-test"
