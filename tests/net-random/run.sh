#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Unit-test the IP stack's random numbers (kernel/c/net_random.c) on the host:
# the file is compiled as it is, with stand-ins for the kernel's generator and
# clock. run.sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cc=${CC:-cc}
. "$root/build-support/find-v.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
V_C_ERROR_BUG_REPORT_DISABLED=1 "$V" -shared -no-builtin -os vinix \
	-target-libc-headers -nofloat -gc none -manualfree \
	-o "$work/erase.c" "$root/kernel/krandom/erase.v"
"$cc" -std=gnu11 -O2 -Wall -Wextra -Werror -Wno-unused-function \
	-fno-strict-aliasing -c "$work/erase.c" -o "$work/erase.o"
# -iquote, not -I: kernel/c has its own freestanding string.h and stdlib.h.
"$cc" -std=gnu11 -O2 -Wall -Wextra -Werror -iquote "$root/kernel/c" \
	"$root/kernel/c/net_random.c" "$work/erase.o" \
	"$root/tests/net-random/test.c" -o "$work/net-random"
"$work/net-random"
