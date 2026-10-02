#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Unit-test the kernel's random generator (kernel/krandom/random.v) on the
# host: the file is compiled as it is, with stand-ins for the lock and the
# hardware hooks. run.sh [V]
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${1:-${V:-v}}
cc=${CC:-cc}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/krandom" "$work/klock" "$work/katomic"
printf "Module {\n name: 'vinix_krandom_host_tests'\n}\n" > "$work/v.mod"
cp "$root/kernel/krandom/random.v" "$root/kernel/krandom/sha256.v" "$root/tests/krandom/krandom_test.v" \
	"$root/tests/krandom/sha256_test.v" \
	"$root/tests/krandom/host_stubs.v" "$work/krandom/"
# Single-threaded tests; this never goes near the kernel.
cat > "$work/klock/klock.v" <<'STUB'
module klock
pub struct Lock {
	l bool
}
pub fn (mut lock Lock) acquire() {}
pub fn (mut lock Lock) release() {}
STUB
cat > "$work/katomic/katomic.v" <<'STUB'
module katomic
pub fn load[T](value &T) T { return unsafe { *value } }
pub fn store[T](mut target T, value T) { target = value }
STUB
cp "$root/tests/krandom/host_stubs.h" "$work/"
# One object: `v test` passes -ldflags through a shell unquoted.
cat "$root/kernel/c/explicit_bzero.c" "$root/tests/krandom/host_stubs.c" > "$work/host.c"
"$cc" -O2 -c "$work/host.c" -o "$work/host.o"
# From the module's own directory, whose v.mod lets krandom find klock.
cd "$work"
"$v" -enable-globals -gc none -cc "$cc" -ldflags "$work/host.o" test krandom
