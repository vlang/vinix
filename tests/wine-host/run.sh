#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
headers=${VINIX_X11_HEADERS:-}
if [ -z "$headers" ]; then
    for candidate in "$root/build-aarch64-x11/sysroot/usr/include" "$root/build-amd64-x11/sysroot/usr/include" /opt/X11/include /usr/include; do
        if [ -f "$candidate/X11/extensions/XTest.h" ] && [ -f "$candidate/X11/extensions/Xdamage.h" ]; then
            headers=$candidate
            break
        fi
    done
fi
[ -n "$headers" ] || { echo 'Wine host: X11/XTest/Xdamage headers required' >&2; exit 1; }
mkdir "$work/include"
ln -s "$headers/X11" "$work/include/X11"
python3 "$root/build-support/xorg-server/compile-v-host.py" winehost "$work/core.c"
link_flags='-Wl,--gc-sections'
if [ "$(uname -s)" = Darwin ]; then
    link_flags='-Wl,-undefined,dynamic_lookup'
fi
${CC:-clang} -std=gnu11 -O2 -g -Wall -Wextra -Werror -Wno-unused-function \
    -Wno-unused-parameter -Wno-unused-label -fsanitize=address,undefined \
    -fno-omit-frame-pointer -ffunction-sections -fdata-sections \
    -I"$work/include" -I"$root/build-support/xorg-server" \
    -DVINIX_WINE_HOST_NO_MAIN "$work/core.c" \
    "$root/build-support/xorg-server/wine-host-v-abi.c" "$root/tests/wine-host/test.c" \
    $link_flags -o "$work/test"
if nm -u "$work/test" | rg '(^| )_?(memdup|new_array|v_malloc|v_realloc|builtin__malloc|array__push)$'; then
    echo 'Wine host: implicit V allocator import' >&2; exit 1
fi
"$work/test"
