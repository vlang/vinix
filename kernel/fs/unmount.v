// SPDX-License-Identifier: GPL-2.0-or-later
module fs

// An ordinary detach must preserve a backing filesystem's shutdown refusal.
// Lazy detach deliberately keeps the existing deferred-lifetime semantics.
pub interface UnmountCheck {
mut:
	check_unmount() ?
}

struct UnmountCall {
mut:
	backend UnmountCheck
}

fn check_filesystem_unmount(mut filesystem FileSystem) ? {
	if filesystem is UnmountCheck {
		// Borrow the mount-lifetime filesystem box; do not allocate another box.
		mut call := unsafe { &UnmountCall(C.vinix_stack_alloc(sizeof(UnmountCall))) }
		unsafe { call.backend = UnmountCheck(filesystem) }
		call.backend.check_unmount()?
	}
}
