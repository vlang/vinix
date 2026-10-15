// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import file
import lib

fn init() {
	file.on_mount_publication(mount_publication_allowed, release_mount_description)
}

// An open can finish after path lookup and a blocking backend rendezvous.
// Check its actual attachment while the publisher holds its descriptor table
// lock. The unmount path releases entry.lock before scanning those tables.
fn mount_publication_allowed(description &file.Handle) bool {
	mut handle := unsafe { description }
	mut entry := unsafe { &Mount(lib.mount_context_top(&handle.mount)) }
	if entry == unsafe { nil } { return true }
	entry.lock.acquire()
	defer { entry.lock.release() }
	if entry.unmount_closed { return false }
	// Different descriptor tables can publish duplicates of this same handle.
	// Serialize its first pin with admission and the mount's busy count.
	if handle.mount_description == unsafe { nil } {
		entry.descriptions++
		handle.mount_description = voidptr(entry)
	}
	return true
}

fn release_mount_description(identity voidptr) {
	mut entry := unsafe { &Mount(identity) }
	entry.lock.acquire()
	entry.descriptions--
	entry.lock.release()
}
