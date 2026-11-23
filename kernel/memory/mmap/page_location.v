// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import memory
import numa

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
	if !page_mapping_has_node(local) { return -i32(errno.enoent) }
	return physical_page_node(phys)
}

fn page_mapping_has_node(local &MmapRangeLocal) bool {
	return local.global.pte_extra & (memory.pte_uncached | memory.pte_device) == 0
}

fn physical_page_node(phys u64) i32 {
	if memory.pmm_refcount_unlocked(voidptr(phys)) == 0 { return -i32(errno.enoent) }
	if !memory.pmm_numa_enabled() { return 0 }
	node := memory.pmm_node_of(phys)
	return if node >= 0 { i32(node) } else { -i32(errno.enoent) }
}

// Address-policy queries use the caller's map. A node query can fault in
// a readable page, so look the range up again after releasing the lock.
pub fn query_policy_address(mut pagemap memory.Pagemap, address u64, want_node bool) i32 {
	if address >= memory.user_address_limit() { return -i32(errno.efault) }
	for attempt in 0 .. 4 {
		pagemap.l.acquire()
		result := policy_address_locked(pagemap, address, want_node)
		pagemap.l.release()
		if result != -i32(errno.eagain) { return result }
		if attempt == 3 || !resolve_missing_with_access(pagemap, address, true) { break }
	}
	return -i32(errno.efault)
}

fn policy_address_locked(pagemap &memory.Pagemap, address u64, want_node bool) i32 {
	local, _, _ := addr2range(pagemap, address) or { return -i32(errno.efault) }
	if !want_node {
		// With no explicit range policy, MPOL_F_ADDR reports MPOL_DEFAULT.
		return i32(numa.mpol_default)
	}
	if !page_mapping_has_node(local) { return -i32(errno.efault) }
	if phys := pagemap.user_page_phys(address, false) {
		node := physical_page_node(phys)
		return if node >= 0 { node } else { -i32(errno.efault) }
	}
	return if local.prot & prot_read != 0 { -i32(errno.eagain) } else { -i32(errno.efault) }
}
