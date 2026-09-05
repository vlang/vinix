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
	if length == 0 {
		return true
	}
	if kernel_address == unsafe { nil } || !valid_user_range(user_address, length) {
		return false
	}

	mut process := proc.current_thread().process
	if process == unsafe { nil } || process.pagemap == unsafe { nil } {
		return false
	}
	mut pagemap := process.pagemap
	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	mut copied := u64(0)
	for copied < length {
		address := user_address + copied
		page_offset := address & (page_size - 1)
		mut chunk := page_size - page_offset
		if chunk > length - copied {
			chunk = length - copied
		}
		physical := pagemap.user_page_phys(address, to_user) or { return false }
		physical_address := physical + page_offset + memory.get_hhdm_offset()
		unsafe {
			if to_user {
				C.memcpy(voidptr(physical_address), voidptr(u64(kernel_address) + copied),
					chunk)
			} else {
				C.memcpy(voidptr(u64(kernel_address) + copied), voidptr(physical_address),
					chunk)
			}
		}
		copied += chunk
	}
	return true
}

pub fn copy_from_user(destination voidptr, source u64, length u64) bool {
	return copy_user(destination, source, length, false)
}

pub fn copy_to_user(destination u64, source voidptr, length u64) bool {
	return copy_user(source, destination, length, true)
}

pub fn read_u32(address u64) ?u32 {
	mut value := u32(0)
	if !copy_from_user(voidptr(&value), address, sizeof(u32)) {
		return none
	}
	return value
}
