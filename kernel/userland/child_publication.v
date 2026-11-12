module userland

import proc
import parentfixture

// The creating thread remains in its syscall until publication. Ordinary
// parent teardown waits for that thread; CLONE_PARENT's parent has no such
// protection. Select it only now, under the same lock as claim_teardown and
// adoption's PPID updates, and retain that lock through list insertion.
fn publish_clone_child(mut child proc.Process, creator &proc.Process, sibling bool) {
	$if parent_publication_fixture ? {
		$if parent_clone_old ? {
			if sibling { publish_clone_old(mut child, creator); return }
		}
		if sibling { parentfixture.pause(1, creator.pid) }
	}
	proc.lock_table()
	mut parent := unsafe { creator }
	if sibling {
		candidate := proc.process_at(creator.ppid)
		if candidate != unsafe { nil } && !candidate.exiting {
			parent = candidate
		} else {
			adopter := find_reaper_locked(creator)
			if adopter != unsafe { nil } { parent = adopter }
		}
	}
	child.ppid = parent.pid
	parent.children_lock.acquire()
	parent.children << &child
	parent.children_lock.release()
	proc.unlock_table()
}
