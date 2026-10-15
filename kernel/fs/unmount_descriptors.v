// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import file
import lib
import proc

// The caller holds the process table lock. Table ownership keeps each FD and
// its handle alive while fds_lock excludes close/replacement and table growth.
// Handle.mount is immutable after publication: inherited descriptors still
// select their original attachment, not a copied namespace's mount with its id.
// Contention conservatively refuses unmount without reversing a lock order.
fn unmount_descriptors_in_use(owner &proc.Process, entry &Mount) bool {
	mut process := unsafe { owner }
	if !process.fds_lock.test_and_acquire() { return true }
	defer { process.fds_lock.release() }
	for pointer in process.fds {
		fd := unsafe { &file.FD(pointer) }
		if fd == unsafe { nil } || fd.handle == unsafe { nil } { continue }
		if lib.mount_context_top(&fd.handle.mount) == voidptr(entry) { return true }
	}
	return false
}
