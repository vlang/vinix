module memory

import lib
import stivale2

const block_size = 0x1000

__global ( bitmap lib.Bitmap )

__global ( block_count u64 )

__global ( highest_address u64 )

__global ( last_used_index u64 )

pub fn physical_init(memmap &stivale2.MemmapTag) {
	// Calculate the highest and lowest boundaries.
	mut entries := &memmap.entries
	unsafe {
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
		highest_address = lib.align_down(highest_address, memory.block_size)

		// Calculate the needed size for the bitmap in bytes
		block_count = lib.align_down(highest_address, memory.block_size) / memory.block_size
		bitmap_size := block_count / 8

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
				bitmap = lib.Bitmap(entries[i].base)
				break
			}
		}

		// Fill the bitmap by first clearing and then populating with the memmap
		for i := 0; i < block_count; i++ {
			lib.bitset(bitmap, u64(i))
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
			for j := u64(0); j < length; j += memory.block_size {
				lib.bitreset(bitmap, (base + j) / memory.block_size)
			}
		}
	}
}

fn inner_alloc(count u64, limit u64) voidptr {
	mut p := 0
	for last_used_index < limit {
		if !lib.bittest(bitmap, last_used_index) {
			last_used_index++
			if p + 1 == count {
				p += 1
				page := last_used_index - count
				for i := page; page < last_used_index; i++ {
					lib.bitset(bitmap, i)
				}
				return voidptr(page * memory.block_size)
			}
		} else {
			last_used_index++
			p = 0
		}
	}
	return 0
}

pub fn malloc(count u64) voidptr {
	last := last_used_index
	ret := inner_alloc(count, highest_address / memory.block_size)
	if ret == 0 {
		last_used_index = 0
		return inner_alloc(count, last)
	}
	return ret
}

pub fn free(ptr voidptr, count u64) {
	page := u64(ptr) / memory.block_size
	for i := page; i < page + count; i++ {
		lib.bitreset(bitmap, i)
	}
}
