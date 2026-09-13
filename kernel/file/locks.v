@[has_globals]
module file

import errno
import event
import event.eventstruct
import klock
import proc
import resource
import stat
import usercopy

const lock_class_posix = 0
const lock_class_flock = 1
const lock_sh = 1
const lock_ex = 2
const lock_nb = 4
const lock_un = 8

struct LockRange {
	start u64
	end   u64
}

struct AdvisoryLock {
	resource_id voidptr
	owner       u64
	class       int
	start       u64
	end         u64
	write       bool
	pid         int
}

__global (
	advisory_locks      []AdvisoryLock
	advisory_locks_lock klock.Lock
	advisory_lock_event eventstruct.Event
)

// Resource is an interface; its first word is the concrete object pointer.
// Comparing the address of an interface box would make two handles for one
// inode look unrelated.
fn lock_resource_id(res &resource.Resource) voidptr {
	return unsafe { *&voidptr(res) }
}

fn ranges_overlap(a_start u64, a_end u64, b_start u64, b_end u64) bool {
	return a_start < b_end && b_start < a_end
}

fn normalize_lock(handle &Handle, flock Flock) ?LockRange {
	mut base := i64(0)
	match flock.l_whence {
		0 { base = 0 }
		1 { base = handle.loc }
		2 { base = handle.resource.stat.size }
		else {
			errno.set(errno.einval)
			return none
		}
	}
	if (flock.l_start > 0 && base > i64(0x7fffffffffffffff) - flock.l_start)
		|| (flock.l_start < 0 && base < i64(-0x7fffffffffffffff - 1) - flock.l_start) {
		errno.set(errno.eoverflow)
		return none
	}
	anchor := base + flock.l_start
	if anchor < 0 {
		errno.set(errno.einval)
		return none
	}
	if flock.l_len == 0 {
		return LockRange{u64(anchor), u64(-1)}
	}
	if flock.l_len > 0 {
		if anchor > i64(0x7fffffffffffffff) - flock.l_len {
			errno.set(errno.eoverflow)
			return none
		}
		return LockRange{u64(anchor), u64(anchor + flock.l_len)}
	}
	if flock.l_len < -anchor {
		errno.set(errno.einval)
		return none
	}
	return LockRange{u64(anchor + flock.l_len), u64(anchor)}
}

fn conflicting_lock(resource_id voidptr, owner u64, class int, start u64, end u64,
	write bool) ?AdvisoryLock {
	for held in advisory_locks {
		if held.resource_id != resource_id || held.class != class || held.owner == owner
			|| !ranges_overlap(held.start, held.end, start, end) {
			continue
		}
		if write || held.write {
			return held
		}
	}
	return none
}

// Remove the requested part of this owner's existing POSIX ranges. Preserved
// prefixes and suffixes make partial unlock/replacement behave byte-for-byte.
fn replace_owner_range(resource_id voidptr, owner u64, class int, start u64, end u64,
	add bool, write bool, pid int) {
	mut next := []AdvisoryLock{cap: advisory_locks.len + 2}
	for held in advisory_locks {
		if held.resource_id != resource_id || held.class != class || held.owner != owner
			|| !ranges_overlap(held.start, held.end, start, end) {
			next << held
			continue
		}
		if held.start < start {
			next << AdvisoryLock{held.resource_id, held.owner, held.class, held.start,
				start, held.write, held.pid}
		}
		if end < held.end {
			next << AdvisoryLock{held.resource_id, held.owner, held.class, end,
				held.end, held.write, held.pid}
		}
	}
	if add {
		next << AdvisoryLock{resource_id, owner, class, start, end, write, pid}
	}
	unsafe {
		advisory_locks.free()
		advisory_locks = next
	}
}

fn notify_lock_waiters() {
	event.trigger(mut advisory_lock_event, false)
}

fn set_posix_lock(mut handle Handle, mut flock Flock, blocking bool) ? {
	range := normalize_lock(handle, flock)?
	resource_id := lock_resource_id(handle.resource)
	owner := u64(proc.current_thread().process.pid)
	if flock.l_type == f_unlck {
		advisory_locks_lock.acquire()
		replace_owner_range(resource_id, owner, lock_class_posix, range.start, range.end,
			false, false, int(owner))
		advisory_locks_lock.release()
		notify_lock_waiters()
		return
	}

	write := flock.l_type == f_wrlck
	for {
		advisory_locks_lock.acquire()
		if _ := conflicting_lock(resource_id, owner, lock_class_posix, range.start,
			range.end, write) {
			generation := event.generation(mut advisory_lock_event)
			advisory_locks_lock.release()
			if !blocking {
				errno.set(errno.eagain)
				return none
			}
			mut events := [&advisory_lock_event]
			event.await_from_generation(mut events, true, 0, generation) or {
				unsafe { events.free() }
				errno.set(errno.eintr)
				return none
			}
			unsafe { events.free() }
			continue
		}
		replace_owner_range(resource_id, owner, lock_class_posix, range.start, range.end,
			true, write, int(owner))
		advisory_locks_lock.release()
		return
	}
}

