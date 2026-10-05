#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/modules/ext2" "$work/modules/memory/mmap" "$work/modules/klock" "$work/modules/errno" "$work/modules/katomic" "$work/modules/pagecache" "$work/modules/stat"
cp "$root/kernel/fs/ext2/mapping.v" "$root/kernel/fs/ext2/writeback.v" "$work/modules/ext2/"
cp "$root/tests/mapped-writeback/mapping_test.v" "$work/modules/ext2/"
python3 - "$root/kernel/fs/ext2/ext2.v" "$work/modules/ext2/acquire.v" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
begin = source.index('fn (mut this EXT2Resource) mmap(')
end = source.index('fn (mut this EXT2Resource) read(', begin)
Path(sys.argv[2]).write_text('module ext2\nimport errno\nimport memory\nimport memory.mmap as mmap_mod\nimport stat\n' + source[begin:end])
PY
cat > "$work/v.mod" <<'EOF'
Module { name: 'mapped_writeback_host_tests' }
EOF
cat > "$work/modules/klock/klock.v" <<'EOF'
module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
pub fn (mut l Lock) test_and_acquire() bool { return l.mutex.try_lock() }
EOF
cat > "$work/modules/errno/errno.v" <<'EOF'
module errno
pub const eio = 5
pub const enomem = 12
pub fn set(_value int) {}
EOF
cat > "$work/modules/katomic/katomic.v" <<'EOF'
module katomic
pub fn inc[T](mut value T) { unsafe { (*value)++ } }
pub fn dec[T](mut value T) bool { unsafe { (*value)-- }; return unsafe { *value != 0 } }
EOF
cat > "$work/modules/memory/memory.v" <<'EOF'
@[has_globals]
module memory
__global (pub live_pages int)
__global (page_refs map[u64]u32)
pub fn pmm_alloc_fallible(_pages u64) voidptr {
    live_pages++
    physical := unsafe { calloc(4096, 1) }
    page_refs[u64(physical)] = 1
    return physical
}
pub fn pmm_retain(physical voidptr, _pages u64) bool {
    if page_refs[u64(physical)] == 0 { return false }
    page_refs[u64(physical)]++
    return true
}
pub fn pmm_refcount(physical voidptr) u32 { return page_refs[u64(physical)] }
pub fn pmm_free(physical voidptr, _pages u64) {
    assert page_refs[u64(physical)] > 0
    page_refs[u64(physical)]--
    if page_refs[u64(physical)] != 0 { return }
    page_refs.delete(u64(physical))
    live_pages--
    assert live_pages >= 0
    unsafe { free(physical) }
}
EOF
cat > "$work/modules/memory/mmap/mmap.v" <<'EOF'
module mmap
pub const map_shared = 1
EOF
cat > "$work/modules/stat/stat.v" <<'EOF'
module stat
pub fn isreg(mode u32) bool { return mode & 0xf000 == 0x8000 }
EOF
cat > "$work/modules/pagecache/pagecache.v" <<'EOF'
module pagecache
pub fn register_sync_hook(_hook fn () bool) bool { return true }
EOF
if [ "${VINIX_HOST_SANITIZE:-0}" = 1 ]; then
    VMODULES="$work/modules" "$v" -cc clang -cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined' -enable-globals -gc none test "$work/modules/ext2"
else
    VMODULES="$work/modules" "$v" -enable-globals -gc none test "$work/modules/ext2"
fi
