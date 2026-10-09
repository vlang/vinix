// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import katomic
import lib
import memory
import pager
import proc
import sched
import resource

// Nonresident pages use an intrusive treap. Large sparse reservations do not
// allocate per-page metadata, and neither faults nor fork scan all swapped
// pages. Nodes belong to the global; backing references also survive I/O.
struct PagedPage {
mut:
	page     u64
	priority u64
	backing  &pager.Backing = unsafe { nil }
	left     &PagedPage     = unsafe { nil }
	right    &PagedPage     = unsafe { nil }
}

fn paged_find(root &PagedPage, page u64) &PagedPage {
	mut node := unsafe { root }
	for node != unsafe { nil } {
		if node.page == page { return node }
		node = if page < node.page { node.left } else { node.right }
	}
	return unsafe { nil }
}

fn paged_lower(root &PagedPage, page u64) &PagedPage {
	mut node := unsafe { root }
	mut found := unsafe { &PagedPage(nil) }
	for node != unsafe { nil } {
		if node.page >= page {
			found = node
			node = node.left
		} else {
			node = node.right
		}
	}
	return found
}

fn paged_merge(_left &PagedPage, _right &PagedPage) &PagedPage {
	mut left := unsafe { _left }
	mut right := unsafe { _right }
	if left == unsafe { nil } { return right }
	if right == unsafe { nil } { return left }
	if left.priority < right.priority {
		left.right = paged_merge(left.right, right)
		return left
	}
	right.left = paged_merge(left, right.left)
	return right
}

fn paged_insert(_root &PagedPage, _node &PagedPage) &PagedPage {
	mut root := unsafe { _root }
	mut node := unsafe { _node }
	if root == unsafe { nil } { return node }
	if node.page < root.page {
		root.left = paged_insert(root.left, node)
		if root.left.priority < root.priority {
			mut next := root.left
			root.left = next.right
			next.right = root
			return next
		}
	} else {
		root.right = paged_insert(root.right, node)
		if root.right.priority < root.priority {
			mut next := root.right
			root.right = next.left
			next.left = root
			return next
		}
	}
	return root
}

fn paged_remove(_root &PagedPage, page u64) &PagedPage {
	mut root := unsafe { _root }
	if root == unsafe { nil } { return root }
	if page < root.page {
		root.left = paged_remove(root.left, page)
	} else if page > root.page {
		root.right = paged_remove(root.right, page)
	} else {
		return paged_merge(root.left, root.right)
	}
	return root
}

// Shadow addresses name object offsets, independently of a local mapping's
// virtual address. Moving a shared mapping therefore preserves fork aliases.
fn shadow_address(local &MmapRangeLocal, virt u64) u64 {
	return local.global.base + u64(local.offset - local.global.offset) + virt - local.base
}

fn shadow_begin(local &MmapRangeLocal) u64 {
	return shadow_address(local, local.base)
}

fn shadow_covered(local &MmapRangeLocal, page u64) bool {
	begin := shadow_begin(local)
	return page >= begin && page - begin < local.length
}

// Called with the shadow lock held. Sources retain the backing independently
// before dropping any VM lock; no source borrows this node or its global.
fn forget_paged_locked(mut global MmapRangeGlobal, page u64) {
	node := paged_find(global.paged_pages, page)
	if node == unsafe { nil } { return }
	global.paged_pages = paged_remove(global.paged_pages, page)
	pager.release(node.backing)
	memory.free(node)
}

fn reclaim_uncovered_paged_locked(mut global MmapRangeGlobal, begin u64, end u64) {
	global.shadow_pagemap.l.acquire()
	mut cursor := begin
	for cursor < end {
		node := paged_lower(global.paged_pages, cursor)
		if node == unsafe { nil } || node.page >= end { break }
		page := node.page
		cursor = page + page_size
		mut covered := false
		for local in global.locals {
			if shadow_covered(local, page) {
				covered = true
				break
			}
		}
		if !covered { forget_paged_locked(mut global, page) }
	}
	global.shadow_pagemap.l.release()
}

fn release_paged_pages(mut global MmapRangeGlobal) {
	for global.paged_pages != unsafe { nil } {
		forget_paged_locked(mut global, global.paged_pages.page)
	}
}

fn fork_paged_span(global &MmapRangeGlobal, mut child MmapRangeGlobal, begin u64, end u64) {
	mut owner := unsafe { global }
	owner.shadow_pagemap.l.acquire()
	mut cursor := begin
	for cursor < end {
		node := paged_lower(owner.paged_pages, cursor)
		if node == unsafe { nil } || node.page >= end { break }
		pager.retain(node.backing)
		copy := &PagedPage{ page: node.page, priority: node.priority, backing: node.backing } @[freed]
		child.paged_pages = paged_insert(child.paged_pages, copy)
		cursor = node.page + page_size
	}
	owner.shadow_pagemap.l.release()
}

