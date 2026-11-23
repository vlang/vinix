// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import memory

// The caller pins the address space. Hold its page-table lock while examining
// one batch, and release it before copying any statuses to userspace.
pub fn page_locations(mut pagemap memory.Pagemap, addresses &u64, statuses &i32, count int) {
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	for i in 0 .. count {
		unsafe { statuses[i] = page_location_locked(pagemap, addresses[i]) }
	}
}

fn page_location_locked(pagemap &memory.Pagemap, address u64) i32 {
	if address >= memory.user_address_limit() { return -i32(errno.efault) }
	local, _, _ := addr2range(pagemap, address) or { return -i32(errno.efault) }
	phys := pagemap.virt2phys(address) or { return -i32(errno.enoent) }
	if local.global.pte_extra & (memory.pte_uncached | memory.pte_device) != 0
		|| memory.pmm_refcount_unlocked(voidptr(phys)) == 0 { return -i32(errno.enoent) }
	if !memory.pmm_numa_enabled() { return 0 }
	node := memory.pmm_node_of(phys)
	return if node >= 0 { i32(node) } else { -i32(errno.enoent) }
}
