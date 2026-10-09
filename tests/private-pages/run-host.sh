#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
v=${V:-v}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/modules/mmap" "$work/modules/memory" "$work/modules/resource" "$work/modules/klock" "$work/modules/errno" "$work/modules/numa" "$work/modules/lib" "$work/modules/proc" "$work/modules/pager" "$work/modules/kbudget" "$work/modules/cgcontrol"
cp "$root/kernel/kbudget/budget.v" "$work/modules/kbudget/"
cp "$root/kernel/cgcontrol/control.v" "$work/modules/cgcontrol/"
cp "$root/kernel/memory/mmap/page_source.v" "$work/modules/mmap/"
python3 - "$root/tests/private-pages/source_test.v" "$work/modules/mmap" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
begin = source.index('fn test_')
header = source[:source.index('const page_size')]
Path(sys.argv[2], 'fixture.v').write_text(source[:begin])
Path(sys.argv[2], 'source_test.v').write_text(header + source[begin:])
PY
python3 - "$root/kernel/memory/mmap/mmap.v" "$work/modules/mmap/install.v" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
functions = ['page_table_flags', 'range_page_has_file_data', 'install_range_page', 'resolve_cow_fault', 'unshare_private_page_unlocked']
result = 'module mmap\nimport memory\nimport numa\nimport lib\nimport proc\nimport pager\nimport errno\nimport resource\n'
if __import__('os').environ.get('VINIX_FILE_PAGES_HOST') != '1':
    result += 'fn resolve_shared_file_write(_pm &memory.Pagemap, _address u64) bool { return false }\nfn pageout_file_span(_pm &memory.Pagemap, _begin u64, _end u64) u64 { return 0 }\n'