// The owner lock is held on entry and released on every path. Other aliases'
// locks are tried, never waited for, under range_locals_lock. This respects
// the existing pagemap -> locals lock order even when two sharers page out.
// All translations are synchronously revoked before the frame is read.
fn detach_page_unlocked(mut pagemap memory.Pagemap, virt u64) &pager.Backing {
	defer { pagemap.l.release() }
	local, _, _ := addr2range(&pagemap, virt) or { return unsafe { nil } }
	if (local.flags & map_anonymous == 0 && (!local.global.tracked_file || local.flags & map_shared != 0)) || local.flags & map_locked != 0
		|| local.immutable || pagemap.dying {
		return unsafe { nil }
	}
	mut global := local.global
	page := shadow_address(local, virt)
	range_locals_lock.acquire()
	defer { range_locals_lock.release() }
	global.shadow_pagemap.l.acquire()
	defer { global.shadow_pagemap.l.release() }
	if global.shadow_pagemap.top_level == unsafe { nil } { return unsafe { nil } }
	physical := global.shadow_pagemap.virt2phys(page) or { return unsafe { nil } }
	if local.flags & map_anonymous == 0 {
		mut res := global.resource
		file_page := u64(local.offset) / page_size + (virt - local.base) / page_size
		if !resource.uncached_mapping_page(mut res, file_page, voidptr(physical)) { return unsafe { nil } }
	}
	mut held := unsafe { [64]&memory.Pagemap{} }
	mut count := 0
	defer {
		for i in 0 .. count { held[i].l.release() }
	}
	for alias in global.locals {
		if !shadow_covered(alias, page) { continue }
		if alias.flags & map_locked != 0 || alias.immutable { return unsafe { nil } }
		mut other := alias.pagemap
		if voidptr(other) == voidptr(&pagemap) { continue }
		mut already := false
		for i in 0 .. count {
			if voidptr(held[i]) == voidptr(other) {
				already = true
				break
			}
		}
		if already { continue }
		if count == held.len || !other.l.test_and_acquire() { return unsafe { nil } }
		held[count] = other
		count++
	}
	// Check every resident alias before removing any, so an unexpected stale
	// descriptor never leads to saving one frame and discarding another.
	for alias in global.locals {
		if !shadow_covered(alias, page) { continue }
		address := alias.base + page - shadow_begin(alias)
		if phys := alias.pagemap.virt2phys(address) {
			if phys != physical { return unsafe { nil } }
		}
	}
	node := unsafe { &PagedPage(memory.malloc_packed_fallible(sizeof(PagedPage))) }
	if node == unsafe { nil } { return unsafe { nil } }
	backing := pager.detached(voidptr(physical))
	if backing == unsafe { nil } {
		memory.free(node)
		return unsafe { nil }
	}
	unsafe { *node = PagedPage{ page: page, priority: range_priority(page), backing: backing } }
	for alias in global.locals {
		if !shadow_covered(alias, page) { continue }
		address := alias.base + page - shadow_begin(alias)
		alias.pagemap.unmap_page_unlocked(address) or {}
	}
	global.shadow_pagemap.unmap_page_unlocked(page) or {
		// This page was present under its lock, so failure means corrupted
		// page tables, not an ordinary storage failure.
		panic('pageout: shadow page disappeared')
	}
	global.paged_pages = paged_insert(global.paged_pages, node)
	return backing
}

fn store_detached_page(pagemap &memory.Pagemap, virt u64, backing &pager.Backing) u64 {
	// The mapping may disappear while store runs; the completion/rollback
	// must own its own pin rather than rely on the tree entry surviving.
	pager.retain(backing)
	reclaimed := pager.store(backing)
	restore_failed_pageout(pagemap, virt, backing)
	pager.release(backing)
	return reclaimed
}

