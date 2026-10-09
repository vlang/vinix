// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import errno
import kbudget
import memory

pub fn kernel_owner() kbudget.Owner {
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } { return kbudget.Owner{} }
	return t.process.kernel_owner
}

// This may be called with VFS, descriptor, IPC or VM locks held. It must not
// sleep, reclaim resources recursively, or invoke the OOM killer there.
pub fn reserve_kernel_for(owner kbudget.Owner, kind kbudget.Kind, bytes u64) ?kbudget.Charge {
	if owner.slot != 0 && !kernel_room(bytes) {
		t := current_thread()
		if t != unsafe { nil } { unsafe { t.owes_memory = true } }
		errno.set(errno.enomem)
		return none
	}
	return kbudget.reserve(owner, kind, bytes) or {
		errno.set(errno.enomem)
		return none
	}
}

pub fn reserve_kernel(kind kbudget.Kind, bytes u64) ?kbudget.Charge {
	return reserve_kernel_for(kernel_owner(), kind, bytes)
}

pub fn grow_kernel(mut charge kbudget.Charge, bytes u64) bool {
	if charge.owner.slot != 0 && !kernel_room(bytes) {
		t := current_thread()
		if t != unsafe { nil } { unsafe { t.owes_memory = true } }
		errno.set(errno.enomem)
		return false
	}
	if !kbudget.grow(mut charge, bytes) {
		errno.set(errno.enomem)
		return false
	}
	return true
}

fn kernel_room(bytes u64) bool {
	free := memory.free_bytes()
	// User pages leave the entire critical reserve. Small syscall metadata
	// may use its upper half, as copy-to-user already does, while its lower
	// half remains available to kernel cleanup. Requiring a higher watermark
	// here would refuse /proc reads and mapping metadata before pageout runs.
	reserve := memory.user_reserve_pages() * memory.page_size / 2
	return free > reserve && bytes <= free - reserve
}
