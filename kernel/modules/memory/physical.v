module memory

import lib
import stivale2
import klock

__global (
	pmm_lock klock.Lock
	pmm_bitmap lib.Bitmap
	pmm_avl_page_count u64
	pmm_last_used_index u64
	free_pages u64
)

pub fn print_free(s charptr) {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	C.printf(c'pmm: Free pages: %llu (%s)\n', free_pages, s)
}

pub fn pmm_init(memmap &stivale2.MemmapTag) {
	unsafe {
		mut highest_address := u64(0)
		mut entries := &memmap.entries

		// Calculate how big the memory map needs to be.
		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].entry_type != u32(stivale2.MemmapEntryType.usable)
			&& entries[i].entry_type != u32(stivale2.MemmapEntryType.bootloader_reclaimable) {
				continue
			}
			top := entries[i].base + entries[i].length
			if top > highest_address {
				highest_address = top
			}
		}

		// Calculate the needed size for the bitmap in bytes and align it to page size.
		pmm_avl_page_count = highest_address / page_size
		bitmap_size := lib.align_up(pmm_avl_page_count / 8, page_size)

		// Find a hole for the bitmap in the memory map.
		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].entry_type != u32(stivale2.MemmapEntryType.usable) {
				continue
			}
			if entries[i].length >= bitmap_size {
				pmm_bitmap = lib.Bitmap(entries[i].base + higher_half)

				// Initialise entire bitmap to 1 (non-free)
				C.memset(pmm_bitmap, 0xff, bitmap_size)

				entries[i].length -= bitmap_size
				entries[i].base += bitmap_size

				break
			}
		}

		// Populate free bitmap entries according to the memory map.
		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].entry_type != u32(stivale2.MemmapEntryType.usable) {
				continue
			}

			for j := u64(0); j < entries[i].length; j += page_size {
				free_pages++
				lib.bitreset(pmm_bitmap, (entries[i].base + j) / page_size)
			}
		}
	}

	print_free(c'')
}

fn inner_alloc(count u64, limit u64) voidptr {
	mut p := 0
	for pmm_last_used_index < limit {
		if !lib.bittest(pmm_bitmap, pmm_last_used_index) {
			pmm_last_used_index++
			p++
			if p == count {
				page := pmm_last_used_index - count
				for i := page; i < pmm_last_used_index; i++ {
					lib.bitset(pmm_bitmap, i)
				}
				return voidptr(page * page_size)
			}
		} else {
			pmm_last_used_index++
			p = 0
		}
	}
	return 0
}

pub fn pmm_alloc_nozero(count u64) voidptr {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}

	last := pmm_last_used_index
	mut ret := inner_alloc(count, pmm_avl_page_count)
	if ret == 0 {
		pmm_last_used_index = 0
		ret = inner_alloc(count, last)
		if ret == 0 {
			lib.kpanic(c'Out of memory')
		}
	}

	free_pages -= count

	return ret
}

pub fn pmm_alloc(count u64) voidptr {
	ret := pmm_alloc_nozero(count)

	// We always zero out memory for security reasons
	unsafe {
		mut ptr := &u64(u64(ret) + higher_half)
		for i := u64(0); i < (count * page_size) / 8; i++ {
			ptr[i] = 0
		}
	}

	return ret
}

pub fn pmm_free(ptr voidptr, count u64) {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	page := u64(ptr) / page_size
	for i := page; i < page + count; i++ {
		lib.bitreset(pmm_bitmap, i)
	}
	free_pages += count
}

__global (
	kernel_alloc_base = u64(0xfffff00000000000)
)

const kernel_alloc_spacing = u64(0x1000000)

pub fn free(ptr voidptr) {
	realloc(ptr, 0)
}

pub fn malloc(size u64) voidptr {
	return realloc(voidptr(0), size)
}

pub fn realloc(ptr voidptr, new_size u64) voidptr {
	if vmm_initialised == false {
		lib.kpanic(c'realloc: No realloc() before VMM')
	}

	if new_size > (kernel_alloc_spacing - page_size) {
		lib.kpanic(c'realloc: Allocation too large')
	}

	new_page_count := lib.div_roundup(new_size, page_size)

	virt_base := if ptr == 0 {
		if new_size == 0 {
			return 0
		}
		new_virt_base := kernel_alloc_base
		kernel_alloc_base += kernel_alloc_spacing
		new_virt_base
	} else {
		u64(ptr)
	}

	mut old_page_count := u64(0)
	for p := virt_base; ; old_page_count++ {
		kernel_pagemap.virt2phys(p) or {
			break
		}
		p += page_size
	}

	mut pages_diff := i64(new_page_count) - i64(old_page_count)

	if pages_diff < 0 {
		// Free pages_diff amount of pages starting by the end of this mapping
		pages_diff = -pages_diff
		mut cur_page := (virt_base + old_page_count * page_size) - page_size
		for i := i64(0); i < pages_diff; i++ {
			mut pte := kernel_pagemap.virt2pte(cur_page, false) or {
				lib.kpanic(c'realloc: virt2pte() failure (2)')
			}
			if unsafe { pte[0] } & 1 == 0 {
				lib.kpanic(c'realloc: A page that should be mapped is not')
			}
			phys := (unsafe { pte[0] } & ~u64(0xfff)) & ~(u64(1) << 63)
			pmm_free(voidptr(phys), 1)
			unsafe { pte[0] = 0 }
			cur_page -= page_size
		}
		tlb_shootdown()
	} else if pages_diff > 0 {
		// Allocate pages_diff amount of pages starting by the end of this mapping
		mut cur_page := virt_base + old_page_count * page_size
		for i := i64(0); i < pages_diff; i++ {
			phys := pmm_alloc(1)
			kernel_pagemap.map_page(cur_page, phys, 0x03) or {
				lib.kpanic(c'realloc: map_page() failure')
			}
			cur_page += page_size
		}
	}

	// Check if we acted as free()
	if new_size == 0 {
		return 0
	}

	return voidptr(virt_base)
}
