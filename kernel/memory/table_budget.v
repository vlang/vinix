// SPDX-License-Identifier: GPL-2.0-or-later
module memory

import kbudget
import errno

fn user_table_levels() int {
	$if aarch64 {
		return 3
	}
	$if amd64 {
		return if la57 { 5 } else { 4 }
	}
}

fn table_page_count(table &u64, levels int, root bool) u64 {
	if table == unsafe { nil } { return 0 }
	mut count := u64(1)
	if levels == 1 { return count }
	mut entries := page_size / 8
	$if amd64 {
		if root { entries = 256 }
	}
	for i := u64(0); i < entries; i++ {
		entry := unsafe { *(&u64(u64(table) + higher_half + i * 8)) }
		if entry & 1 != 0 {
			count += table_page_count(voidptr(entry & pte_flags_mask), levels - 1, false)
		}
	}
	return count
}

// Adopt an address space built before its Process existed, or initialize an
// empty private shadow. Only unattached or locked page maps are passed here.
pub fn account_pagemap(mut pagemap Pagemap, owner kbudget.Owner) ? {
	if owner.slot == 0 || pagemap.kernel_charge.owner.slot != 0 { return }
	bytes := table_page_count(pagemap.top_level, user_table_levels(), true) * page_size + 128
	pagemap.kernel_charge = kbudget.reserve(owner, .mapping, bytes) or {
		errno.set(errno.enomem)
		return none
	}
	pagemap.kernel_owner = owner
}

fn reserve_table_page(mut pagemap Pagemap) bool {
	if pagemap.kernel_owner.slot == 0 { return true }
	account_pagemap(mut pagemap, pagemap.kernel_owner) or { return false }
	if !kbudget.grow(mut pagemap.kernel_charge, page_size) {
		errno.set(errno.enomem)
		return false
	}
	// Never invoke the OOM killer under the page-map lock. A fault/syscall
	// retries or settles physical exhaustion once those locks are unwound.
	if !user_room(1) {
		kbudget.shrink(mut pagemap.kernel_charge, page_size)
		return false
	}
	return true
}

fn release_table_page(mut pagemap Pagemap) {
	if pagemap.kernel_charge.owner.slot != 0 {
		kbudget.shrink(mut pagemap.kernel_charge, page_size)
	}
}

pub fn ensure_table_root(mut pagemap Pagemap) ? {
	if pagemap.top_level != unsafe { nil } { return }
	if !reserve_table_page(mut pagemap) { return none }
	root := pmm_alloc_fallible(1)
	if root == unsafe { nil } {
		release_table_page(mut pagemap)
		errno.set(errno.enomem)
		return none
	}
	pagemap.top_level = root
}

fn dispose_table(table &u64, levels int, root bool) {
	if table == unsafe { nil } { return }
	if levels > 1 {
		mut entries := page_size / 8
		$if amd64 {
			if root { entries = 256 }
		}
		for i := u64(0); i < entries; i++ {
			entry := unsafe { *(&u64(u64(table) + higher_half + i * 8)) }
			if entry & 1 != 0 { dispose_table(voidptr(entry & pte_flags_mask), levels - 1, false) }
		}
	}
	pmm_free(table, 1)
}

// The address space is detached and every data leaf has been unmapped. Walk
// any empty tables left by a failed allocation, in addition to its root.
pub fn dispose_pagemap_tables(mut pagemap Pagemap) {
	dispose_table(pagemap.top_level, user_table_levels(), true)
	pagemap.top_level = unsafe { nil }
	kbudget.release(pagemap.kernel_charge)
	pagemap.kernel_charge = kbudget.Charge{}
}
