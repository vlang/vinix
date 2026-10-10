// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Memory below 1 MiB that the kernel keeps for itself.
//
// A processor that starts in real mode -- after a suspend to RAM, or when it
// is sent a startup IPI -- can only begin in the first megabyte, so the code
// it begins with has to live there (x86/wake). The boot loader's memory map
// lists what is left of that megabyte as ordinary usable memory, and the
// allocator hands out the lowest free page first: unless the pages are taken
// before the first allocation, they are the first to go, to whoever asks.
@[has_globals]
module memory

import lib

pub const low_memory_limit = u64(0x100000)

__global (
	lowmem_base  u64
	lowmem_pages u64
)

// Take `count` pages in one run below 1 MiB out of the allocator for good.
// Called once, straight after pmm_init(). Returns their physical address, or
// 0 when the first megabyte has no such run -- the caller then does without.
// Page 0 is never part of it: an address of 0 has to stay meaning "none".
pub fn reserve_low_pages(count u64) u64 {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	if lowmem_base != 0 || count == 0 {
		return lowmem_base
	}
	mut limit := low_memory_limit / page_size
	if limit > pmm_avl_page_count {
		limit = pmm_avl_page_count
	}
	if limit < count + 1 {
		return 0
	}
	// The highest run there is. The bottom of the megabyte is where firmware
	// keeps its own data, and some firmware writes there on its way back
	// from a sleep, whatever the memory map says about who owns it.
	for first := limit - count; first >= 1; first-- {
		mut free := true
		for page := first; page < first + count; page++ {
			if lib.bittest(pmm_bitmap, page) {
				free = false
				break
			}
		}
		if !free {
			continue
		}
		for page := first; page < first + count; page++ {
			lib.bitset(pmm_bitmap, page)
			unsafe {
				(&u32(pmm_refcounts))[page] = 1
			}
		}
		free_pages -= count
		lowmem_base = first * page_size
		lowmem_pages = count
		return lowmem_base
	}
	return 0
}

// The pages reserve_low_pages() took: their address and how many, or 0, 0.
pub fn low_pages() (u64, u64) {
	return lowmem_base, lowmem_pages
}
