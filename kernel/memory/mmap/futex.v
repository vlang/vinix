// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import memory

pub fn is_shared_address(space &memory.Pagemap, address u64) bool {
	mut pagemap := unsafe { space }
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	local, _, _ := addr2range(pagemap, address) or { return false }
	return local.flags & map_shared != 0
}

pub struct FutexMapping {
pub:
	shared bool
	inode u64
	offset u64
}

// Sample the backing and its resident PTE together. An absent shared page
// must be faulted in by the caller so an address past EOF cannot name a queue.
// A copied inode ID survives truncation without pinning the page or inode.
pub fn futex_mapping(space &memory.Pagemap, address u64) ?FutexMapping {
	mut pagemap := unsafe { space }
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	local, _, file_page := addr2range(pagemap, address) or { return FutexMapping{} }
	if local.flags & map_shared == 0 { return FutexMapping{} }
	physical := pagemap.user_page_phys(address, false) or { return none }
	byte := address & (memory.page_size - 1)
	inode := local.global.truncation_inode
	return FutexMapping{
		shared: true
		inode: inode
		offset: if inode != 0 { file_page * memory.page_size + byte } else { physical + byte }
	}
}

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
