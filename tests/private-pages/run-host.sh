#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/modules/mmap" "$work/modules/memory" "$work/modules/resource" "$work/modules/klock" "$work/modules/errno" "$work/modules/numa" "$work/modules/lib" "$work/modules/proc"
cp "$root/kernel/memory/mmap/page_source.v" "$root/tests/private-pages/source_test.v" "$work/modules/mmap/"
python3 - "$root/kernel/memory/mmap/mmap.v" "$work/modules/mmap/install.v" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
functions = ['page_table_flags', 'range_page_has_file_data', 'install_range_page', 'resolve_cow_fault', 'unshare_private_page_unlocked']
result = 'module mmap\nimport memory\nimport numa\nimport lib\nimport proc\n'
for name in functions:
    begin = source.index('fn ' + name + '(')
    if source[begin-4:begin] == 'pub ': begin -= 4
    end = source.index('\n}\n', begin) + 3
    result += source[begin:end] + '\n'
Path(sys.argv[2]).write_text(result)
PY
cat > "$work/v.mod" <<'VEOF'
Module { name: 'private_page_host_tests' }
VEOF
cat > "$work/modules/klock/klock.v" <<'VEOF'
module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
pub fn (mut l Lock) test_and_acquire() bool { return l.mutex.try_lock() }
VEOF
cat > "$work/modules/errno/errno.v" <<'VEOF'
module errno
pub const enomem = 12
pub fn set(_value int) {}
VEOF
cat > "$work/modules/lib/lib.v" <<'VEOF'
module lib
pub fn align_down(value u64, size u64) u64 { return value / size * size }
VEOF
cat > "$work/modules/numa/numa.v" <<'VEOF'
module numa
import memory
pub fn alloc_user_page() voidptr { return memory.pmm_alloc_fallible(1) }
pub fn alloc_user_page_nozero() voidptr { return memory.pmm_alloc_fallible(1) }
VEOF
cat > "$work/modules/proc/proc.v" <<'VEOF'
module proc
import memory
pub fn account_page_fault(_map &memory.Pagemap, _major bool) {}
VEOF
cat > "$work/modules/memory/memory.v" <<'VEOF'
@[has_globals]
module memory
import klock
pub const pte_present = u64(1)
pub const pte_writable = u64(2)
pub const pte_user = u64(4)
pub const pte_noexec = u64(8)
pub const pte_execute_only = u64(32)
pub fn execute_only_supported() bool { return false }
__global (pub live_pages int pub fail_alloc bool page_refs map[u64]u32)
pub fn pmm_alloc_fallible(_pages u64) voidptr {
    if fail_alloc { return unsafe { nil } }
    live_pages++
    physical := unsafe { calloc(4096, 1) }
    page_refs[u64(physical)] = 1
    return physical
}
pub fn pmm_alloc(pages u64) voidptr { return pmm_alloc_fallible(pages) }
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
    page_refs.delete(u64(physical)); live_pages--
    assert live_pages >= 0
    unsafe { free(physical) }
}
pub struct Page { pub mut: physical u64 flags u64 }
pub struct Pagemap { pub mut: l klock.Lock pages map[u64]Page fail_map bool top_level &u64 = unsafe { &u64(1) } }
pub fn (pm &Pagemap) virt2phys(virt u64) ?u64 {
    if virt !in pm.pages { return none }
    return pm.pages[virt].physical
}
pub fn (pm &Pagemap) user_page_phys(virt u64, write bool) ?u64 {
    if virt !in pm.pages || (write && pm.pages[virt].flags & pte_writable == 0) { return none }
    return pm.pages[virt].physical
}
pub fn (mut pm Pagemap) map_page_unlocked(virt u64, physical u64, flags u64) ? {
    if pm.fail_map { pm.fail_map = false; return none }
    pm.pages[virt] = Page{physical: physical, flags: flags}
}
pub fn (mut pm Pagemap) map_page(virt u64, physical u64, flags u64) ? {
    pm.l.acquire(); defer { pm.l.release() }
    pm.map_page_unlocked(virt, physical, flags)?
}
pub fn (mut pm Pagemap) flag_page(virt u64, flags u64) ? {
    if virt !in pm.pages { return none }
    pm.pages[virt] = Page{physical: pm.pages[virt].physical, flags: flags}
}
VEOF
cat > "$work/modules/resource/resource.v" <<'VEOF'
module resource
import memory
pub struct Resource {
pub mut:
    refcount int = 1
    physical voidptr
    cached bool = true
    range_refs int
    givebacks int
    fail_range bool
    during_mmap fn () = unsafe { nil }
    check_unlocked fn () = unsafe { nil }
}
pub fn (mut res Resource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
    assert memory.pmm_retain(res.physical, 1)
    if res.during_mmap != unsafe { nil } { res.during_mmap() }
    return res.physical
}
pub fn retain_resource(mut res Resource) { res.refcount++ }
pub fn release_resource(mut res Resource) { res.refcount--; assert res.refcount > 0 }
pub fn retain_mapping_range(mut res Resource, _handle voidptr, _offset u64, _length u64, _flags int) bool {
    if res.check_unlocked != unsafe { nil } { res.check_unlocked() }
    if res.fail_range { return false }
    res.range_refs++
    return true
}
pub fn release_mapping_range(mut res Resource, _handle voidptr, _offset u64, _length u64, _flags int) {
    if res.check_unlocked != unsafe { nil } { res.check_unlocked() }
    res.range_refs--; assert res.range_refs >= 0
}
pub fn private_mapping_cow(mut res Resource) bool { return res.cached }
pub fn release_mapping(mut res Resource, _handle voidptr, _page u64, physical voidptr, _flags int) {
    if res.check_unlocked != unsafe { nil } { res.check_unlocked() }
    res.givebacks++
    memory.pmm_free(physical, 1)
}
VEOF
if [ "${VINIX_HOST_SANITIZE:-0}" = 1 ]; then
    VMODULES="$work/modules" "$v" -cc clang -cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined' -enable-globals -gc none test "$work/modules/mmap"
else
    VMODULES="$work/modules" "$v" -enable-globals -gc none test "$work/modules/mmap"
fi
