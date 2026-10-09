@[has_globals]
module mmap

import memory
import resource
import klock

const page_size = u64(4096)
const higher_half = u64(0)
const prot_none = 0
const prot_read = 1
const prot_write = 2
const prot_exec = 4
const map_shared = 1
const map_anonymous = 0x20
const map_locked = 0x2000

struct MmapRangeGlobal {
mut:
    serial u64 = 1
    private_cow bool = true
    resource &resource.Resource
    handle voidptr
    handle_ref fn (voidptr) = unsafe { nil }
    handle_unref fn (voidptr) = unsafe { nil }
    offset i64
    base u64 = 4096
    length u64 = 4096
    segmented_file bool
    file_data_start u64
    file_data_length u64
    shadow_pagemap memory.Pagemap
    tracked_file bool
    file_registered bool
    file_previous &MmapRangeGlobal = unsafe { nil }
    file_next &MmapRangeGlobal = unsafe { nil }
    pte_extra u64
    paged_pages &PagedPage = unsafe { nil }
    locals []&MmapRangeLocal
}
struct MmapRangeLocal {
mut:
	generation u64 = 1
    pagemap &memory.Pagemap = unsafe { nil }
    immutable bool
    base u64 = 4096
    length u64 = 4096
    offset i64
    flags int = 2
    prot int = prot_read | prot_write
    cow bool = true
    global &MmapRangeGlobal
}
__global (
    fixture_local &MmapRangeLocal = unsafe { nil }
    active_map &memory.Pagemap = unsafe { nil }
    race_mode int
    handle_refs int = 1
    range_locals_lock klock.Lock
)
fn addr2range(_map &memory.Pagemap, virt u64) ?(&MmapRangeLocal, u64, u64) {
    if fixture_local == unsafe { nil } || virt < fixture_local.base || virt >= fixture_local.base + fixture_local.length { return none }
    return fixture_local, virt / page_size, u64(fixture_local.offset) / page_size + (virt - fixture_local.base) / page_size
}
fn sync_new_code_page(_physical voidptr) {}
fn assert_map_unlocked() {
    assert active_map.l.test_and_acquire()
    active_map.l.release()
}
fn retain_handle(_handle voidptr) { handle_refs++ }
fn release_handle(_handle voidptr) { handle_refs--; assert handle_refs >= 1 }
fn race() {
    match race_mode {
        0 {
            // Actually destroy both borrowed pointers before mmap returns.
            old := fixture_local
            fixture_local = unsafe { nil }
            unsafe { free(old.global); free(old) }
        }
        1 { fixture_local.global.serial++ }
        2 { fixture_local.offset += i64(page_size) }
        3 { fixture_local.flags = map_shared }
        4 { fixture_local.generation++ }
        else {}
    }
}
fn fixture() (&memory.Pagemap, &resource.Resource) {
    mut res := &resource.Resource{physical: memory.pmm_alloc_fallible(1), check_unlocked: assert_map_unlocked}
    unsafe { C.memset(res.physical, 0x83, page_size) }
    fixture_local = &MmapRangeLocal{global: &MmapRangeGlobal{resource: res}}
    active_map = &memory.Pagemap{}
    return active_map, res
}
fn snapshot(pm &memory.Pagemap) RangePageSource {
    mut m := unsafe { pm }
    m.l.acquire()
    source := range_page_source(fixture_local, 4096)
    m.l.release()
    return source
}
fn dispose(mut pm memory.Pagemap, res &resource.Resource) {
    assert res.refcount == 1 && res.range_refs == 0
    // Release fixture's owned cache page and every installed mapping/copy.
    for _, entry in fixture_local.global.shadow_pagemap.pages { memory.pmm_free(voidptr(entry.physical), 1) }
    memory.pmm_free(res.physical, 1)
    unsafe { fixture_local.global.shadow_pagemap.pages.free(); pm.pages.free(); free(fixture_local.global); free(fixture_local); free(res); free(active_map) }
    fixture_local = unsafe { nil }
    active_map = unsafe { nil }
    assert memory.live_pages == 0
}

fn fill_test_page(mut pm memory.Pagemap, source RangePageSource, virt u64, file_page u64) bool {
    fill_range_page(mut pm, source, virt, file_page) or { return false }
    return true
}

