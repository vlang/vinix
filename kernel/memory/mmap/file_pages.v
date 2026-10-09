@[has_globals]
module mmap

import memory
import resource

__global (file_globals &MmapRangeGlobal = unsafe { nil })

fn register_file_global(global &MmapRangeGlobal) {
	mut g := unsafe { global }
	if !g.tracked_file { return }
	range_locals_lock.acquire()
	defer { range_locals_lock.release() }
	if g.file_registered { return }
	g.file_next = file_globals
	if file_globals != unsafe { nil } { file_globals.file_previous = g }
	file_globals = g
	g.file_registered = true
}

// Called when the final local is identified, under range_locals_lock, before
// shadow tables or the resource can be released.
fn unregister_file_global_locked(mut g MmapRangeGlobal) {
	if !g.file_registered { return }
	if g.file_previous == unsafe { nil } { file_globals = g.file_next }
	else { g.file_previous.file_next = g.file_next }
	if g.file_next != unsafe { nil } { g.file_next.file_previous = g.file_previous }
	g.file_registered = false
}

pub struct FilePageState {
pub mut:
	ready bool
	referenced bool
	dirty bool
	blocked bool
	shared_refs u64
}

// Called with the vnode pinned and locked. Reverse VM lock acquisition is
// exclusively nonblocking. Preflight every alias before any mutation; neither
// a busy alias nor the bounded workspace can leave a partially revoked page.
// No callback or I/O runs while VM locks are held.
pub fn file_page_state(box voidptr, file_page u64, physical voidptr, evict bool) FilePageState {
	mut state := FilePageState{}
	if !range_locals_lock.test_and_acquire() { return state }
	mut globals := unsafe { [64]&MmapRangeGlobal{} }
	mut maps := unsafe { [64]&memory.Pagemap{} }
	mut count := 0
	mut map_count := 0
	mut shadows := 0
	defer {
		for i := shadows - 1; i >= 0; i-- { globals[i].shadow_pagemap.l.release() }
		for i := map_count - 1; i >= 0; i-- { maps[i].l.release() }
		range_locals_lock.release()
	}
	mut g := file_globals
	for g != unsafe { nil } {
		if voidptr(g.resource) == box && file_page * page_size >= u64(g.offset)
			&& file_page * page_size - u64(g.offset) < g.length {
			key := g.base + file_page * page_size - u64(g.offset)
			mut covered := false
			for local in g.locals {
				if !shadow_covered(local, key) { continue }
				covered = true
				mut found := false
				for i in 0 .. map_count { if voidptr(maps[i]) == voidptr(local.pagemap) { found = true; break } }
				if !found {
					if map_count == maps.len || !local.pagemap.l.test_and_acquire() { return state }
					maps[map_count] = local.pagemap
					map_count++
				}
			}
			if covered {
				if count == globals.len { return state }
				globals[count] = g
				count++
			}
		}
		g = g.file_next
	}
	for i in 0 .. count {
		if !globals[i].shadow_pagemap.l.test_and_acquire() { return state }
		shadows++
	}
	for i in 0 .. count {
		global := globals[i]
		if global.shadow_pagemap.top_level == unsafe { nil } { continue }
		key := global.base + file_page * page_size - u64(global.offset)
		frame := global.shadow_pagemap.virt2phys(key) or { continue }
		if frame != u64(physical) { continue }
		for local in global.locals {
			if !shadow_covered(local, key) { continue }
			address := local.base + key - shadow_begin(local)
			if alias := local.pagemap.virt2phys(address) {
				if alias != frame { return state }
			}
		}
	}
	// First revoke writes on every matching alias, preserving dirty evidence.
	// All shootdowns complete before any dirty bit is collected or cleared.
	for i in 0 .. count {
		global := globals[i]
		if global.shadow_pagemap.top_level == unsafe { nil } { continue }
		key := global.base + file_page * page_size - u64(global.offset)
		frame := global.shadow_pagemap.virt2phys(key) or { continue }
		if frame != u64(physical) { continue }
		for local in global.locals {
			if !shadow_covered(local, key) { continue }
			if local.flags & map_locked != 0 || local.immutable { state.blocked = true }
			address := local.base + key - shadow_begin(local)
			if _ := local.pagemap.virt2phys(address) {
				local.pagemap.protect_file_page_unlocked(address)
			}
		}
	}
	for i in 0 .. count {
		global := globals[i]
		if global.shadow_pagemap.top_level == unsafe { nil } { continue }
		key := global.base + file_page * page_size - u64(global.offset)
		frame := global.shadow_pagemap.virt2phys(key) or { continue }
		if frame != u64(physical) { continue } // private COW frame
		for local in global.locals {
			if !shadow_covered(local, key) { continue }
			address := local.base + key - shadow_begin(local)
			activity := local.pagemap.sample_file_page_unlocked(address, true)
			state.referenced = state.referenced || activity.referenced
			if local.flags & map_shared != 0 { state.dirty = state.dirty || activity.dirty }
		}
	}
	state.ready = true
	if !evict || state.referenced || state.blocked { return state }
	for i in 0 .. count {
		global := globals[i]
		if global.shadow_pagemap.top_level == unsafe { nil } { continue }
		key := global.base + file_page * page_size - u64(global.offset)
		frame := global.shadow_pagemap.virt2phys(key) or { continue }
		if frame != u64(physical) { continue }
		mut shared := false
		for local in global.locals {
			if !shadow_covered(local, key) { continue }
			shared = local.flags & map_shared != 0
			address := local.base + key - shadow_begin(local)
			local.pagemap.unmap_page_unlocked(address) or {}
		}
		global.shadow_pagemap.unmap_page_unlocked(key) or { panic('file pageout: shadow disappeared') }
		if shared { state.shared_refs++ }
		else { memory.pmm_free(physical, 1) }
	}
	return state
}

