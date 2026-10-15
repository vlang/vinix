// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno

// Share the writer's admission lock: either an in-flight open already pins
// this attachment, or it must refuse before copy-up/truncation. Keep the gate
// closed after ordinary detach, but reopen it on backend shutdown failure.
fn begin_mount_unmount(mut entry Mount) ? {
	entry.lock.acquire()
	defer { entry.lock.release() }
	if entry.writers != 0 {
		errno.set(errno.ebusy)
		return none
	}
	entry.unmount_closed = true
}

fn cancel_mount_unmount(mut entry Mount) {
	entry.lock.acquire()
	entry.unmount_closed = false
	entry.lock.release()
}

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