page_source = Path(sys.argv[1]).with_name('paging.v').read_text()
result += page_source[page_source.index('struct PagedPage'):page_source.index('fn reclaim_uncovered_paged_locked')]
if __import__('os').environ.get('VINIX_PAGING_HOST') == '1':
    result = result[:result.index('struct PagedPage')] + page_source[page_source.index('struct PagedPage'):page_source.index('__global (')]
    result = result.replace('import errno\n', 'import errno\nimport sched\nimport kbudget\n')
    result += '__global (pageout_process_cursor = int(1))\n'
    for name in ['reclaim_anonymous', 'max_u64']:
        begin = page_source.index('fn ' + name + '(')
        if page_source[begin-4:begin] == 'pub ': begin -= 4
        end = page_source.index('\n', begin) + 1 if name == 'max_u64' else page_source.index('\n}\n', begin) + 3
        result += page_source[begin:end] + '\n'
    functions += ['range_priority']
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
@[has_globals]
module errno
pub const enomem = 12
pub const eagain = 11
pub const einval = 22
pub const e2big = 7
pub const ebusy = 16
pub const eio = 5
__global (last_error int)
pub fn set(value int) { last_error = value }
pub fn get() int { return last_error }
VEOF
cat > "$work/modules/pager/pager.v" <<'VEOF'
module pager
pub struct Backing {}
pub fn retain(_backing &Backing) {}
pub fn retain_mapping(_backing &Backing) {}
pub fn release(_backing &Backing) {}
pub fn release_mapping(_backing &Backing) {}
pub fn load(_backing &Backing) ?voidptr { return none }
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
@[has_globals]
module proc
import memory
import klock
pub const max_pid = 4
pub struct Process { pub mut: exiting bool pagemap &memory.Pagemap = unsafe { nil } }
__global (pub fixture_process &Process = unsafe { nil } table_lock klock.Lock)
pub fn lock_table() { table_lock.acquire() }
pub fn unlock_table() { table_lock.release() }
pub fn process_at(pid int) &Process { return if pid == 1 { fixture_process } else { unsafe { nil } } }
pub fn account_page_fault(_map &memory.Pagemap, _major bool) {}
VEOF
cat > "$work/modules/memory/memory.v" <<'VEOF'
@[has_globals]
module memory
import klock
import kbudget
pub const pte_present = u64(1)
pub const pte_writable = u64(2)
pub const pte_user = u64(4)
pub const pte_noexec = u64(8)
pub const pte_file_tracked = u64(512)
pub const pte_execute_only = u64(32)
pub fn execute_only_supported() bool { return false }
__global (pub live_pages int pub fail_alloc bool page_refs map[u64]u32)
pub fn pmm_alloc_fallible(pages u64) voidptr {
    if fail_alloc { return unsafe { nil } }
    live_pages++
    physical := unsafe { calloc(usize(4096 * pages), 1) }
    page_refs[u64(physical)] = 1
    return physical
}
pub fn pmm_alloc(pages u64) voidptr { return pmm_alloc_fallible(pages) }
pub fn ensure_table_root(mut pm Pagemap) ? { if pm.top_level == unsafe { nil } { pm.top_level = pmm_alloc_fallible(1); if pm.top_level == unsafe { nil } { return none } } }
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
    unsafe { C.free(physical) }
}
pub struct Page { pub mut: physical u64 flags u64 }
pub struct Pagemap { pub mut: kernel_owner kbudget.Owner l klock.Lock pages map[u64]Page fail_map bool dying bool pageout_cursor u64 inspection_refs int top_level &u64 = unsafe { &u64(1) } }
pub fn release_inspection(pm &Pagemap) { mut map_ := unsafe { pm }; map_.l.acquire(); map_.inspection_refs--; map_.l.release() }
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
pub fn (mut pm Pagemap) unmap_page_unlocked(virt u64) ? { pm.pages.delete(virt) }
pub fn (pm &Pagemap) next_present(begin u64, end u64) u64 {
    mut first := end
    for address, _ in pm.pages { if address >= begin && address < first { first = address } }
    return first
}
__global (heap_allocations map[u64]bool pub heap_objects int pub fixture_total = u64(64 * 1024 * 1024))
pub fn get_hhdm_offset() u64 { return 0 }
pub const page_size = u64(4096)
pub fn total_bytes() u64 { return fixture_total }
pub fn malloc(bytes u64) voidptr { heap_objects++; address := unsafe { calloc(usize(bytes), 1) }; heap_allocations[u64(address)] = true; return address }
pub fn malloc_packed_fallible(bytes u64) voidptr { if fail_alloc { return unsafe { nil } }; return malloc(bytes) }
pub fn note_exhaustion() {}
pub fn free(address voidptr) { if u64(address) in heap_allocations { heap_objects--; heap_allocations.delete(u64(address)) }; unsafe { C.free(address) } }
pub fn pmm_alloc_user_nozero(pages u64) voidptr { return pmm_alloc_fallible(pages) }
VEOF
cat > "$work/modules/resource/resource.v" <<'VEOF'
module resource
import memory
import errno
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
    swap_data []u8
    fail_read bool
    fail_read_errno int
    fail_write bool
    short_io bool
    io_hook fn () = unsafe { nil }
    stat Stat
}
pub struct Stat { pub mut: size i64 }
pub struct BlockIdentity { pub: disk_id u64 start u64 length u64 }
pub fn (identity BlockIdentity) valid() bool { return identity.disk_id != 0 && identity.length != 0 }
pub fn backend_is_read_only(mut _res Resource) bool { return false }
pub fn (mut res Resource) read(_handle voidptr, output voidptr, offset u64, length u64) ?i64 {
    if res.io_hook != unsafe { nil } { res.io_hook() }
    if res.fail_read { errno.set(res.fail_read_errno); return none }
    if offset + length > u64(res.swap_data.len) { return none }
    unsafe { C.memcpy(output, &res.swap_data[offset], usize(length)) }
    return if res.short_io { i64(length - 1) } else { i64(length) }
}
pub fn (mut res Resource) write(_handle voidptr, input voidptr, offset u64, length u64) ?i64 {
    if res.io_hook != unsafe { nil } { res.io_hook() }
    if res.fail_write || offset + length > u64(res.swap_data.len) { return none }
    unsafe { C.memcpy(&res.swap_data[offset], input, usize(length)) }
    return if res.short_io { i64(length - 1) } else { i64(length) }
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
pub fn uncached_mapping_page(mut _res Resource, _page u64, _physical voidptr) bool { return false }
pub fn release_mapping(mut res Resource, _handle voidptr, _page u64, physical voidptr, _flags int) {
    if res.check_unlocked != unsafe { nil } { res.check_unlocked() }
    res.givebacks++
    memory.pmm_free(physical, 1)
}
VEOF
if [ "${VINIX_PAGING_HOST:-0}" = 1 ]; then
    rm "$work/modules/pager/pager.v"
    cp "$root/kernel/pager/"*.v "$root/tests/paging/store_test.v" "$root/tests/paging/codec_test.v" "$work/modules/pager/"
    cp "$root/tests/paging/mapping_test.v" "$work/modules/mmap/"
    mkdir -p "$work/modules/sched"
    cat > "$work/modules/sched/sched.v" <<'VEOF'
module sched
import time
pub fn yield(_save bool) { time.sleep(time.microsecond) }
VEOF
    cat > "$work/modules/mmap/pressure_fixture.v" <<'VEOF'
@[has_globals]
module mmap
import memory
__global (pressure_locked_prefix int pressure_prefix_range MmapRangeLocal)
fn prefix_range(address u64) &MmapRangeLocal {
    pressure_prefix_range.base = max_u64(4096, address / 4096 * 4096)
    pressure_prefix_range.length = 4096
    pressure_prefix_range.flags = map_anonymous | map_locked
    return unsafe { &pressure_prefix_range }
}
fn range_floor(_pm &memory.Pagemap, address u64) &MmapRangeLocal {
    if fixture_local != unsafe { nil } && address >= fixture_local.base { return fixture_local }
    if pressure_locked_prefix != 0 && address >= 4096 { return prefix_range(address) }
    return unsafe { nil }
}
fn range_lower_bound(_pm &memory.Pagemap, address u64) &MmapRangeLocal {
    if fixture_local != unsafe { nil } && address <= fixture_local.base {
        if pressure_locked_prefix != 0 && address < fixture_local.base { return prefix_range(address) }
        return fixture_local
    }
    return unsafe { nil }
}
VEOF
    mkdir -p "$work/modules/krandom" "$work/modules/event/eventstruct"
    cp "$root/kernel/krandom/sha256.v" "$root/kernel/krandom/erase.v" "$work/modules/krandom/"
    cat > "$work/modules/krandom/fixture.v" <<'VEOF'
module krandom
pub fn fill(output voidptr, length u64, _insecure bool) bool {
    for i in 0 .. length { unsafe { (&u8(output))[i] = u8(i * 17 + 91) } }
    return true
}
VEOF
    cat > "$work/modules/event/eventstruct/event.v" <<'VEOF'
module eventstruct
import sync
pub struct Event { pub mut: lock sync.Mutex sequence u64 }
VEOF
    cat > "$work/modules/event/event.v" <<'VEOF'
module event
import event.eventstruct
import time
pub fn generation(mut e eventstruct.Event) u64 { e.lock.lock(); result := e.sequence; e.lock.unlock(); return result }
pub fn trigger(mut e eventstruct.Event, _wake bool) { e.lock.lock(); e.sequence++; e.lock.unlock() }
pub fn may_wait() bool { return true }
pub fn await_one_from_generation(mut e eventstruct.Event, _block bool, previous u64) ?u64 {
    for _ in 0 .. 2000 { if generation(mut e) != previous { return 0 }; time.sleep(time.millisecond) }
    panic('host pager event timed out')
}
pub fn await_one_from_generation_masked(mut e eventstruct.Event, previous u64) ?u64 {
    return await_one_from_generation(mut e, true, previous)
}
VEOF
fi
if [ "${VINIX_FILE_PAGES_HOST:-0}" = 1 ]; then
    cp "$root/kernel/memory/mmap/file_pages.v" "$root/tests/mapped-writeback/aliases_test.v" "$work/modules/mmap/"
    cat >> "$work/modules/memory/memory.v" <<'VEOF'
pub const pte_file_dirty = u64(1) << 20
pub const file_referenced = u64(1) << 21
pub struct PageActivity { pub: referenced bool dirty bool }
pub fn (mut pm Pagemap) protect_file_page_unlocked(address u64) {
    if address !in pm.pages { return }
    mut p := pm.pages[address]
    if p.flags & pte_file_tracked == 0 { return }
    p.flags &= ~pte_writable
    pm.pages[address] = p
}
pub fn (mut pm Pagemap) sample_file_page_unlocked(address u64, reset bool) PageActivity {
    if address !in pm.pages { return PageActivity{} }
    mut p := pm.pages[address]
    result := PageActivity{ referenced: p.flags & file_referenced != 0, dirty: p.flags & pte_file_dirty != 0 }
    if reset { p.flags &= ~(file_referenced | pte_file_dirty); pm.pages[address] = p }
    return result
}
pub fn (mut pm Pagemap) allow_file_write_unlocked(address u64) bool {
    if address !in pm.pages || pm.pages[address].flags & pte_file_tracked == 0 { return false }
    mut p := pm.pages[address]
    p.flags |= pte_writable | pte_file_dirty | file_referenced
    pm.pages[address] = p
    return true
}
VEOF
    cat >> "$work/modules/resource/resource.v" <<'VEOF'
pub fn mark_mapping_dirty(mut _res Resource, _page u64, _physical voidptr) {}
pub fn sync_mapping(mut _res Resource, _handle voidptr, _offset u64, _length u64) ? {}
pub fn pageout_mapping(mut _res Resource, _page u64) u64 { return 0 }
VEOF
fi
if [ "${VINIX_HOST_SANITIZE:-0}" = 1 ]; then
    VMODULES="$work/modules" "$v" -cc clang -cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined' -enable-globals -gc none test "$work/modules/mmap"
else
    VMODULES="$work/modules" "$v" -enable-globals -gc none test "$work/modules/mmap"
fi
if [ "${VINIX_PAGING_HOST:-0}" = 1 ]; then
    if [ "${VINIX_HOST_SANITIZE:-0}" = 1 ]; then
        VMODULES="$work/modules" "$v" -cc clang -cflags '-fsanitize=address,undefined' -ldflags '-fsanitize=address,undefined' -enable-globals -gc none test "$work/modules/pager"
    else
        VMODULES="$work/modules" "$v" -enable-globals -gc none test "$work/modules/pager"
    fi
fi
