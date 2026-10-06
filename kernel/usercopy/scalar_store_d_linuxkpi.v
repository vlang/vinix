// SPDX-License-Identifier: GPL-2.0-or-later
module usercopy

import memory
import proc

// Ordinary faulting stores retain the current task's process and capture its
// pagemap once. The value is passed by value; no kernel buffer is retained.
pub fn write_scalar_user(address u64, size u64, value u64) bool {
	if (size != 1 && size != 2 && size != 4 && size != 8)
		|| !user_range(address, size) {
		return false
	}
	process := proc.current_thread().process
	if process == unsafe { nil } {
		return false
	}
	return write_scalar_pagemap(process.pagemap, address, size, value)
}

// The native fixture owns an unpublished pagemap. Permission checks and each
// physical access remain protected by that same pagemap's lock.
fn write_scalar_pagemap(_pagemap &memory.Pagemap, address u64, size u64, value u64) bool {
	if _pagemap == unsafe { nil }
		|| (size != 1 && size != 2 && size != 4 && size != 8)
		|| !user_range(address, size) {
		return false
	}
	mut pagemap := unsafe { _pagemap }
	page_offset := address & (page_size - 1)
	if size > page_size - page_offset {
		// Adjacent user pages need not have adjacent physical backing. These
		// unaligned stores commit one protected page chunk at a time. Failure
		// leaves any committed prefix in place and the inaccessible suffix
		// untouched; split-page stores have no rollback or atomicity promise.
		mut bytes := [8]u8{}
		for i in 0 .. int(size) {
			unsafe { bytes[i] = u8(value >> u32(8 * i)) }
		}
		return copy_pagemap_policy_remaining(pagemap, unsafe { &bytes[0] }, address,
			size, true, true, true) == 0
	}
	mut attempts := 0
	for {
		pagemap.l.acquire()
		physical := pagemap.user_page_phys(address, true) or {
			pagemap.l.release()
			// Real COW and demand-page resolvers may wait or allocate. They
			// revalidate the mapping outside this lock before a fresh lookup.
			if attempts < 3 {
				attempts++
				if memory.resolve_cow(pagemap, address)
					|| memory.resolve_missing_page(pagemap, address) {
					continue
				}
			}
			return false
		}
		scalar_word_store(voidptr(physical + page_offset + memory.get_hhdm_offset()),
			size, value)
		pagemap.l.release()
		return true
	}
	return false
}
