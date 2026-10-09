@[has_globals]
module mmap

import memory
import resource

fn file_alias(res &resource.Resource, physical voidptr, flags int, address u64) &MmapRangeLocal {
	mut pm := &memory.Pagemap{}
	mut global := &MmapRangeGlobal{resource: unsafe { res }, tracked_file: true}
	mut local := &MmapRangeLocal{global: global, pagemap: pm, base: address, flags: flags}
	global.locals.flags |= .noslices
	global.locals << local
	if flags & map_shared == 0 { assert memory.pmm_retain(physical, 1) }
	global.shadow_pagemap.map_page_unlocked(4096, u64(physical), memory.pte_present) or { panic('shadow') }
	pte := memory.pte_present | memory.pte_user | memory.file_referenced |
		(if flags & map_shared != 0 { memory.pte_file_tracked | memory.pte_writable | memory.pte_file_dirty } else { u64(0) })
	pm.map_page_unlocked(address, u64(physical), pte) or { panic('alias') }
	register_file_global(global)
	return local
}

fn dispose_file_alias(local &MmapRangeLocal) {
	mut global := local.global
	range_locals_lock.acquire()
	unregister_file_global_locked(mut global)
	range_locals_lock.release()
	if local.flags & map_shared == 0 {
		for _, page in global.shadow_pagemap.pages { memory.pmm_free(voidptr(page.physical), 1) }
	}
	unsafe {
		global.locals.free()
		global.shadow_pagemap.pages.free()
		local.pagemap.pages.free()
		free(local.pagemap)
		free(global)
		free(local)
	}
}

fn test_all_alias_preflight_age_eviction_and_private_cow_identity() {
	mut res := &resource.Resource{physical: memory.pmm_alloc_fallible(1)}
	first := file_alias(res, res.physical, map_shared, 4096)
	second := file_alias(res, res.physical, map_shared, 12288)
	mut clean := file_alias(res, res.physical, 2, 20480)
	copy := memory.pmm_alloc_fallible(1)
	cow := file_alias(res, copy, 2, 28672)
	memory.pmm_free(copy, 1) // Keep only the COW global's owner.
	mut lazy := file_alias(res, res.physical, map_shared, 36864)
	lazy.pagemap.unmap_page_unlocked(lazy.base) or { panic('unmap') }
	lazy.global.shadow_pagemap.unmap_page_unlocked(4096) or { panic('unmap') }
	lazy.global.shadow_pagemap.top_level = unsafe { nil }

	// A busy alias aborts preflight before changing ANY descriptor.
	second.pagemap.l.acquire()
	busy := file_page_state(voidptr(res), 0, res.physical, true)
	second.pagemap.l.release()
	assert !busy.ready && first.pagemap.pages[first.base].flags & memory.pte_writable != 0
	assert first.global.shadow_pagemap.pages.len == 1 && memory.pmm_refcount(res.physical) == 2

	aged := file_page_state(voidptr(res), 0, res.physical, true)
	assert aged.ready && aged.referenced && aged.dirty && aged.shared_refs == 0
	assert first.pagemap.pages[first.base].flags & memory.pte_writable == 0
	assert second.pagemap.pages[second.base].flags & memory.pte_file_dirty == 0
	assert cow.pagemap.pages.len == 1 && memory.pmm_refcount(copy) == 1

	clean.flags |= map_locked
	locked := file_page_state(voidptr(res), 0, res.physical, true)
	assert locked.ready && locked.blocked && locked.shared_refs == 0
	assert first.global.shadow_pagemap.pages.len == 1
	clean.flags &= ~map_locked
	evicted := file_page_state(voidptr(res), 0, res.physical, true)
	assert evicted.ready && !evicted.referenced && evicted.shared_refs == 2
	assert first.pagemap.pages.len == 0 && second.pagemap.pages.len == 0 && clean.pagemap.pages.len == 0
	assert first.global.shadow_pagemap.pages.len == 0 && memory.pmm_refcount(res.physical) == 1
	assert cow.pagemap.pages.len == 1 && memory.pmm_refcount(copy) == 1
	for local in [first, second, clean, cow, lazy] { dispose_file_alias(local) }
	memory.pmm_free(res.physical, 1)
	unsafe { free(res) }
	assert memory.live_pages == 0 && file_globals == unsafe { nil }
}

fn test_alias_workspace_overflow_and_shadow_lock_contention_are_atomic() {
	mut res := &resource.Resource{physical: memory.pmm_alloc_fallible(1)}
	mut locals := []&MmapRangeLocal{cap: 65}
	for i in 0 .. 65 { locals << file_alias(res, res.physical, map_shared, u64(4096 * (i + 1))) }
	assert !file_page_state(voidptr(res), 0, res.physical, true).ready
	for local in locals { assert local.pagemap.pages[local.base].flags & memory.pte_writable != 0 }
	dispose_file_alias(locals.pop())
	locals[0].global.shadow_pagemap.l.acquire()
	assert !file_page_state(voidptr(res), 0, res.physical, true).ready
	locals[0].global.shadow_pagemap.l.release()
	for local in locals { assert local.pagemap.pages[local.base].flags & memory.pte_writable != 0 }
	for local in locals { dispose_file_alias(local) }
	memory.pmm_free(res.physical, 1)
	unsafe { locals.free(); free(res) }
	assert memory.live_pages == 0 && file_globals == unsafe { nil }
}
