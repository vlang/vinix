// SPDX-License-Identifier: GPL-2.0-or-later
// Deliberately unsafe ordering for the clone-parent negative-control fixture.
module userland

import proc
import parentfixture

fn publish_clone_old(mut child proc.Process, creator &proc.Process) {
	proc.lock_table()
	mut parent := proc.process_at(creator.ppid)
	if parent == unsafe { nil } { parent = unsafe { creator } }
	// Keep the cached object allocated even when the fixture reaps it. The
	// control isolates lost child publication rather than a use-after-free.
	proc.pin_process(parent)
	proc.unlock_table()
	parentfixture.pause(1, creator.pid)
	proc.lock_table()
	child.ppid = parent.pid
	parent.children_lock.acquire()
	parent.children << &child
	parent.children_lock.release()
	proc.unlock_table()
	proc.unpin_process(parent)
}
