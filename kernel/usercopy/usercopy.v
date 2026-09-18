// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module usercopy

// Checked copies between the current process and kernel memory. User virtual
// addresses are resolved through the process pagemap one page at a time and
// copied through the kernel's physical direct map, so malformed pointers
// return EFAULT instead of taking a kernel-mode page fault.

import memory
import proc

fn valid_user_range(address u64, length u64) bool {
	if length == 0 {
		return true
	}
	if address == 0 || length - 1 > ~address {
		return false
	}
	// The per-architecture resolver enforces the canonical userspace half.
	return true
}

fn copy_user(kernel_address voidptr, user_address u64, length u64, to_user bool) bool {
	mut process := proc.current_thread().process
	if process == unsafe { nil } {
		return false
	}
	return copy_pagemap(process.pagemap, kernel_address, user_address, length, to_user)
}

fn copy_pagemap(_pagemap &memory.Pagemap, kernel_address voidptr, user_address u64, length u64, to_user bool) bool {
	if length == 0 {
		return true
	}
	if kernel_address == unsafe { nil } || !valid_user_range(user_address, length) {
		return false
	}
	if _pagemap == unsafe { nil } {
		return false
	}

	mut pagemap := unsafe { _pagemap }
	mut copied := u64(0)
	for copied < length {
		address := user_address + copied
		page_offset := address & (page_size - 1)
		mut chunk := page_size - page_offset
		if chunk > length - copied {
			chunk = length - copied
		}
		pagemap.l.acquire()
		physical := pagemap.user_page_phys(address, to_user) or {
			pagemap.l.release()
			if to_user && memory.resolve_cow(pagemap, address) {
				continue
			}
			if memory.resolve_user_page(pagemap, address, to_user) {
				continue
			}
			return false
		}
		physical_address := physical + page_offset + memory.get_hhdm_offset()
		unsafe {
			if to_user {
				C.memcpy(voidptr(physical_address), voidptr(u64(kernel_address) + copied), chunk)
			} else {
				C.memcpy(voidptr(u64(kernel_address) + copied), voidptr(physical_address), chunk)
			}
		}
		pagemap.l.release()
		copied += chunk
	}
	return true
}

fn probe_pagemap(_pagemap &memory.Pagemap, user_address u64, length u64, write bool) bool {
	if !valid_user_range(user_address, length) || _pagemap == unsafe { nil } {
		return false
	}
	if length == 0 {
		return true
	}
	mut pagemap := unsafe { _pagemap }
	mut checked := u64(0)
	for checked < length {
		address := user_address + checked
		page_offset := address & (page_size - 1)
		mut chunk := page_size - page_offset
		if chunk > length - checked {
			chunk = length - checked
		}
		for {
			pagemap.l.acquire()
			if _ := pagemap.user_page_phys(address, write) {
				pagemap.l.release()
				break
			}
			pagemap.l.release()
			if write && memory.resolve_cow(pagemap, address) {
				continue
			}
			if memory.resolve_user_page(pagemap, address, write) {
				continue
			}
			return false
		}
		checked += chunk
	}
	return true
}

// Validate and, where appropriate, demand-page the current process's user
// range without copying bytes. Read-like syscalls use the writable form before
// consuming backend data so an invalid destination can still fail with EFAULT
// before the resource changes state.
pub fn probe_readable(address u64, length u64) bool {
	process := proc.current_thread().process
	return process != unsafe { nil }
		&& probe_pagemap(process.pagemap, address, length, false)
}

pub fn probe_writable(address u64, length u64) bool {
	process := proc.current_thread().process
	return process != unsafe { nil }
		&& probe_pagemap(process.pagemap, address, length, true)
}

pub fn copy_from_user(destination voidptr, source u64, length u64) bool {
	return copy_user(destination, source, length, false)
}

pub fn copy_to_user(destination u64, source voidptr, length u64) bool {
	return copy_user(source, destination, length, true)
}

// Write into an address space that is not the current one. Used when setting up
// a freshly forked child, whose pages were already copied away from ours.
pub fn copy_to_pagemap(pagemap &memory.Pagemap, destination u64, source voidptr, length u64) bool {
	return copy_pagemap(pagemap, source, destination, length, true)
}

pub fn read_u32(address u64) ?u32 {
	mut value := u32(0)
	if !copy_from_user(voidptr(&value), address, sizeof(u32)) {
		return none
	}
	return value
}
