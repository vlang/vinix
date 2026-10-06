// SPDX-License-Identifier: GPL-2.0-or-later
module usercopy

import memory
import proc

// Resident-only from-user copies use real non-temporal 4/8-byte stores for
// aligned kernel destinations. Cached alignment edges and tails are allowed.
// The caller owns accessible kernel memory for the complete synchronous copy;
// this provides no machine-check recovery for arbitrary kernel/WC addresses.
pub fn raw_copy_from_user_nocache(destination voidptr, source u64, length u64) u64 {
	if length == 0 {
		return 0
	}
	if destination == unsafe { nil } || !user_range(source, length)
		|| length - 1 > ~u64(destination) {
		return length
	}
	caller := proc.current_thread()
	if caller == unsafe { nil } {
		return length
	}
	process := caller.process
	if process == unsafe { nil } {
		return length
	}
	return copy_nocache_pagemap_remaining(process.pagemap, destination, source, length)
}

// The fixture can own an unpublished pagemap. Each physical source chunk stays
// under this map's lock through its final SFENCE; no source reference escapes.
// Page boundaries may require extra cached edges compared with Linux's
// virtual copy. Only complete protected page prefixes are committed on a later
// mapping failure, and the exact uncopied destination suffix stays untouched.
// No resolver, COW, allocation or sleeping operation is used on this path.
fn copy_nocache_pagemap_remaining(_pagemap &memory.Pagemap, destination voidptr, source u64, length u64) u64 {
	if length == 0 {
		return 0
	}
	if _pagemap == unsafe { nil } || destination == unsafe { nil }
		|| !user_range(source, length) || length - 1 > ~u64(destination) {
		return length
	}
	mut pagemap := unsafe { _pagemap }
	mut copied := u64(0)
	for copied < length {
		address := source + copied
		page_offset := address & (page_size - 1)
		mut chunk := page_size - page_offset
		if chunk > length - copied {
			chunk = length - copied
		}
		pagemap.l.acquire()
		physical := pagemap.user_page_phys(address, false) or {
			nocache_store_fence()
			pagemap.l.release()
			return length - copied
		}
		physical_address := physical + page_offset + memory.get_hhdm_offset()
		mut offset := u64(0)
		for offset < chunk {
			destination_address := u64(destination) + copied + offset
			remaining := chunk - offset
			mut width := u64(1)
			if destination_address & 7 == 0 && remaining >= 8 {
				width = 8
			} else if destination_address & 3 == 0 && remaining >= 4 {
				width = 4
			} else if destination_address & 1 == 0 && remaining >= 2 {
				width = 2
			}
			if !copy_nocache_word(voidptr(destination_address),
				voidptr(physical_address + offset), width) {
				nocache_store_fence()
				pagemap.l.release()
				return length - copied - offset
			}
			offset += width
		}
		nocache_store_fence()
		pagemap.l.release()
		copied += chunk
	}
	return 0
}
