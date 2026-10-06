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

// Whether [address, address + length) is somewhere a process can have memory:
// not null, not wrapping, and below the kernel's half. The copies check this
// as they go; a caller about to take something that cannot be put back -- a
// pipe's bytes, a socket's message -- asks first.
pub fn user_range(address u64, length u64) bool {
	if length == 0 {
		return true
	}
	if !valid_user_range(address, length) {
		return false
	}
	return address + (length - 1) < memory.user_address_limit()
}

// Whether the current process can write the byte at `address`, after doing
// what a write there would: copying a page still shared with a fork child,
// paging in one nothing has touched. For a caller about to take something
// that cannot be put back, which then learns of a pointer that leads nowhere
// while it still has nothing to lose.
pub fn writable(address u64) bool {
	mut process := proc.current_thread().process
	if process == unsafe { nil } || !user_range(address, 1) {
		return false
	}
	mut pagemap := process.pagemap
	for _ in 0 .. 4 {
		pagemap.l.acquire()
		if _ := pagemap.user_page_phys(address, true) {
			pagemap.l.release()
			return true
		}
		pagemap.l.release()
		if memory.resolve_cow(pagemap, address) || memory.resolve_missing_page(pagemap,
			address) {
			continue
		}
		return false
	}
	return false
}

fn copy_user(kernel_address voidptr, user_address u64, length u64, to_user bool) bool {
	mut process := proc.current_thread().process
	if process == unsafe { nil } {
		return false
	}
	return copy_pagemap(process.pagemap, kernel_address, user_address, length, to_user)
}

fn copy_pagemap(_pagemap &memory.Pagemap, kernel_address voidptr, user_address u64, length u64, to_user bool) bool {
	return copy_pagemap_policy(_pagemap, kernel_address, user_address, length, to_user, true, true)
}

fn copy_pagemap_policy(_pagemap &memory.Pagemap, kernel_address voidptr, user_address u64, length u64, to_user bool, fault_missing bool, cow bool) bool {
	return copy_pagemap_policy_remaining(_pagemap, kernel_address, user_address, length,
		to_user, fault_missing, cow) == 0
}

// Return the uncopied suffix. The prefix is committed one page at a time
// while holding the pagemap lock, and failed resolution never changes the
// bytes after that prefix. Keep the native range policy here: existing
// Boolean callers allow a prefix before the architecture rejects a later
// address outside the userspace half.
fn copy_pagemap_policy_remaining(_pagemap &memory.Pagemap, kernel_address voidptr, user_address u64, length u64, to_user bool, fault_missing bool, cow bool) u64 {
	if length == 0 {
		return 0
	}
	if kernel_address == unsafe { nil } || !valid_user_range(user_address, length) {
		return length
	}
	if _pagemap == unsafe { nil } {
		return length
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
				if to_user && cow && memory.resolve_cow(pagemap, address) {
					continue
				}
				if fault_missing && memory.resolve_missing_page(pagemap, address) {
					continue
				}
			}
			return length - copied
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
	return 0
}

fn raw_copy_user(kernel_address voidptr, user_address u64, length u64, to_user bool) u64 {
	// Zero-length copies must not inspect either pointer or the current task.
	if length == 0 {
		return 0
	}
	// These raw copies validate the complete user range before committing any
	// prefix. The kernel buffer is borrowed and must remain accessible for the
	// requested length throughout this synchronous copy.
	if kernel_address == unsafe { nil } || !user_range(user_address, length) {
		return length
	}
	mut process := proc.current_thread().process
	if process == unsafe { nil } {
		return length
	}
	return copy_pagemap_policy_remaining(process.pagemap, kernel_address, user_address,
		length, to_user, true, true)
}

// Return the bytes that could not be read. Any copied prefix is preserved;
// the uncopied destination suffix is left untouched. Missing pages may fault
// in, so callers use ordinary kernel process context that permits faults.
pub fn raw_copy_from_user(destination voidptr, source u64, length u64) u64 {
	return raw_copy_user(destination, source, length, false)
}

// Return the bytes that could not be written. Missing and COW pages resolve
// through the native fault handlers, and an inaccessible suffix is untouched.
pub fn raw_copy_to_user(destination u64, source voidptr, length u64) u64 {
	return raw_copy_user(source, destination, length, true)
}

