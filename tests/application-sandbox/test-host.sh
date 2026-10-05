#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$root/build-support/security-tools/compile-v-core.py" sandbox "$work/core.c" -d security_no_main -d security_fixture
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -D_GNU_SOURCE -DVINIX_V_RUNTIME -DVINIX_SECURITY_FIXTURE -I"$root/tools/sandbox" -c "$work/core.c" -o "$work/core.o"
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=address,undefined \
    "$root/tests/application-sandbox/host.c" "$work/core.o" -o "$work/host"
"$work/host" 2>"$work/failures.log"
