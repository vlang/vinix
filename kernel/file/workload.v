module file

import errno
import katomic
import proc
import resource
import stat

fn retire_workload(group &proc.WorkloadLease) {
	mut handle := unsafe { &Handle(group.payload) }
	// This owner is distinct from every user-visible open description. LOCK_UN
	// or closing a descriptor cannot remove the kernel-only shared lock.
	release_owner_locks(handle, u64(group), true)
	handle.unref()
}

pub fn attach_workload_lease(fdnum int) (u64, u64) {
	mut process := proc.current_thread().process
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer { fd.unref() }
	mut handle := fd.handle
	if handle.flags & resource.o_path != 0 || handle.flags & resource.o_accmode != resource.o_rdonly
		|| !stat.isreg(handle.resource.stat.mode) { return errno.err, errno.einval }
	handle.mac_check(proc.mac_metadata) or { return errno.err, errno.get() }
	process.threads_lock.acquire()
	defer { process.threads_lock.release() }
	if process.exiting || process.threads.len != 1 { return errno.err, errno.ebusy }
	resource_id := lock_resource_id(handle.resource)
	advisory_locks_lock.acquire()
	mut shared := false
	for held in advisory_locks {
		if held.resource_id == resource_id && held.owner == u64(handle) && held.class == lock_class_flock && !held.write {
			shared = true; break
		}
	}
	advisory_locks_lock.release()
	if !shared { return errno.err, errno.einval }
	mut ancestor := process.workload_lease
	for ancestor != unsafe { nil } {
		old := unsafe { &Handle(ancestor.payload) }
		if lock_resource_id(old.resource) == resource_id { return 0, 0 }
		ancestor = ancestor.parent
	}
	depth := if process.workload_lease == unsafe { nil } { 0 } else { process.workload_lease.depth }
	if depth >= proc.max_workload_depth { return errno.err, errno.e2big }
	mut group := proc.new_workload_lease(voidptr(handle), retire_workload) or { return errno.err, errno.get() }
	katomic.inc(mut &handle.refcount)
	advisory_locks_lock.acquire()
	// Another process can hold a duplicate of the source description. Recheck
	// its lock and conflicts atomically with inserting the independent owner.
	shared = false
	for held in advisory_locks {
		if held.resource_id == resource_id && held.owner == u64(handle) && held.class == lock_class_flock && !held.write {
			shared = true; break
		}
	}
	mut conflict := false
	if _ := conflicting_lock(resource_id, u64(group), lock_class_flock, 0, u64(-1), false, false) { conflict = true }
	if !shared || conflict {
		advisory_locks_lock.release()
		proc.drop_workload_lease(group)
		return errno.err, errno.eagain
	}
	advisory_locks.flags |= .noslices
	advisory_locks << AdvisoryLock{resource_id, u64(group), lock_class_flock, 0, u64(-1), false, 0}
	advisory_locks_lock.release()
	// Transfer this process's previous leaf reference into the new parent link.
	group.parent = process.workload_lease
	group.depth = depth + 1
	process.workload_lease = group
	return 0, 0
}