fn harvest_file_dirty_unlocked(mut pagemap memory.Pagemap, local &MmapRangeLocal, address u64) {
	if !local.global.tracked_file || local.flags & map_shared == 0 { return }
	physical := pagemap.virt2phys(address) or { return }
	pagemap.protect_file_page_unlocked(address)
	if !pagemap.sample_file_page_unlocked(address, false).dirty { return }
	mut res := local.global.resource
	page := u64(local.offset) / page_size + (address - local.base) / page_size
	resource.mark_mapping_dirty(mut res, page, voidptr(physical))
}

fn resolve_shared_file_write(pagemap &memory.Pagemap, address u64) bool {
	mut pm := unsafe { pagemap }
	pm.l.acquire()
	defer { pm.l.release() }
	local, _, _ := addr2range(pm, address) or { return false }
	if !local.global.tracked_file || local.flags & map_shared == 0 || local.prot & prot_write == 0 { return false }
	return pm.allow_file_write_unlocked(address)
}

// The source pin, not a borrowed VMA, survives writeback. Device and vnode
// callbacks may take VM locks, so msync never keeps the caller's map locked.
fn sync_file_span(_source RangePageSource, offset u64, length u64) ? {
	mut source := _source
	defer { source.close() }
	if !source.prepare() { return none }
	mut res := source.resource
	resource.sync_mapping(mut res, source.handle, offset, length)?
}

fn pageout_file_span(pagemap &memory.Pagemap, begin u64, end u64) u64 {
	mut pm := unsafe { pagemap }
	mut cursor := begin
	mut reclaimed := u64(0)
	for cursor < end {
		pm.l.acquire()
		address := pm.next_present(cursor, end)
		if address == end { pm.l.release(); break }
		cursor = address + page_size
		local, _, _ := addr2range(pm, address) or { pm.l.release(); continue }
		if !local.global.tracked_file || local.flags & map_locked != 0 || local.immutable {
			pm.l.release(); continue
		}
		mut source := range_page_source(local, address)
		pm.l.release()
		if source.prepare() {
			mut res := source.resource
			reclaimed += resource.pageout_mapping(mut res, source.file_page)
		}
		source.close()
	}
	return reclaimed
}