fn restore_failed_pageout(_pagemap &memory.Pagemap, virt u64, backing &pager.Backing) {
	physical := pager.fallback_frame(backing)
	if physical == unsafe { nil } { return }
	mut transferred := false
	defer { if !transferred { memory.pmm_free(physical, 1) } }
	mut pagemap := unsafe { _pagemap }
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	local, _, _ := addr2range(pagemap, virt) or { return }
	mut global := local.global
	page := shadow_address(local, virt)
	range_locals_lock.acquire()
	defer { range_locals_lock.release() }
	global.shadow_pagemap.l.acquire()
	defer { global.shadow_pagemap.l.release() }
	node := paged_find(global.paged_pages, page)
	if node == unsafe { nil } || voidptr(node.backing) != voidptr(backing) { return }
	mut held := unsafe { [64]&memory.Pagemap{} }
	mut count := 0
	defer { for i in 0 .. count { held[i].l.release() }
	 }
	for alias in global.locals {
		if !shadow_covered(alias, page) { continue }
		mut other := alias.pagemap
		if voidptr(other) == voidptr(pagemap) { continue }
		mut already := false
		for i in 0 .. count {
			if voidptr(held[i]) == voidptr(other) {
				already = true
				break
			}
		}
		if already { continue }
		if count == held.len || !other.l.test_and_acquire() { return }
		held[count] = other
		count++
	}
	global.shadow_pagemap.map_page_unlocked(page, u64(physical),
		memory.pte_present | memory.pte_writable | memory.pte_noexec) or { return }
	transferred = true
	for alias in global.locals {
		if !shadow_covered(alias, page) { continue }
		mut mutable_alias := unsafe { alias }
		if alias.flags & map_shared == 0 { mutable_alias.cow = true }
		if alias.prot & prot_exec != 0 { sync_new_code_page(physical) }
		address := alias.base + page - shadow_begin(alias)
		alias.pagemap.map_page_unlocked(address, u64(physical),
			page_table_flags(alias.prot, global.pte_extra, alias.flags & map_shared != 0)) or {}
	}
	forget_paged_locked(mut global, page)
}

pub fn pageout(pagemap &memory.Pagemap, address u64, length u64) u64 {
	mut map_ := unsafe { pagemap }
	mut reclaimed := u64(0)
	end := address + length
	mut cursor := address
	for cursor < end {
		map_.l.acquire()
		page := map_.next_present(cursor, end)
		if page == end {
			map_.l.release()
			break
		}
		cursor = page + page_size
		backing := detach_page_unlocked(mut map_, page)
		if backing != unsafe { nil } { reclaimed += store_detached_page(map_, page, backing) }
	}
	return reclaimed + pageout_file_span(pagemap, address, end)
}

__global (
	paging_registered      u32
	pageout_process_cursor = int(1)
)

fn register_paging() {
	if katomic.cas(mut &paging_registered, u32(0), u32(1)) {
		memory.register_anonymous_pageout(reclaim_anonymous)
	}
}

// Only a sleepable worker or OOM recovery calls this bridge. It retains each
// address space under the process table before dropping it; exec/exit waits
// for the same inspection references used by process_vm_*.
pub fn reclaim_anonymous(wanted u64, foreground bool) u64 {
	mut reclaimed := u64(0)
	mut visited := 0
	for visited < proc.max_pid && reclaimed < wanted {
		proc.lock_table()
		mut process := unsafe { &proc.Process(nil) }
		// Sparse PID tables must not cost one lock/IRQ pair per empty slot.
		// Keep each table-lock hold bounded while locating a live address space.
		for _ in 0 .. 256 {
			if visited == proc.max_pid { break }
			pageout_process_cursor = (pageout_process_cursor + 1) % proc.max_pid
			visited++
			candidate := proc.process_at(pageout_process_cursor)
			if candidate != unsafe { nil } && !candidate.exiting && candidate.pagemap != unsafe { nil } {
				process = candidate
				break
			}
		}
		if process == unsafe { nil } {
			proc.unlock_table()
			continue
		}
		mut pagemap := process.pagemap
		if !pagemap.l.test_and_acquire() {
			proc.unlock_table()
			continue
		}
		pagemap.inspection_refs++
		pagemap.l.release()
		proc.unlock_table()
		pagemap.l.acquire()
		// Background work bounds scanning as well as successful eviction.
		// Foreground recovery inspects a complete cycle before reporting empty.
		mut scanned := u64(0)
		mut wrapped := false
		// A full pressure target may need more than 256 native 4 KiB pages.
		// Extra background scans cover skipped/fork-shared frames, with a fixed
		// upper bound. Foreground lock-held chunks are bounded below instead.
		scan_budget := if foreground { u64(-1) } else if wanted > 2048 { u64(4096) } else { max_u64(256, wanted * 2) }
		for scanned < scan_budget && reclaimed < wanted {
			// Before OOM, a budget-sized locked/nonanonymous prefix is not
			// evidence that no frames can be reclaimed. Foreground recovery
			// completes a cycle, yielding between bounded lock-held chunks.
			if foreground && scanned != 0 && scanned % 256 == 0 {
				pagemap.l.release()
				sched.yield(true)
				pagemap.l.acquire()
			}
			if pagemap.dying { break }
			mut local := range_floor(pagemap, pagemap.pageout_cursor)
			if local == unsafe { nil } || pagemap.pageout_cursor >= local.base + local.length {
				local = range_lower_bound(pagemap, pagemap.pageout_cursor)
			}
			if local == unsafe { nil } {
				pagemap.pageout_cursor = 0
				// Reaching the end is not evidence that the address space has
				// no reclaimable frames. Foreground OOM recovery must inspect
				// earlier addresses in this same pass rather than fail empty.
				if wrapped { break }
				wrapped = true
				if range_lower_bound(pagemap, 0) == unsafe { nil } { break }
				continue
			}
			begin := if pagemap.pageout_cursor > local.base {
				pagemap.pageout_cursor
			} else {
				local.base
			}
			end := local.base + local.length
			if (local.flags & map_anonymous == 0 && (!local.global.tracked_file || local.flags & map_shared != 0)) || local.flags & map_locked != 0 || local.immutable {
				pagemap.pageout_cursor = end
				scanned++
				continue
			}
			page := pagemap.next_present(begin, end)
			pagemap.pageout_cursor = if page == end { end } else { page + page_size }
			scanned++
			if page == end { continue }
			backing := detach_page_unlocked(mut pagemap, page)
			if backing != unsafe { nil } {
				reclaimed += store_detached_page(pagemap, page, backing)
			}
			pagemap.l.acquire()
		}
		pagemap.l.release()
		memory.release_inspection(pagemap)
	}
	return reclaimed
}

