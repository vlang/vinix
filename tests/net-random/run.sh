#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Unit-test the IP stack's random numbers (kernel/socket/inet/net_random.v):
# compile the actual V file, with stand-ins for the kernel's generator and
# clock. run.sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cc=${CC:-cc}
. "$root/build-support/find-v.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
V_C_ERROR_BUG_REPORT_DISABLED=1 "$V" -shared -no-builtin -os vinix \
	-enable-globals -target-libc-headers -nofloat -gc none -manualfree \
	-o "$work/net_random.c" "$root/kernel/socket/inet/net_random.v"
V_C_ERROR_BUG_REPORT_DISABLED=1 "$V" -shared -no-builtin -os vinix \
	-target-libc-headers -nofloat -gc none -manualfree \
	-o "$work/erase.c" "$root/kernel/krandom/erase.v"
sanitizers=${VINIX_NET_RANDOM_SANITIZERS:-address,undefined}
case $sanitizers in
	none) instrumentation= ;;
	*) instrumentation="-fsanitize=$sanitizers -fno-omit-frame-pointer" ;;
esac
# These variables contain flag lists, not shell code.
# Give each standalone V translation unit its own generated startup symbols.
# shellcheck disable=SC2086
"$cc" -std=gnu11 -O2 -Wall -Wextra -Werror -Wno-unused-function \
	-ffreestanding -fno-builtin -fno-strict-aliasing $instrumentation \
	-D_vinit_caller=vinix_erase_vinit_caller -D_vcleanup=vinix_erase_vcleanup \
	-D_vcleanup_caller=vinix_erase_vcleanup_caller -c "$work/erase.c" -o "$work/erase.o"
# shellcheck disable=SC2086
"$cc" -std=gnu11 -O2 -Wall -Wextra -Werror -Wno-unused-function \
	-ffreestanding -fno-builtin -fno-strict-aliasing $instrumentation \
	-c "$work/net_random.c" -o "$work/net_random.o"
python3 - "$work/net_random.o" "$work/erase.o" <<'PY'
import re
import subprocess
import sys
symbols = subprocess.check_output(['nm', '-u', *sys.argv[1:]], text=True)
forbidden = re.findall(r'\b_?(?:malloc|calloc|realloc|free|aligned_alloc|posix_memalign)\b', symbols)
assert not forbidden, forbidden
print('net-random: no allocator imports')
PY
# -iquote, not -I: kernel/c has its own freestanding string.h and stdlib.h.
# shellcheck disable=SC2086
"$cc" -std=gnu11 -O2 -Wall -Wextra -Werror $instrumentation -iquote "$root/kernel/c" \
	"$work/net_random.o" "$work/erase.o" \
	"$root/tests/net-random/test.c" -o "$work/net-random"
"$work/net-random"