fn get_posix_lock(handle &Handle, mut flock Flock) ? {
	range := normalize_lock(handle, flock)?
	resource_id := lock_resource_id(handle.resource)
	owner := u64(proc.current_thread().process.pid)
	write := flock.l_type == f_wrlck
	advisory_locks_lock.acquire()
	conflict := conflicting_lock(resource_id, owner, lock_class_posix, range.start,
		range.end, write) or {
		advisory_locks_lock.release()
		flock.l_type = f_unlck
		flock.l_pid = 0
		return
	}
	advisory_locks_lock.release()
	flock.l_type = if conflict.write { f_wrlck } else { f_rdlck }
	flock.l_whence = 0
	flock.l_start = i64(conflict.start)
	flock.l_len = if conflict.end == u64(-1) { 0 } else { i64(conflict.end - conflict.start) }
	flock.l_pid = conflict.pid
}

fn release_posix_locks(res &resource.Resource, pid int) {
	resource_id := lock_resource_id(res)
	advisory_locks_lock.acquire()
	mut next := []AdvisoryLock{cap: advisory_locks.len}
	mut changed := false
	for held in advisory_locks {
		if held.class == lock_class_posix && held.resource_id == resource_id
			&& held.owner == u64(pid) {
			changed = true
			continue
		}
		next << held
	}
	if changed {
		unsafe {
			advisory_locks.free()
			advisory_locks = next
		}
	} else {
		unsafe { next.free() }
	}
	advisory_locks_lock.release()
	if changed { notify_lock_waiters() }
}

fn release_flock(handle &Handle) {
	resource_id := lock_resource_id(handle.resource)
	owner := u64(handle)
	advisory_locks_lock.acquire()
	mut next := []AdvisoryLock{cap: advisory_locks.len}
	mut changed := false
	for held in advisory_locks {
		if held.class == lock_class_flock && held.resource_id == resource_id
			&& held.owner == owner {
			changed = true
			continue
		}
		next << held
	}
	if changed {
		unsafe {
			advisory_locks.free()
			advisory_locks = next
		}
	} else {
		unsafe { next.free() }
	}
	advisory_locks_lock.release()
	if changed { notify_lock_waiters() }
}

pub fn syscall_flock(_ voidptr, fdnum int, operation int) (u64, u64) {
	if operation & ~(lock_sh | lock_ex | lock_nb | lock_un) != 0
		|| (operation & lock_un == 0 && (operation & lock_sh == 0) == (operation & lock_ex == 0)) {
		return errno.err, errno.einval
	}
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer { fd.unref() }
	mut handle := fd.handle
	if !stat.isreg(handle.resource.stat.mode) && !stat.isdir(handle.resource.stat.mode) {
		return errno.err, errno.einval
	}
	resource_id := lock_resource_id(handle.resource)
	owner := u64(handle)

	// Conversion first releases the old whole-file lock held by this open file
	// description, matching Linux's non-atomic conversion semantics.
	release_flock(handle)
	if operation & lock_un != 0 {
		return 0, 0
	}
	write := operation & lock_ex != 0
	for {
		advisory_locks_lock.acquire()
		if _ := conflicting_lock(resource_id, owner, lock_class_flock, 0, u64(-1), write) {
			generation := event.generation(mut advisory_lock_event)
			advisory_locks_lock.release()
			if operation & lock_nb != 0 {
				return errno.err, errno.ewouldblock
			}
			mut events := [&advisory_lock_event]
			event.await_from_generation(mut events, true, 0, generation) or {
				unsafe { events.free() }
				return errno.err, errno.eintr
			}
			unsafe { events.free() }
			continue
		}
		advisory_locks << AdvisoryLock{resource_id, owner, lock_class_flock, 0,
			u64(-1), write, 0}
		advisory_locks_lock.release()
		return 0, 0
	}
	return errno.err, errno.eintr
}

fn fcntl_lock(mut handle Handle, cmd int, arg u64) (u64, u64) {
	if arg == 0 {
		return errno.err, errno.efault
	}
	mut flock := Flock{}
	if !usercopy.copy_from_user(voidptr(&flock), arg, sizeof(Flock)) {
		return errno.err, errno.efault
	}
	if flock.l_type != f_rdlck && flock.l_type != f_wrlck && flock.l_type != f_unlck {
		return errno.err, errno.einval
	}
	if !stat.isreg(handle.resource.stat.mode) {
		return errno.err, errno.ebadf
	}
	access := handle.flags & resource.o_accmode
	if flock.l_type == f_rdlck && access == resource.o_wronly {
		return errno.err, errno.ebadf
	}
	if flock.l_type == f_wrlck && access != resource.o_wronly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	if cmd == f_getlk {
		if flock.l_type == f_unlck {
			return errno.err, errno.einval
		}
		get_posix_lock(handle, mut flock) or { return errno.err, errno.get() }
		if !usercopy.copy_to_user(arg, voidptr(&flock), sizeof(Flock)) {
			return errno.err, errno.efault
		}
		return 0, 0
	}
	set_posix_lock(mut handle, mut flock, cmd == f_setlkw) or {
		return errno.err, errno.get()
	}
	return 0, 0
}
