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
import errno

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
	mut attempts := 0
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
			// Do what a fault on the page would: copy it if it is still shared
			// with a fork child, and page it in if nothing has touched it yet.
			// A program's file-backed pages only enter the page tables when first
			// touched, so a constant in its read-only data could not be read:
			// musl blocks signals with rt_sigprocmask(SIG_BLOCK, &all_mask), which
			// failed with EFAULT, and a detached thread then unmapped its stack
			// with signals still open and was killed by the next one to arrive.
			// Bounded, since a page that stays out of reach -- read-only or
			// PROT_NONE -- is a genuine EFAULT.
			if attempts < 3 {
				attempts++
				if to_user && memory.resolve_cow(pagemap, address) {
					continue
				}
				if memory.resolve_missing_page(pagemap, address) {
					continue
				}
			}
			return false
		}
		attempts = 0
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

pub fn copy_from_user(destination voidptr, source u64, length u64) bool {
	return copy_user(destination, source, length, false)
}

// Copy a NUL-terminated userspace string into owned kernel memory. Read only
// within the current mapped page before looking for NUL: a terminator at the
// end of a page must not require the following page to be mapped. max_bytes
// includes the terminator, as with PATH_MAX-style limits.
pub fn copy_cstring_from_user(address u64, max_bytes int) ?string {
	if max_bytes <= 0 {
		errno.set(errno.einval)
		return none
	}
	if address == 0 {
		errno.set(errno.efault)
		return none
	}
	mut bytes := []u8{len: max_bytes}
	defer {
		unsafe { bytes.free() }
	}
	mut copied := 0
	for copied < max_bytes {
		if u64(copied) > ~address {
			errno.set(errno.efault)
			return none
		}
		current := address + u64(copied)
		page_remaining := int(page_size - (current & (page_size - 1)))
		chunk := if page_remaining < max_bytes - copied {
			page_remaining
		} else {
			max_bytes - copied
		}
		if !copy_from_user(voidptr(&bytes[copied]), current, u64(chunk)) {
			errno.set(errno.efault)
			return none
		}
		for i in copied .. copied + chunk {
			if bytes[i] == 0 {
				return bytes[..i].bytestr()
			}
		}
		copied += chunk
	}
	errno.set(errno.enametoolong)
	return none
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
