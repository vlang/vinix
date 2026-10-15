// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import file
import lib

fn init() {
	file.on_mount_publication(mount_publication_allowed)
}

// An open can finish after path lookup and a blocking backend rendezvous.
// Check its actual attachment while the publisher holds its descriptor table
// lock. The unmount path releases entry.lock before scanning those tables.
fn mount_publication_allowed(identity &lib.MountContext) bool {
	mut entry := unsafe { &Mount(lib.mount_context_top(identity)) }
	if entry == unsafe { nil } { return true }
	entry.lock.acquire()
	allowed := !entry.unmount_closed
	entry.lock.release()
	return allowed
}
