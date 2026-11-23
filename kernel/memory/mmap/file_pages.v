@[has_globals]
module mmap

import lib
import katomic
import memory
import resource

__global (
	file_globals &MmapRangeGlobal = unsafe { nil }
	truncate_globals &MmapRangeGlobal = unsafe { nil }
)

fn register_file_global(global &MmapRangeGlobal) {
	mut g := unsafe { global }
	if !g.tracked_file && g.truncation_inode == 0 { return }
	range_locals_lock.acquire()
	defer { range_locals_lock.release() }
	if g.file_registered { return }
	if g.truncation_inode != 0 {
		g.file_next = truncate_globals
		truncate_globals = g
	} else {
		g.file_next = file_globals
		file_globals = g
	}
	if g.file_next != unsafe { nil } { g.file_next.file_previous = g }
	g.file_registered = true
}

// Called when the final local is identified, under range_locals_lock, before
// shadow tables or the resource can be released.
fn unregister_file_global_locked(mut g MmapRangeGlobal) {
	if !g.file_registered { return }
	if g.file_previous != unsafe { nil } {
		g.file_previous.file_next = g.file_next
	} else if g.truncation_inode != 0 {
		truncate_globals = g.file_next
	} else {
		file_globals = g.file_next
	}
	if g.file_next != unsafe { nil } { g.file_next.file_previous = g.file_previous }
	g.file_registered = false
}

// Hold the inode lock across revocation and the shrink that follows it.
// VM operations can enter the inode in the opposite order, so reverse locks
// are acquired without waiting. Failure changes neither PTEs nor generations.
pub fn try_truncate_file_mappings(box voidptr, cutoff u64) bool {
	if !range_locals_lock.test_and_acquire() { return false }
	defer { range_locals_lock.release() }
	mut held := &memory.Pagemap(unsafe { nil })
	defer {
		for held != unsafe { nil } {
			next := held.truncate_next
			last := voidptr(next) == voidptr(held)
			held.truncate_next = unsafe { nil }
			held.l.release()
			if last { break }
			held = next
		}
	}
	for g := truncate_globals; g != unsafe { nil }; g = g.file_next {
		if voidptr(g.resource) != box { continue }
		begin, end := file_truncation_span(g, cutoff)
		if begin == end { continue }
		for local in g.locals {
			mut pm := local.pagemap
			if pm.truncate_next != unsafe { nil } { continue }
			if !pm.l.test_and_acquire() { return false }
			pm.truncate_next = if held == unsafe { nil } { pm } else { held }
			held = pm
		}
	}
	for g := truncate_globals; g != unsafe { nil }; g = g.file_next {
		if voidptr(g.resource) != box { continue }
		begin, end := file_truncation_span(g, cutoff)
		if begin != end { truncate_file_span_unlocked(mut g, begin, end) }
	}
	return true
}

fn file_truncation_span(g &MmapRangeGlobal, cutoff u64) (u64, u64) {
	if g.segmented_file && g.file_data_length == 0 { return g.base, g.base }
	offset := u64(g.offset)
	// ELF pages supplied entirely by the anonymous BSS have no file offset.
	first := if g.segmented_file { lib.align_down(g.file_data_start, page_size) } else { u64(0) }
	last := if g.segmented_file {
		lib.align_up(g.file_data_start + g.file_data_length, page_size)
	} else {
		g.length
	}
	end := g.base + last
	delta := if cutoff > offset { cutoff - offset } else { u64(0) }
	return g.base + min_u64(max_u64(delta, first), last), end
}

fn truncate_file_span_unlocked(mut g MmapRangeGlobal, begin u64, end u64) {
	// The registry and all local map locks are held. No other path can
	// enter this shadow, even for a range below the truncation boundary.
	g.shadow_pagemap.l.acquire()
	defer { g.shadow_pagemap.l.release() }
	for mut local in g.locals {
		base := shadow_begin(local)
		first := max_u64(begin, base)
		last := min_u64(end, base + local.length)
		if first >= last { continue }
		// A source that already obtained an old frame cannot install it
		// after this point, even if the file is grown again before it returns.
		local.generation = katomic.inc(mut &next_range_generation)
		mut pm := local.pagemap
		limit := local.base + (last - base)
		mut page := pm.next_present(local.base + (first - base), limit)
		for page < limit {
			pm.unmap_page_unlocked(page) or { panic('truncate: local file PTE disappeared') }
			page = pm.next_present(page + page_size, limit)
		}
	}
	if g.shadow_pagemap.top_level == unsafe { nil } { return }
	// Shared tmpfs PTEs borrow from the inode. Private shadows own one
	// PMM reference each, for either a cache frame or a detached COW copy.
	is_private := g.locals[0].flags & map_shared == 0
	mut page := g.shadow_pagemap.next_present(begin, end)
	for page < end {
		physical := g.shadow_pagemap.virt2phys(page) or { panic('truncate: missing shadow frame') }
		g.shadow_pagemap.unmap_page_unlocked(page) or { panic('truncate: shadow file PTE disappeared') }
		if is_private { memory.pmm_free(voidptr(physical), 1) }
		page = g.shadow_pagemap.next_present(page + page_size, end)
	}
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