// Shared anonymous moves keep the object and its offsets. Copying into a new
// anonymous object would detach the moved mapping from its fork siblings.
fn remap_shared_anonymous(mut pagemap memory.Pagemap, old_address u64, old_length u64,
	new_length u64, flags u64, new_address u64, serial u64) ?u64 {
	pagemap.l.acquire()
	mut held := true
	defer { if held { pagemap.l.release() } }
	local, _, first_page := addr2range(&pagemap, old_address) or {
		errno.set(errno.efault)
		return none
	}
	if local.global.serial != serial || !compatible_remap_span_unlocked(&pagemap,
		old_address, old_length, local, first_page) {
		errno.set(errno.efault)
		return none
	}
	mut global := local.global
	mut process := proc.current_thread().process
	mut base := new_address
	if flags & mremap_fixed == 0 {
		base = find_free_base_unlocked(&pagemap, process.mmap_anon_non_fixed_base, new_length)?
	}
	if base == 0 || base >= memory.user_address_limit() || new_length > memory.user_address_limit() - base {
		errno.set(errno.enomem)
		return none
	}
	if immutable_overlap_unlocked(&pagemap, base, new_length) {
		errno.set(errno.eperm)
		return none
	}
	if !mapping_fits_address_limit(&pagemap, process, base, new_length, flags & mremap_fixed != 0,
		new_length, old_length) {
		errno.set(errno.enomem)
		return none
	}
	mut moved := &MmapRangeLocal{
		pagemap:      unsafe { &pagemap }
		global:       global
		base:         base
		length:       new_length
		offset:       local.offset + i64(old_address - local.base)
		prot:         local.prot
		flags:        local.flags
		dont_fork:    local.dont_fork
		wipe_on_fork: local.wipe_on_fork
	} @[freed]
	if !prepare_mapping_lock_unlocked(&pagemap, process, moved, flags & mremap_fixed != 0,
		old_length, MmapOptions{ credit_base: old_address, credit_serial: serial }) {
		unsafe { free(moved) }
		return none
	}
	if flags & mremap_fixed != 0 {
		munmap_unlocked(mut pagemap, voidptr(base), new_length) or {
			unsafe { free(moved) }
			return none
		}
	}
	range_locals_lock.acquire()
	global.length = max_u64(global.length, u64(moved.offset - global.offset) + new_length)
	global.add_local(moved)
	range_locals_lock.release()
	insert_range_unlocked(mut pagemap, moved)
	if moved.flags & map_locked != 0 {
		protection := moved.prot
		pagemap.l.release()
		held = false
		populate_missing_pages(mut pagemap, base, new_length, protection, false) or {
			failure := errno.get()
			unmap_created_range(mut pagemap, base, new_length, serial)
			errno.set(failure)
			return none
		}
		pagemap.l.acquire()
		held = true
		if !remap_span_unlocked(&pagemap, old_address, old_length, serial, true)
			|| !remap_span_unlocked(&pagemap, base, new_length, serial, true) {
			failure := errno.get()
			pagemap.l.release()
			held = false
			unmap_created_range(mut pagemap, base, new_length, serial)
			errno.set(failure)
			return none
		}
	}
	munmap_unlocked(mut pagemap, voidptr(old_address), old_length)?
	if flags & mremap_fixed == 0 {
		process.mmap_anon_non_fixed_base = base + new_length + page_size
	}
	return base
}

fn max_u64(left u64, right u64) u64 { return if left > right { left } else { right } }
