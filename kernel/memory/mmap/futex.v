// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import memory

// A PI prefault may lose a page-in/pageout race. Check the mapping separately
// before treating a missing PTE as an invalid user pointer. Caller owns the map.
pub fn writable_futex_address(space &memory.Pagemap, address u64) bool {
	if address >= memory.user_address_limit() { return false }
	mut pagemap := unsafe { space }
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	if pagemap.dying || address & 3 != 0 { return false }
	local, _, _ := addr2range(pagemap, address) or { return false }
	return local.length >= 4 && local.prot & prot_write != 0 && local.flags & map_shared == 0
		&& address - local.base <= local.length - 4
}
