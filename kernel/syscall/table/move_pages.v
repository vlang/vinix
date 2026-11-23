// SPDX-License-Identifier: GPL-2.0-or-later
module table

import errno
import memory
import memory.mmap
import proc
import usercopy

const move_pages_chunk = 16
const move_pages_move = u32(2)
const move_pages_move_all = u32(4)

fn syscall_linux_move_pages(_ voidptr, pid i32, count u64, pages u64, nodes u64, status u64,
	flags u32) (u64, u64) {
	if flags & ~(move_pages_move | move_pages_move_all) != 0 { return errno.err, errno.einval }
	if flags & move_pages_move_all != 0
		&& !proc.has_capability(proc.current_thread().process, proc.cap_sys_nice) {
		return errno.err, errno.eperm
	}
	mut pagemap := proc.pin_page_location_pagemap(int(pid)) or { return errno.err, errno.get() }
	defer { memory.release_inspection(pagemap) }
	if count == 0 { return 0, 0 }
	if nodes != 0 { return errno.err, errno.eopnotsupp }

	mut input := pages
	mut output := status
	mut remaining := count
	mut addresses := [move_pages_chunk]u64{}
	mut located := [move_pages_chunk]i32{}
	address_ptr := unsafe { &addresses[0] }
	status_ptr := unsafe { &located[0] }
	for remaining > 0 {
		batch := if remaining < move_pages_chunk { remaining } else { u64(move_pages_chunk) }
		in_bytes := batch * sizeof(u64)
		out_bytes := batch * sizeof(i32)
		if !usercopy.copy_from_user(address_ptr, input, in_bytes) { return errno.err, errno.efault }
		mmap.page_locations(mut pagemap, address_ptr, status_ptr, int(batch))
		if !usercopy.copy_to_user(output, status_ptr, out_bytes) { return errno.err, errno.efault }
		input += in_bytes
		output += out_bytes
		remaining -= batch
	}
	return 0, 0
}
