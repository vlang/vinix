module memory

import lib
import stivale2

__global (
	pmm_bitmap lib.Bitmap
)

__global (
	pmm_avl_page_count u64
)

__global (
	pmm_last_used_index u64
)

pub fn physical_init(memmap &stivale2.MemmapTag) {
	// Calculate the highest and lowest boundaries.
	mut highest_address := u64(0)
	unsafe {
		mut entries := &memmap.entries

		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].entry_type != u32(stivale2.MemmapEntryType.usable)
				&& entries[i].entry_type != u32(stivale2.MemmapEntryType.bootloader_reclaimable)
				&& entries[i].entry_type != u32(stivale2.MemmapEntryType.acpi_reclaimable) {
				continue
			}
			top := entries[i].base + entries[i].length
			if top > highest_address {
				highest_address = top
			}
		}

		// Calculate the needed size for the bitmap in bytes
		pmm_avl_page_count = highest_address / page_size
		bitmap_size := pmm_avl_page_count / 8

		// Find a hole for the bitmap in the memory map.
		mut bitmap_entry := 0
		mut bitmap_entry_base := u64(0)
		mut bitmap_entry_size := u64(0)
		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].entry_type != u32(stivale2.MemmapEntryType.usable) {
				continue
			}
			if entries[i].length >= bitmap_size {
				bitmap_entry = i
				bitmap_entry_base = entries[i].base + bitmap_size
				bitmap_entry_size = entries[i].length - bitmap_size
				pmm_bitmap = lib.Bitmap(entries[i].base)
				break
			}
		}

		// Fill the bitmap by first clearing and then populating with the memmap
		for i := 0; i < pmm_avl_page_count; i++ {
			lib.bitset(pmm_bitmap, u64(i))
		}

		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].entry_type != u32(stivale2.MemmapEntryType.usable) {
				continue
			}
			base, length := if i == bitmap_entry {
				bitmap_entry_base, bitmap_entry_size
			} else {
				entries[i].base, entries[i].length
			}
			for j := u64(0); j < length; j += page_size {
				lib.bitreset(pmm_bitmap, (base + j) / page_size)
			}
		}
	}
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

pub fn pmm_alloc(count u64) voidptr {
	last := pmm_last_used_index
	mut ret := inner_alloc(count, pmm_avl_page_count)
	if ret == 0 {
		pmm_last_used_index = 0
		ret = inner_alloc(count, last)
		if ret == 0 {
			return 0
		}
	}

	// We always zero out memory for security reasons
	unsafe {
		mut ptr := &u64(ret)
		for i := u64(0); i < (count * page_size) / 8; i++ {
			ptr[i] = 0
		}
	}
	return ret
}

pub fn pmm_free(ptr voidptr, count u64) {
	page := u64(ptr) / page_size
	for i := page; i < page + count; i++ {
		lib.bitreset(pmm_bitmap, i)
	}
}

struct MallocMetadata {
mut:
	pages u64
	size  u64
}

pub fn free(ptr voidptr) {
	metadata_ptr := unsafe { &char(ptr) - page_size }
	metadata := &MallocMetadata(metadata_ptr)

	pmm_free(unsafe { metadata_ptr - higher_half }, metadata.pages + 1)
}

pub fn malloc(size u64) voidptr {
	page_count := lib.div_roundup(size, page_size)

	ptr := pmm_alloc(page_count + 1)

	if ptr == 0 {
		return 0
	}

	metadata_ptr := unsafe { &char(ptr) + higher_half }
	mut metadata := &MallocMetadata(metadata_ptr)

	metadata.pages = page_count
	metadata.size = size

	return unsafe { &char(ptr) + higher_half + page_size }
}

pub fn realloc(ptr voidptr, new_size u64) voidptr {
	if ptr == 0 {
		return malloc(new_size)
	}

	metadata_ptr := unsafe { &char(ptr) - page_size }
	mut metadata := &MallocMetadata(metadata_ptr)

	if lib.div_roundup(metadata.size, page_size) == lib.div_roundup(new_size, page_size) {
		metadata.size = new_size
		return ptr
	}

	new_ptr := malloc(new_size)
	if new_ptr == 0 {
		return 0
	}

	if metadata.size > new_size {
		unsafe { C.memcpy(new_ptr, ptr, new_size) }
	} else {
		unsafe { C.memcpy(new_ptr, ptr, metadata.size) }
	}

	free(ptr)

	return new_ptr
}
