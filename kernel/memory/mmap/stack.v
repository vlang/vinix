// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import memory

// Linux's flag value. PROT_NONE reservations may carry the tag so runtimes
// can make the usable portion writable later without tagging guard pages.
pub const map_stack = 0x20000

fn validate_stack_mapping(prot int, flags int) ? {
	if flags & map_stack == 0 { return }
	if flags & (map_private | map_shared) != map_private
		|| flags & map_anonymous == 0 || prot & prot_exec != 0 {
		errno.set(errno.einval)
		return none
	}
}

// Inspect metadata only: syscall entry must not fault pages in or allocate.
// The pagemap lock keeps an overlapping unmap/protection change from removing
// the range while its flags are checked. Existing split/fork/remap copy flags.
pub fn stack_pointer_valid(_pagemap &memory.Pagemap, pointer u64) bool {
	if pointer == 0 || pointer >= memory.user_address_limit() { return false }
	mut pagemap := unsafe { _pagemap }
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	range := range_floor(pagemap, pointer)
	return range != unsafe { nil } && pointer >= range.base
		&& pointer - range.base < range.length && range.flags & map_stack != 0
		&& range.prot & (prot_read | prot_write) == (prot_read | prot_write)
		&& range.prot & prot_exec == 0
}
