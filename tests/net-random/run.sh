#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Unit-test the IP stack's random numbers (kernel/c/net_random.c) on the host:
# the file is compiled as it is, with stand-ins for the kernel's generator and
# clock. run.sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cc=${CC:-cc}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
# -iquote, not -I: kernel/c has its own freestanding string.h and stdlib.h.
"$cc" -std=gnu99 -O2 -Wall -Wextra -Werror -iquote "$root/kernel/c" \
	"$root/kernel/c/net_random.c" "$root/kernel/c/explicit_bzero.c" \
	"$root/tests/net-random/test.c" -o "$work/net-random"
"$work/net-random"
