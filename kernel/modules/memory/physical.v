module memory

import lib
import stivale2
import klock

__global (
	pmm_lock klock.Lock
	pmm_bitmap = voidptr(0)
	pmm_avl_page_count = u64(0)
	pmm_last_used_index = u64(0)
	free_pages = u64(0)
)

pub fn print_free() {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	C.printf(c'pmm: Free pages: %llu\n', free_pages)
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
				pmm_bitmap = voidptr(entries[i].base + higher_half)

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

	print_free()
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
			lib.kpanic(0, c'Out of memory')
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

struct MallocMetadata {
mut:
	pages u64
	size  u64
}

pub fn free(ptr voidptr) {
	if ptr == voidptr(0) {
		return
	}

	metadata := &MallocMetadata(u64(ptr) - page_size)

	pmm_free(voidptr(u64(metadata) - higher_half), metadata.pages + 1)
}

pub fn malloc(size u64) voidptr {
	page_count := lib.div_roundup(size, page_size)

	ptr := pmm_alloc(page_count + 1)

	if ptr == 0 {
		return 0
	}

	mut metadata := &MallocMetadata(u64(ptr) + higher_half)

	metadata.pages = page_count
	metadata.size = size

	return voidptr(u64(ptr) + higher_half + page_size)
}

pub fn realloc(ptr voidptr, new_size u64) voidptr {
	if ptr == 0 {
		return malloc(new_size)
	}

	mut metadata := &MallocMetadata(u64(ptr) - page_size)

	if lib.div_roundup(metadata.size, page_size) == lib.div_roundup(new_size, page_size) {
		metadata.size = new_size
		return ptr
	}

	new_ptr := unsafe { C.malloc(new_size) }
	if new_ptr == 0 {
		return 0
	}

	if metadata.size > new_size {
		unsafe { C.memcpy(new_ptr, ptr, new_size) }
	} else {
		unsafe { C.memcpy(new_ptr, ptr, metadata.size) }
	}

	C.free(ptr)

	return new_ptr
}
