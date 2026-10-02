// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import memory

// Version 1 records, sorted by Linux syscall number. The reserved flags must
// be zero; every entry names exactly one instruction offset, including zero.
pub struct SyscallPin {
pub mut:
	number u32
	flags u32
	offset u64
}

// Validate metadata and instruction bytes in one pagemap critical section.
// Only private anonymous RX text can be registered: file/shared aliases must
// not let another writer replace an instruction after the check. The caller
// owns the records, and none of their pointers are retained here.
pub fn validate_syscall_pin_region(_pagemap &memory.Pagemap, base u64, length u64,
	pins &SyscallPin, count u32) ? {
	mut pagemap := unsafe { _pagemap }
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	end := base + length
	mut current := base
	for current < end {
		range := range_floor(pagemap, current)
		if range == unsafe { nil } || current < range.base
			|| current - range.base >= range.length || !range.immutable
			|| range.prot & (prot_read | prot_write | prot_exec) != (prot_read | prot_exec)
			|| range.flags & (map_private | map_shared | map_anonymous) != (map_private | map_anonymous)
			|| range.dont_fork || range.wipe_on_fork
			|| range.global.resource != unsafe { nil } {
			errno.set(errno.eperm)
			return none
		}
		range_end := range.base + range.length
		current = if range_end < end { range_end } else { end }
	}
	for i := u32(0); i < count; i++ {
		offset := unsafe { pins[i].offset }
		if offset > length || syscall_instruction_size() > length - offset
			|| !syscall_instruction_aligned(base + offset) {
			errno.set(errno.einval)
			return none
		}
		for byte := u64(0); byte < syscall_instruction_size(); byte++ {
			address := base + offset + byte
			physical := pagemap.user_page_phys(address, false) or {
				// The runtime must touch its copied stubs before sealing them.
				// Entry/installation never allocates or faults executable text in.
				errno.set(errno.efault)
				return none
			}
			value := unsafe { *&u8(physical + address % page_size + memory.get_hhdm_offset()) }
			if value != u8(syscall_instruction_word() >> (byte * 8)) {
				errno.set(errno.einval)
				return none
			}
		}
	}
}
