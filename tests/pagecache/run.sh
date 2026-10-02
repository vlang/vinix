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
mkdir -p "$tmp/modules/pagecache" "$tmp/modules/errno" "$tmp/modules/klock" "$tmp/modules/memory" "$tmp/modules/katomic"
cp "$root/kernel/pagecache/"*.v "$tmp/modules/pagecache/"
cp "$root/tests/pagecache/pagecache_test.v" "$tmp/modules/pagecache/"
cp "$root/tests/pagecache/registry_test.v" "$tmp/modules/pagecache/"
cat > "$tmp/v.mod" <<'MOD'
Module { name: 'pagecache_host_tests' }
MOD
# Kernel locks, page allocation, reclaimer registration and errno are replaced
# by host facilities. Both cache and global writeback code run unchanged.
cat > "$tmp/modules/pagecache/host.v" <<'VEOF'
module pagecache
#include <alloca.h>
#define vinix_stack_alloc alloca
const page_size = u64(4096)
const higher_half = u64(0)
VEOF
cat > "$tmp/modules/memory/memory.v" <<'VEOF'
@[has_globals]
module memory
__global (pub packed_left int = -1 pub pmm_left int = -1 pub live_pmm int)
pub fn pmm_alloc_nozero_fallible(pages u64) voidptr {
    if pmm_left == 0 { return unsafe { nil } }
    if pmm_left > 0 { pmm_left-- }
    live_pmm++
    return unsafe { malloc(int(pages * 4096)) }
}
pub fn pmm_free(physical voidptr, _pages u64) { live_pmm--; unsafe { free(physical) } }
pub fn malloc_packed_fallible(bytes u64) voidptr {
    if packed_left == 0 { return unsafe { nil } }
    if packed_left > 0 { packed_left-- }
    return unsafe { calloc(usize(bytes), 1) }
}
pub fn register_reclaimer(_callback fn (u64) u64) bool { return true }
VEOF
cat > "$tmp/modules/katomic/katomic.v" <<'VEOF'
module katomic
pub fn load[T](value &T) T { return unsafe { *value } }
pub fn store[T](mut value T, new T) { unsafe { *value = new } }
VEOF
cat > "$tmp/modules/klock/klock.v" <<'VEOF'
module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
pub fn (mut l Lock) test_and_acquire() bool { return l.mutex.try_lock() }
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
