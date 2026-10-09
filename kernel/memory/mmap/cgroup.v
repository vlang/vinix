// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import memory
import pager

pub struct AnonymousUsage {
pub mut:
	resident u64
	paged u64
}

// Count committed objects rather than VM reservations or visible PTEs.
// PROT_NONE still owns pages, and pageout must not hide them from a quota.
// Resident COW frames and nonresident fork backings each count their share;
// shared objects also divide by the aliases covering this particular page.
// A busy address space reports unavailable, never a misleading zero.
pub fn anonymous_usage(_pagemap &memory.Pagemap) ?AnonymousUsage {
	mut pagemap := unsafe { _pagemap }
	if pagemap == unsafe { nil } { return AnonymousUsage{} }
	if !pagemap.l.test_and_acquire() { return none }
	defer { pagemap.l.release() }
	range_locals_lock.acquire()
	defer { range_locals_lock.release() }
	mut usage := AnonymousUsage{}
	for pointer in pagemap.mmap_ranges {
		local := unsafe { &MmapRangeLocal(pointer) }
		if local == unsafe { nil } || local.flags & map_anonymous == 0 { continue }
		mut global := local.global
		global.shadow_pagemap.l.acquire()
		begin := shadow_begin(local)
		end := begin + local.length
		mut cursor := begin
		for global.shadow_pagemap.top_level != unsafe { nil } && cursor < end {
			page := global.shadow_pagemap.next_present(cursor, end)
			if page == end { break }
			cursor = page + page_size
			physical := global.shadow_pagemap.virt2phys(page) or { continue }
			refs := memory.pmm_refcount_unlocked(voidptr(physical))
			owners := covered_aliases(global, page) * if refs > 0 { u64(refs) } else { u64(1) }
			usage.resident += (page_size + owners - 1) / owners
		}
		cursor = begin
		for cursor < end {
			node := paged_lower(global.paged_pages, cursor)
			if node == unsafe { nil } || node.page >= end { break }
			cursor = node.page + page_size
			owners := covered_aliases(global, node.page) * pager.mapping_sharers(node.backing)
			if owners != 0 { usage.paged += (page_size + owners - 1) / owners }
		}
		global.shadow_pagemap.l.release()
	}
	return usage
}

// range_locals_lock is held, so mappings cannot disappear during the count.
fn covered_aliases(global &MmapRangeGlobal, page u64) u64 {
	mut aliases := u64(0)
	for local in global.locals {
		if shadow_covered(local, page) { aliases++ }
	}
	return if aliases == 0 { u64(1) } else { aliases }
}