pub fn copy_from_user(destination voidptr, source u64, length u64) bool {
	return copy_user(destination, source, length, false)
}

// Copy a NUL-terminated userspace string into owned kernel memory. Read only
// within the current mapped page before looking for NUL: a terminator at the
// end of a page must not require the following page to be mapped. max_bytes
// includes the terminator, as with PATH_MAX-style limits. The buffer starts
// small and grows, since nearly every string is far shorter than its limit.
pub fn copy_cstring_from_user(address u64, max_bytes int) ?string {
	if max_bytes <= 0 {
		errno.set(errno.einval)
		return none
	}
	if address == 0 {
		errno.set(errno.efault)
		return none
	}
	mut capacity := if max_bytes < 256 { max_bytes } else { 256 }
	mut bytes := unsafe { &u8(malloc(capacity)) }
	mut copied := 0
	for copied < max_bytes {
		if u64(copied) > ~address {
			break
		}
		if copied == capacity {
			capacity = if capacity * 4 < max_bytes { capacity * 4 } else { max_bytes }
			grown := unsafe { &u8(malloc(capacity)) }
			unsafe {
				C.memcpy(grown, bytes, copied)
				free(bytes)
			}
			bytes = grown
		}
		current := address + u64(copied)
		page_remaining := int(page_size - (current & (page_size - 1)))
		chunk := if page_remaining < capacity - copied {
			page_remaining
		} else {
			capacity - copied
		}
		if !copy_from_user(unsafe { voidptr(bytes + copied) }, current, u64(chunk)) {
			break
		}
		for i in copied .. copied + chunk {
			if unsafe { bytes[i] } == 0 {
				// The string owns the buffer: its free() gives it back.
				return unsafe { tos(bytes, i) }
			}
		}
		copied += chunk
	}
	unsafe { free(bytes) }
	errno.set(if copied >= max_bytes { errno.enametoolong } else { errno.efault })
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

// The caller owns an inspection reference when this is a remote map.
pub fn copy_from_pagemap(pagemap &memory.Pagemap, destination voidptr, source u64, length u64) bool {
	return copy_pagemap(pagemap, destination, source, length, false)
}

// Cross-process demand faults need a pinned mapping-range lifetime. Copies
// also preserve cgroup limits by refusing remote COW when it cannot be charged.
pub fn copy_remote_from(pagemap &memory.Pagemap, destination voidptr, source u64, length u64, fault_missing bool) bool {
	return copy_pagemap_policy(pagemap, destination, source, length, false, fault_missing, false)
}

pub fn copy_remote_to(pagemap &memory.Pagemap, destination u64, source voidptr, length u64, fault_missing bool) bool {
	return copy_pagemap_policy(pagemap, source, destination, length, true, fault_missing, fault_missing)
}

pub fn read_u32(address u64) ?u32 {
	mut value := u32(0)
	if !copy_from_user(voidptr(&value), address, sizeof(u32)) {
		return none
	}
	return value
}

// FUTEX_WAKE_OP must change a user word atomically with respect to userspace.
// Resolve writable/COW pages first, then use the same physical word the
// process sees. The pagemap lock keeps that mapping stable during the CAS.
pub fn futex_atomic_op_u32(address u64, op u32, operand u32) ?u32 {
	if address & 3 != 0 || !valid_user_range(address, 4) {
		return none
	}
	mut pagemap := proc.current_thread().process.pagemap
	for _ in 0 .. 4 {
		pagemap.l.acquire()
		physical := pagemap.user_page_phys(address, true) or {
			pagemap.l.release()
			if memory.resolve_cow(pagemap, address) || memory.resolve_missing_page(pagemap,
				address) {
				continue
			}
			return none
		}
		ptr := voidptr(physical + (address & (page_size - 1)) + memory.get_hhdm_offset())
		for {
			old := word_load(ptr)
			updated := match op {
				0 { operand } // SET
				1 { old + operand } // ADD
				2 { old | operand } // OR
				3 { old & ~operand } // ANDN
				else { old ^ operand } // XOR
			}
			if word_cas(ptr, old, updated) == old {
				pagemap.l.release()
				return old
			}
		}
	}
	return none
}
