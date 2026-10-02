#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
tmp=$(mktemp -d)
if [ "${KEEP_TEST_TMP:-0}" = 0 ]; then trap 'rm -rf "$tmp"' EXIT HUP INT TERM; else echo "$tmp"; fi
mkdir -p "$tmp/modules/file" "$tmp/modules/memory" "$tmp/modules/klock" "$tmp/modules/katomic" "$tmp/modules/stat" "$tmp/modules/resource" "$tmp/modules/errno" "$tmp/modules/event/eventstruct"
cp "$root/kernel/file/memory_pressure.v" "$tmp/modules/file/"
cp "$root/tests/memory-pressure/pressure_test.v" "$tmp/modules/file/"
cp "$root/kernel/memory/pressure_policy.v" "$tmp/modules/memory/"
cp "$root/tests/memory-pressure/policy_test.v" "$tmp/modules/memory/"
cat > "$tmp/v.mod" <<'EOF'
Module { name: 'memory_pressure_tests' }
EOF
cat > "$tmp/modules/file/constants.v" <<'EOF'
module file
pub const pollin = 1
EOF
cat > "$tmp/modules/klock/klock.v" <<'EOF'
module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
EOF
cat > "$tmp/modules/katomic/katomic.v" <<'EOF'
module katomic
pub fn inc[T](mut n T) T { old := n; n++; return old }
pub fn dec[T](mut n T) bool { old := n; n--; return old != 1 }
EOF
cat > "$tmp/modules/stat/stat.v" <<'EOF'
module stat
pub struct Stat { pub mut: mode u32 }
EOF
cat > "$tmp/modules/event/eventstruct/eventstruct.v" <<'EOF'
module eventstruct
pub struct Event { pub mut: generation u64 }
EOF
cat > "$tmp/modules/event/event.v" <<'EOF'
module event
import event.eventstruct
pub fn trigger(mut e eventstruct.Event, drop bool) u64 { e.generation++; return 0 }
EOF
cat > "$tmp/modules/errno/errno.v" <<'EOF'
@[has_globals]
module errno
pub const eacces = 13
pub const eperm = 1
pub const enospc = 28
__global (last_error int)
pub fn set(value int) { last_error = value }
pub fn get() int { return last_error }
EOF
# Copy the real interface layout; ioctl behavior is outside these tests.
sed '/__global (/,$d' "$root/kernel/resource/resource.v" | sed '/import ioctl/d' > "$tmp/modules/resource/resource.v"
cat >> "$tmp/modules/resource/resource.v" <<'EOF'
pub const o_directory = 0o200000
pub const o_nofollow = 0o400000
pub fn default_ioctl(handle voidptr, request u64, argp voidptr) ?int { return none }
EOF
cat > "$tmp/modules/memory/snapshot.v" <<'EOF'
@[has_globals]
module memory
pub struct PressureSnapshot {
pub:
 level int
 generation u64
 free_bytes u64
 total_bytes u64
 watermarks PressureWatermarks
 reclaim_runs u64
 reclaimed_pages u64
 allocation_failures u64
}
__global (
 test_pressure_snapshot PressureSnapshot
 test_pressure_observer fn (u64) = unsafe { nil }
)
pub fn register_pressure_observer(callback fn (u64)) { test_pressure_observer = callback }
pub fn pressure_snapshot() PressureSnapshot { return test_pressure_snapshot }
pub fn set_snapshot(level int, generation u64) {
 test_pressure_snapshot = PressureSnapshot{level: level, generation: generation}
 if test_pressure_observer != unsafe { nil } { test_pressure_observer(generation) }
}
EOF
VMODULES="$tmp/modules" "$v" -cc clang -enable-globals -gc none test "$tmp/modules/memory" "$tmp/modules/file"
