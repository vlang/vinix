module mmap

import memory
import pager
import proc

fn anonymous_fixture() &memory.Pagemap {
	mut pm, _ := fixture()
	fixture_local.flags = map_anonymous | 2
	fixture_local.cow = false
	fixture_local.pagemap = pm
	fixture_local.global.locals << fixture_local
	page := memory.pmm_alloc_fallible(1)
	unsafe { C.memset(page, 0x73, 4096) }
	pm.map_page(4096, u64(page), memory.pte_present | memory.pte_writable) or { panic('local map') }
	fixture_local.global.shadow_pagemap.map_page(4096, u64(page), memory.pte_present) or { panic('shadow map') }
	return pm
}

fn dispose_anonymous(mut pm memory.Pagemap) {
	mut global := fixture_local.global
	release_paged_pages(mut global)
	for _, entry in global.shadow_pagemap.pages { memory.pmm_free(voidptr(entry.physical), 1) }
	memory.pmm_free(global.resource.physical, 1)
	unsafe {
		global.locals.free()
		global.shadow_pagemap.pages.free()
		pm.pages.free()
		free(global.resource)
		free(global)
		free(fixture_local)
		free(pm)
	}
	fixture_local = unsafe { nil }
	active_map = unsafe { nil }
	assert memory.live_pages == 0 && memory.heap_objects == 0 && pager.snapshot().compressed_pages == 0
}

fn test_pageout_refault_race_rejects_a_zero_page_captured_before_eviction() {
	mut pm := anonymous_fixture()
	before := snapshot(pm)
	assert pageout(pm, 4096, 4096) == 1
	assert pm.pages.len == 0 && fixture_local.global.shadow_pagemap.pages.len == 0
	// Production fill retries against the backing, rather than installing the
	// zero page that this source originally expected to acquire.
	assert fill_test_page(mut pm, before, 4096, 0)
	physical := pm.virt2phys(4096) or { panic('refault missing') }
	for i in 0 .. 4096 {
		assert unsafe { (&u8(physical))[i] } == 0x73
	}
	assert fixture_local.global.paged_pages == unsafe { nil }
	dispose_anonymous(mut pm)
}

fn test_shared_aliases_are_revoked_and_locked_alias_prevents_pageout() {
	mut pm := anonymous_fixture()
	fixture_local.flags = map_shared | map_anonymous
	mut other := &memory.Pagemap{}
	mut alias := &MmapRangeLocal{ pagemap: other, global: fixture_local.global, base: 16384, flags: map_shared | map_anonymous }
	fixture_local.global.locals << alias
	physical := pm.virt2phys(4096) or { panic('no frame') }
	other.map_page(16384, physical, memory.pte_present | memory.pte_writable) or { panic('alias map') }
	alias.flags |= map_locked
	assert pageout(pm, 4096, 4096) == 0 && pm.pages.len == 1 && other.pages.len == 1
	alias.flags &= ~map_locked
	other.l.acquire()
	assert pageout(pm, 4096, 4096) == 0 // failed try-lock preserves both aliases
	other.l.release()
	assert pageout(pm, 4096, 4096) == 1
	assert pm.pages.len == 0 && other.pages.len == 0
	assert fill_test_page(mut pm, snapshot(pm), 4096, 0)
	fixture_local.global.locals.delete(1)
	unsafe {
		other.pages.free()
		free(alias)
		free(other)
	}
	dispose_anonymous(mut pm)
}

fn test_swapped_fork_and_uncovered_page_lifetimes() {
	mut pm := anonymous_fixture()
	assert pageout(pm, 4096, 4096) == 1
	mut child := &MmapRangeGlobal{ resource: fixture_local.global.resource }
	fork_paged_span(fixture_local.global, mut child, 4096, 8192)
	assert child.paged_pages.backing == fixture_local.global.paged_pages.backing
	// Parent discard cannot invalidate its child's nonresident contents.
	fixture_local.global.locals.clear()
	reclaim_uncovered_paged_locked(mut fixture_local.global, 4096, 8192)
	assert fixture_local.global.paged_pages == unsafe { nil }
	loaded := pager.load(child.paged_pages.backing) or { panic('child refault') }
	for i in 0 .. 4096 {
		assert unsafe { (&u8(loaded))[i] } == 0x73
	}
	memory.pmm_free(loaded, 1)
	release_paged_pages(mut child)
	unsafe { free(child) }
	dispose_anonymous(mut pm)
}

fn test_failed_pageout_restores_original_frame_and_metadata_failure_keeps_mapping() {
	mut pm := anonymous_fixture()
	physical := pm.virt2phys(4096) or { panic('no frame') }
	memory.fail_alloc = true
	assert pageout(pm, 4096, 4096) == 0
	assert pm.virt2phys(4096) or { u64(0) } == physical
	assert fixture_local.global.paged_pages == unsafe { nil }
	memory.fail_alloc = false
	// Incompressible bytes with no active disk must return the original frame
	// to the shadow and leave private aliases read-only for any fork sharers.
	mut random := u32(97)
	for i in 0 .. 4096 {
		random ^= random << 13
		random ^= random >> 17
		random ^= random << 5
		unsafe { (&u8(physical))[i] = u8(random) }
	}
	assert pageout(pm, 4096, 4096) == 0
	assert pm.virt2phys(4096) or { u64(0) } == physical
	assert fixture_local.global.paged_pages == unsafe { nil }
	assert fixture_local.cow
	dispose_anonymous(mut pm)
}

fn test_pressure_cursor_wraps_in_same_pass_and_reclaims_a_full_target() {
	mut pm := anonymous_fixture()
	fixture_local.length = 300 * 4096
	for i in 1 .. 300 {
		frame := memory.pmm_alloc_fallible(1)
		address := u64(i + 1) * 4096
		pm.map_page(address, u64(frame), memory.pte_present | memory.pte_writable) or { panic('local') }
		fixture_local.global.shadow_pagemap.map_page(address, u64(frame), memory.pte_present) or { panic('shadow') }
	}
	mut process := &proc.Process{ pagemap: pm }
	proc.fixture_process = process
	// The previous pass ended here. Recovery must wrap immediately rather
	// than tell OOM that the process has no evictable frames.
	pm.pageout_cursor = fixture_local.base + fixture_local.length
	assert reclaim_anonymous(300, false) == 300
	assert pm.pages.len == 0 && pm.inspection_refs == 0
	proc.fixture_process = unsafe { nil }
	unsafe { free(process) }
	dispose_anonymous(mut pm)
}

fn test_foreground_reclaim_reaches_eligible_pages_after_a_locked_prefix() {
	mut pm := anonymous_fixture()
	physical := pm.virt2phys(4096) or { panic('frame') }
	pm.pages.delete(4096)
	fixture_local.base = 601 * 4096
	pm.map_page(fixture_local.base, physical, memory.pte_present | memory.pte_writable) or { panic('map') }
	pressure_locked_prefix = 600
	proc.fixture_process = &proc.Process{ pagemap: pm }
	pm.pageout_cursor = 4096
	assert reclaim_anonymous(1, false) == 0 // bounded background chunk
	assert pm.pages.len == 1
	assert reclaim_anonymous(1, true) == 1 // full foreground search before OOM
	assert pm.pages.len == 0 && pm.inspection_refs == 0
	pressure_locked_prefix = 0
	unsafe { free(proc.fixture_process) }
	proc.fixture_process = unsafe { nil }
	dispose_anonymous(mut pm)
}