fn test_removed_replaced_offset_and_flags_races_give_back_every_acquisition() {
    for mode in 0 .. 5 {
        mut pm, mut res := fixture()
        source := snapshot(pm)
        assert res.refcount == 2
        race_mode = mode
        res.during_mmap = race
        result := fill_test_page(mut pm, source, 4096, 0)
        if mode == 0 { assert !result } else { assert result }
        assert res.givebacks == 1 && memory.pmm_refcount(res.physical) == 1
        assert pm.pages.len == 0 && res.refcount == 1 && res.range_refs == 0
        if fixture_local == unsafe { nil } {
            memory.pmm_free(res.physical, 1)
            unsafe { pm.pages.free(); free(res); free(pm) }
        } else { dispose(mut pm, res) }
    }
    assert memory.live_pages == 0
}

fn test_optional_storage_pin_failure_drops_object_or_handle_pin() {
    mut pm, mut res := fixture()
    res.fail_range = true
    source := snapshot(pm)
    assert !fill_test_page(mut pm, source, 4096, 0)
    assert res.refcount == 1 && res.givebacks == 0 && res.range_refs == 0
    fixture_local.global.handle = voidptr(1)
    fixture_local.global.handle_ref = retain_handle
    fixture_local.global.handle_unref = release_handle
    handle_source := snapshot(pm)
    assert handle_refs == 2 && res.refcount == 1
    assert !fill_test_page(mut pm, handle_source, 4096, 0)
    assert handle_refs == 1
    dispose(mut pm, res)
}

fn test_elf_edge_zero_fill_isolated_from_cached_file_page() {
    mut pm, mut res := fixture()
    fixture_local.global.segmented_file = true
    fixture_local.global.file_data_start = 13
    fixture_local.global.file_data_length = 100
    source := snapshot(pm)
    assert fill_test_page(mut pm, source, 4096, 0)
    installed := pm.virt2phys(4096) or { panic('no page') }
    assert installed != u64(res.physical) && memory.pmm_refcount(res.physical) == 1
    bytes := unsafe { &u8(installed) }
    cached := unsafe { &u8(res.physical) }
    for i in 0 .. int(page_size) {
        assert unsafe { bytes[i] } == if i >= 13 && i < 113 { u8(0x83) } else { u8(0) }
        assert unsafe { cached[i] } == 0x83
    }
    dispose(mut pm, res)
}

fn test_surplus_private_acquisition_and_cow_failure_restore_ownership() {
    mut pm, mut res := fixture()
    first := snapshot(pm)
    assert fill_test_page(mut pm, first, 4096, 0)
    assert memory.pmm_refcount(res.physical) == 2
    second := snapshot(pm)
    assert fill_test_page(mut pm, second, 4096, 0)
    assert res.givebacks == 1 && memory.pmm_refcount(res.physical) == 2
    memory.fail_alloc = true
    assert !resolve_cow_fault(pm, 4113)
    memory.fail_alloc = false
    assert memory.pmm_refcount(res.physical) == 2 && res.refcount == 1 && res.range_refs == 0
    pm.fail_map = true
    assert !resolve_cow_fault(pm, 4113)
    assert pm.pages[4096].physical == u64(res.physical)
    assert fixture_local.global.shadow_pagemap.pages[4096].physical == u64(res.physical)
    assert memory.live_pages == 1 && memory.pmm_refcount(res.physical) == 2
    assert resolve_cow_fault(pm, 4113)
    assert memory.pmm_refcount(res.physical) == 1 && res.givebacks == 2
    installed := pm.pages[4096].physical
    assert installed != u64(res.physical) && memory.pmm_refcount(voidptr(installed)) == 1
    assert unsafe { (&u8(installed))[17] } == 0x83
    assert res.refcount == 1 && res.range_refs == 0
    dispose(mut pm, res)
}

fn test_ordinary_fork_private_page_drops_pmm_reference_without_cache_hook() {
    mut pm, mut res := fixture()
    res.cached = false
    fixture_local.global.private_cow = false
    assert memory.pmm_retain(res.physical, 1)
    pm.pages[4096] = memory.Page{physical: u64(res.physical), flags: memory.pte_present}
    fixture_local.global.shadow_pagemap.pages[4096] = pm.pages[4096]
    assert resolve_cow_fault(pm, 4113)
    assert memory.pmm_refcount(res.physical) == 1 && res.givebacks == 0
    assert res.refcount == 1 && res.range_refs == 0
    dispose(mut pm, res)
}
