// SPDX-License-Identifier: GPL-2.0-or-later
module table

import errno
import memory
import memory.mmap
import numa
import proc
import usercopy

fn syscall_linux_get_mempolicy(_ voidptr, mode_ptr u64, nodemask u64, maxnode u64,
	address u64, flags u64) (u64, u64) {
	if nodemask != 0 && maxnode < u64(numa.node_count()) { return errno.err, errno.einval }
	if flags & ~u64(numa.mpol_f_node | numa.mpol_f_addr | numa.mpol_f_mems_allowed) != 0 {
		return errno.err, errno.einval
	}

	process := proc.current_thread().process
	mut mode := i32(process.mempolicy_mode)
	mut mask := process.mempolicy_nodemask
	want_node := flags & u64(numa.mpol_f_node) != 0
	if flags & u64(numa.mpol_f_mems_allowed) != 0 {
		if flags != u64(numa.mpol_f_mems_allowed) { return errno.err, errno.einval }
		mode = 0
		mask = numa.all_nodes_mask()
	} else if flags & u64(numa.mpol_f_addr) != 0 {
		mut pagemap := process.pagemap
		mode = mmap.query_policy_address(mut pagemap, address, want_node)
		if mode < 0 { return errno.err, u64(-mode) }
		mask = 0
	} else {
		if address != 0 { return errno.err, errno.einval }
		if want_node { mode = i32(numa.current_node()) }
	}

	if mode_ptr != 0 && !usercopy.copy_to_user(mode_ptr, unsafe { &mode }, sizeof(i32)) {
		return errno.err, errno.efault
	}
	if nodemask != 0 {
		return copy_policy_mask(nodemask, maxnode, mask)
	}
	return 0, 0
}

fn copy_policy_mask(nodemask u64, maxnode u64, mask u64) (u64, u64) {
	// Linux's bitmap width counts node IDs below maxnode-1. Copy complete
	// words and zero the extra words before copying the first one.
	bits := maxnode - 1
	if bits > memory.page_size * 8 { return errno.err, errno.einval }
	bytes := ((bits + 63) / 64) * sizeof(u64)
	if bytes == 0 { return 0, 0 }
	if !usercopy.user_range(nodemask, bytes) { return errno.err, errno.efault }
	zeroes := [16]u64{}
	mut offset := sizeof(u64)
	for offset < bytes {
		remaining := bytes - offset
		length := if remaining < sizeof(zeroes) { remaining } else { sizeof(zeroes) }
		if !usercopy.copy_to_user(nodemask + offset, unsafe { &zeroes[0] }, length) {
			return errno.err, errno.efault
		}
		offset += length
	}
	if !usercopy.copy_to_user(nodemask, unsafe { &mask }, sizeof(u64)) {
		return errno.err, errno.efault
	}
	return 0, 0
}
