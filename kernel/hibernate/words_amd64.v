// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A table of 64-bit words kept in single pages.
//
// Hibernation keeps a number for every page it saves and a bit for every
// frame of the machine: megabytes, on a machine with much memory, wanted at
// the moment its memory is as scattered as it will ever be. A table that
// needs one run of pages that long is a table that cannot be had; this one is
// a tree of single pages, three deep, all of them allocated when it is made
// so that using it never allocates -- it is filled in with interrupts off.
//
// A leaf page holds 512 words; a directory page names 512 leaves; the root
// names 512 directories: 134 million words, which as frame numbers is 512 GiB
// of saved pages.
module hibernate

import memory

const words_per_page = u64(512)
const max_words = words_per_page * words_per_page * words_per_page

struct Words {
mut:
	// The root page, by physical address; 0 for a table that is not there.
	root  u64
	count u64
}

@[inline]
fn page_of(phys u64) &u64 {
	return unsafe { &u64(phys + higher_half) }
}

fn one_page() u64 {
	return u64(memory.pmm_alloc_fallible(1))
}

// A table of `count` words, all zero. None when there is no memory for it,
// with nothing left allocated.
fn words_new(count u64) ?Words {
	if count == 0 || count > max_words {
		return none
	}
	root := one_page()
	if root == 0 {
		return none
	}
	mut table := Words{
		root:  root
		count: count
	}
	leaves := (count + words_per_page - 1) / words_per_page
	for leaf in u64(0) .. leaves {
		mut directories := page_of(root)
		slot := leaf / words_per_page
		if unsafe { directories[slot] } == 0 {
			directory := one_page()
			if directory == 0 {
				table.release()
				return none
			}
			unsafe {
				directories[slot] = directory
			}
		}
		page := one_page()
		if page == 0 {
			table.release()
			return none
		}
		unsafe {
			mut directory := page_of(directories[slot])
			directory[leaf % words_per_page] = page
		}
	}
	return table
}

// The physical address of the page that holds words 512 * `leaf` onward.
fn (table &Words) leaf_page(leaf u64) u64 {
	directory := unsafe { page_of(table.root)[leaf / words_per_page] }
	return unsafe { page_of(directory)[leaf % words_per_page] }
}

@[inline]
fn (table &Words) slot(index u64) &u64 {
	page := table.leaf_page(index / words_per_page)
	return unsafe { &u64(page + higher_half + (index % words_per_page) * 8) }
}

@[inline]
fn (table &Words) get(index u64) u64 {
	return unsafe { *table.slot(index) }
}

@[inline]
fn (mut table Words) set(index u64, value u64) {
	mut slot := table.slot(index)
	unsafe {
		*slot = value
	}
}

// The table as bits, 64 to a word.
@[inline]
fn (table &Words) bit(index u64) bool {
	return table.get(index / 64) & (u64(1) << (index % 64)) != 0
}

@[inline]
fn (mut table Words) set_bit(index u64) {
	mut slot := table.slot(index / 64)
	unsafe {
		*slot |= u64(1) << (index % 64)
	}
}

// How many pages the table itself takes.
fn (table &Words) pages() u64 {
	if table.root == 0 {
		return 0
	}
	leaves := (table.count + words_per_page - 1) / words_per_page
	return 1 + (leaves + words_per_page - 1) / words_per_page + leaves
}

// Give every page back. The table is then one that is not there, and may be
// released again.
fn (mut table Words) release() {
	if table.root == 0 {
		return
	}
	directories := page_of(table.root)
	for slot in u64(0) .. words_per_page {
		directory := unsafe { directories[slot] }
		if directory == 0 {
			continue
		}
		leaves := page_of(directory)
		for index in u64(0) .. words_per_page {
			page := unsafe { leaves[index] }
			if page != 0 {
				memory.pmm_free(voidptr(page), 1)
			}
		}
		memory.pmm_free(voidptr(directory), 1)
	}
	memory.pmm_free(voidptr(table.root), 1)
	table.root = 0
	table.count = 0
}
