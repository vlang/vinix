// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

import errno
import memory
import proc
import usercopy

struct ProcessIOVec {
mut:
	base u64
	len  u64
}

const process_iov_max = 1024
const process_ssize_max = u64(0x7fffffffffffffff)

fn process_iov_size(vectors []ProcessIOVec) ?u64 {
	mut total := u64(0)
	for vector in vectors {
		if vector.len > process_ssize_max - total {
			errno.set(errno.einval)
			return none
		}
		total += vector.len
	}
	return total
}

fn process_vm_copy(pid int, local_address u64, local_count u64,
	remote_address u64, remote_count u64, flags u64, write bool) (u64, u64) {
	if flags != 0 || local_count > process_iov_max || remote_count > process_iov_max {
		return errno.err, errno.einval
	}
	mut local := []ProcessIOVec{len: int(local_count)} @[freed]
	mut remote := []ProcessIOVec{len: int(remote_count)} @[freed]
	defer {
		unsafe {
			local.free()
			remote.free()
		}
	}
	if local_count != 0 && !usercopy.copy_from_user(unsafe { voidptr(&local[0]) },
		local_address, local_count * sizeof(ProcessIOVec)) {
		return errno.err, errno.efault
	}
	local_bytes := process_iov_size(local) or { return errno.err, errno.get() }
	// Empty transfers have no target address space to inspect.
	if local_bytes == 0 {
		return 0, 0
	}
	if remote_count != 0 && !usercopy.copy_from_user(unsafe { voidptr(&remote[0]) },
		remote_address, remote_count * sizeof(ProcessIOVec)) {
		return errno.err, errno.efault
	}
	remote_bytes := process_iov_size(remote) or { return errno.err, errno.get() }
	if remote_bytes == 0 {
		return 0, 0
	}
	inspection := proc.inspect_pagemap(pid) or { return errno.err, errno.get() }
	pagemap := inspection.pagemap
	defer { memory.release_inspection(pagemap) }
	mut buffer := [4096]u8{}
	mut local_index := 0
	mut remote_index := 0
	mut local_offset := u64(0)
	mut remote_offset := u64(0)
	mut copied := u64(0)
	for local_index < local.len && remote_index < remote.len {
		if local_offset == local[local_index].len {
			local_index++
			local_offset = 0
			continue
		}
		if remote_offset == remote[remote_index].len {
			remote_index++
			remote_offset = 0
			continue
		}
		mut count := u64(buffer.len)
		if local[local_index].len - local_offset < count {
			count = local[local_index].len - local_offset
		}
		if remote[remote_index].len - remote_offset < count {
			count = remote[remote_index].len - remote_offset
		}
		if local_offset > ~local[local_index].base || remote_offset > ~remote[remote_index].base {
			break
		}
		local_ptr := local[local_index].base + local_offset
		remote_ptr := remote[remote_index].base + remote_offset
		// A failed page never hides bytes already transferred. Each copy is
		// contained in both maps' pages, so usercopy cannot copy only a prefix.
		local_remaining := page_size - (local_ptr & (page_size - 1))
		remote_remaining := page_size - (remote_ptr & (page_size - 1))
		if local_remaining < count { count = local_remaining }
		if remote_remaining < count { count = remote_remaining }
		if !usercopy.user_range(local_ptr, count) || !usercopy.user_range(remote_ptr, count) {
			break
		}
		ok := if write {
			usercopy.copy_from_user(voidptr(&buffer[0]), local_ptr, count)
				&& usercopy.copy_remote_to(pagemap, remote_ptr, voidptr(&buffer[0]), count, inspection.fault_missing)
		} else {
			usercopy.copy_remote_from(pagemap, voidptr(&buffer[0]), remote_ptr, count, inspection.fault_missing)
				&& usercopy.copy_to_user(local_ptr, voidptr(&buffer[0]), count)
		}
		if !ok {
			break
		}
		copied += count
		local_offset += count
		remote_offset += count
	}
	if copied == 0 {
		return errno.err, errno.efault
	}
	return copied, 0
}

fn syscall_linux_process_vm_readv(_ voidptr, pid int, local u64, local_count u64,
	remote u64, remote_count u64, flags u64) (u64, u64) {
	return process_vm_copy(pid, local, local_count, remote, remote_count, flags, false)
}

fn syscall_linux_process_vm_writev(_ voidptr, pid int, local u64, local_count u64,
	remote u64, remote_count u64, flags u64) (u64, u64) {
	return process_vm_copy(pid, local, local_count, remote, remote_count, flags, true)
}
