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
	found := inner_alloc_range(count, 1, limit)
	if found == unsafe { nil } {
		return 0
	}
	free_pages -= count
	lowmem_base = u64(found)
	lowmem_pages = count
	return lowmem_base
}

// The pages reserve_low_pages() took: their address and how many, or 0, 0.
pub fn low_pages() (u64, u64) {
	return lowmem_base, lowmem_pages
}
