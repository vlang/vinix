// SPDX-License-Identifier: GPL-2.0-or-later
module usercopy

import memory
import proc

// The current task retains its process/pagemap throughout this ordinary,
// faulting read. Callers retain writable kernel result storage until return.
pub fn read_scalar_user(address u64, size u64, result &u64) bool {
	unsafe { *result = 0 }
	if (size != 1 && size != 2 && size != 4 && size != 8)
		|| !user_range(address, size) {
		return false
	}
	process := proc.current_thread().process
	if process == unsafe { nil } {
		return false
	}
	return read_scalar_pagemap(process.pagemap, address, size, result)
}

// The native fixture can exercise the same read on an owned, unpublished
// pagemap. Every direct physical access stays inside its pagemap lock.
fn read_scalar_pagemap(_pagemap &memory.Pagemap, address u64, size u64, result &u64) bool {
	unsafe { *result = 0 }
	if _pagemap == unsafe { nil }
		|| (size != 1 && size != 2 && size != 4 && size != 8)
		|| !user_range(address, size) {
		return false
	}
	mut pagemap := unsafe { _pagemap }
	page_offset := address & (page_size - 1)
	if size > page_size - page_offset {
		// An unaligned value crossing two pages can have noncontiguous
		// physical backing. Keep every chunk protected by the existing
		// faulting walk and publish nothing if either page is inaccessible.
		mut bytes := [8]u8{}
		if copy_pagemap_policy_remaining(pagemap, unsafe { &bytes[0] }, address,
			size, false, true, true) != 0 {
			return false
		}
		mut value := u64(0)
		for i in 0 .. int(size) {
			value |= u64(unsafe { bytes[i] }) << u32(8 * i)
		}
		unsafe { *result = value }
		return true
	}
	mut attempts := 0
	for {
		pagemap.l.acquire()
		physical := pagemap.user_page_phys(address, false) or {
			pagemap.l.release()
			if attempts < 3 {
				attempts++
				if memory.resolve_missing_page(pagemap, address) {
					continue
				}
			}
			return false
		}
		value := scalar_word_load(voidptr(physical + page_offset + memory.get_hhdm_offset()),
			size)
		pagemap.l.release()
		unsafe { *result = value }
		return true
	}
	return false
}
