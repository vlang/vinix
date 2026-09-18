#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Compile the actual shared V generator, without executing privileged code.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
cc=${CC:-cc}
command -v "$v" >/dev/null 2>&1 || { echo "V compiler not found: $v" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/krandom" "$work/klock" "$work/securemem"
printf "Module {\n name: 'vinix_rng_host_tests'\n}\n" > "$work/v.mod"
cp "$root/kernel/krandom/random.v" "$work/krandom/"
cp "$root/tests/security/krandom_test.v" "$work/krandom/"
cp "$root/tests/security/krandom_host.v" "$work/krandom/"
cp "$root/kernel/securemem/securemem.v" "$work/securemem/"
# Tests are single-threaded. This stub never enters the production kernel.
cat > "$work/klock/klock.v" <<'STUB'
module klock
pub struct Lock {}
pub fn (mut lock Lock) acquire() {}
pub fn (mut lock Lock) release() {}
STUB
"$cc" -O2 -I"$root/kernel/c" -c "$root/kernel/c/explicit_bzero.c" -o "$work/explicit_bzero.o"
"$v" -enable-globals -gc none -cc "$cc" \
    -path "$work|@vlib" -cflags "-I$root/kernel/c" \
    -ldflags "$work/explicit_bzero.o" test "$work/krandom"
