#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
if ! command -v "$v" >/dev/null 2>&1; then
    echo "V compiler not found: set V=/path/to/v" >&2
    exit 127
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/modules/pagecache" "$tmp/modules/errno" "$tmp/modules/klock" "$tmp/modules/memory"
cp "$root/kernel/pagecache/pagecache.v" "$tmp/modules/pagecache/"
cp "$root/tests/pagecache/pagecache_test.v" "$tmp/modules/pagecache/"
cat > "$tmp/v.mod" <<'MOD'
Module { name: 'pagecache_host_tests' }
MOD
# Synchronization, errno and physical storage are substituted. The cache implementation is
# copied unchanged from the kernel and exercised directly, not reimplemented.
cat > "$tmp/modules/klock/klock.v" <<'VEOF'
module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
pub fn (mut l Lock) test_and_acquire() bool { return l.mutex.try_lock() }
VEOF
cat > "$tmp/modules/memory/memory.v" <<'VEOF'
@[has_globals]
module memory
__global (
 page_size = u64(4096)
 higher_half = u64(0)
)
pub fn pmm_alloc_nozero_fallible(count u64) voidptr { return unsafe { malloc(int(count * page_size)) } }
pub fn pmm_free(p voidptr, count u64) { unsafe { free(p) } }
pub fn malloc_packed_fallible(size u64) voidptr {
 p := unsafe { malloc(int(size)) }
 if p != unsafe { nil } { unsafe { C.memset(p, 0, size) } }
 return p
}
VEOF
cat > "$tmp/modules/errno/errno.v" <<'VEOF'
@[has_globals]
module errno
pub const eio = 5
pub const enomem = 12
pub const ebusy = 16
pub const einval = 22
__global (last_error int)
pub fn set(value int) { last_error = value }
pub fn get() int { return last_error }
VEOF
VMODULES="$tmp/modules" "$v" -enable-globals -gc none test "$tmp/modules/pagecache"
