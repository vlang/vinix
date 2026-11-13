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
const lock_class_ofd = 2
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
		// Linux validates the inclusive last byte. The exclusive end can
		// be INT64_MAX + 1; represent that endpoint with the same sentinel
		// as length zero, since Linux reports both as l_len == 0.
		if anchor > i64(0x7fffffffffffffff) - (flock.l_len - 1) {
			errno.set(errno.eoverflow)
			return none
		}
		last := anchor + (flock.l_len - 1)
		return LockRange{u64(anchor), if last == i64(0x7fffffffffffffff) {
			u64(-1)
		} else { u64(last) + 1 }}
	}
	if flock.l_len < -anchor {
		errno.set(errno.einval)
		return none
	}
	return LockRange{u64(anchor + flock.l_len), u64(anchor)}
}

fn conflicting_lock(resource_id voidptr, owner u64, class int, start u64, end u64,
	write bool, own bool) ?AdvisoryLock {
	for held in advisory_locks {
		// Linux F_OFD_GETLK with F_UNLCK queries the description's own
		// ranges, including compatible readers; it does not remove them.
		if own {
			if held.resource_id == resource_id && held.class == class && held.owner == owner
				&& ranges_overlap(held.start, held.end, start, end) { return held }
			continue
		}
		// flock has a separate conflict domain. POSIX and OFD record locks
		// conflict even when the same process acquired both on one handle.
		if held.resource_id != resource_id
			|| (held.class == lock_class_flock) != (class == lock_class_flock)
			|| (held.class == class && held.owner == owner)
			|| !ranges_overlap(held.start, held.end, start, end) {
			continue
		}
		if write || held.write {
			return held
		}
	}
	return none
}

// Remove the requested part of this owner's existing record ranges. Preserved
// prefixes and suffixes make partial unlock/replacement behave byte-for-byte.
fn replace_owner_range(resource_id voidptr, owner u64, class int, start u64, end u64,
	add bool, write bool, pid int) {
	// It replaces advisory_locks, which is freed here.
	mut next := []AdvisoryLock{cap: advisory_locks.len + 2} @[freed]
	next.flags |= .noslices
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
		// Coalesce adjacent ranges of the same kind. The table is unsorted,
		// so extend to a fixed point before compacting it in place.
		mut merged_start := start
		mut merged_end := end
		for {
			mut extended := false
			for held in next {
				if held.resource_id == resource_id && held.class == class
					&& held.owner == owner && held.write == write
					&& held.start <= merged_end && merged_start <= held.end {
					if held.start < merged_start { merged_start = held.start; extended = true }
					if held.end > merged_end { merged_end = held.end; extended = true }
				}
			}
			if !extended { break }
		}
		mut kept := 0
		for held in next {
			if held.resource_id == resource_id && held.class == class
				&& held.owner == owner && held.write == write
				&& held.start <= merged_end && merged_start <= held.end { continue }
			next[kept] = held
			kept++
		}
		next.trim(kept)
		next << AdvisoryLock{resource_id, owner, class, merged_start, merged_end, write, pid}
	}
	unsafe {
		advisory_locks.free()
		advisory_locks = next
	}
}

fn notify_lock_waiters() {
	event.trigger(mut advisory_lock_event, false)
}

fn set_record_lock(mut handle Handle, mut flock Flock, blocking bool, ofd bool, range LockRange) ? {
	resource_id := lock_resource_id(handle.resource)
	owner := if ofd { u64(voidptr(handle)) } else { u64(proc.current_thread().process.pid) }
	class := if ofd { lock_class_ofd } else { lock_class_posix }
	pid := if ofd { -1 } else { int(owner) }
	if flock.l_type == f_unlck {
		advisory_locks_lock.acquire()
		replace_owner_range(resource_id, owner, class, range.start, range.end,
			false, false, pid)
		advisory_locks_lock.release()
		notify_lock_waiters()
		return
	}

	write := flock.l_type == f_wrlck
	for {
		advisory_locks_lock.acquire()
		if _ := conflicting_lock(resource_id, owner, class, range.start,
			range.end, write, false) {
			generation := event.generation(mut advisory_lock_event)
			advisory_locks_lock.release()
			if !blocking {
				errno.set(errno.eagain)
				return none
			}
			event.await_one_from_generation(mut advisory_lock_event, true, generation) or {
				errno.set(errno.eintr)
				return none
			}
			continue
		}
		replace_owner_range(resource_id, owner, class, range.start, range.end,
			true, write, pid)
		advisory_locks_lock.release()
		// A write-to-read conversion can make a blocked reader eligible.
		notify_lock_waiters()
		return
	}
}

fn get_record_lock(handle &Handle, mut flock Flock, ofd bool, range LockRange) ? {
	resource_id := lock_resource_id(handle.resource)
	owner := if ofd { u64(handle) } else { u64(proc.current_thread().process.pid) }
	class := if ofd { lock_class_ofd } else { lock_class_posix }
	write := flock.l_type == f_wrlck
	advisory_locks_lock.acquire()
	conflict := conflicting_lock(resource_id, owner, class, range.start,
		range.end, write, flock.l_type == f_unlck) or {
		advisory_locks_lock.release()
		flock.l_type = f_unlck
		return
	}
	advisory_locks_lock.release()
	flock.l_type = if conflict.write { f_wrlck } else { f_rdlck }
	flock.l_whence = 0
	flock.l_start = i64(conflict.start)
	flock.l_len = if conflict.end == u64(-1) { 0 } else { i64(conflict.end - conflict.start) }
	flock.l_pid = if conflict.class == lock_class_ofd { i32(-1) } else {
		i32(proc.pid_seen_by_caller(conflict.pid))
	}
}

fn release_posix_locks(res &resource.Resource, pid int) {
	// fcntl_lock only admits regular files. Other resources cannot have
	// record locks, so closing them needs no global lock-table work.
	if !stat.isreg(res.stat.mode) {
		return
	}
	resource_id := lock_resource_id(res)
	advisory_locks_lock.acquire()
	mut next := []AdvisoryLock{cap: advisory_locks.len} @[freed]
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

fn release_description_locks(handle &Handle, only_flock bool) {
	// syscall_flock admits only regular files and directories. Pipe/socket
	// teardown cannot release an entry from this table.
	mode := handle.resource.stat.mode
	if !stat.isreg(mode) && !stat.isdir(mode) {
		return
	}
	resource_id := lock_resource_id(handle.resource)
	owner := u64(handle)
	advisory_locks_lock.acquire()
	mut next := []AdvisoryLock{cap: advisory_locks.len} @[freed]
	mut changed := false
	for held in advisory_locks {
		if (held.class == lock_class_flock || (!only_flock && held.class == lock_class_ofd))
			&& held.resource_id == resource_id
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

pub fn syscall_flock(_ voidptr, fdword int, opword int) (u64, u64) {
	// Linux imports unsigned-int descriptor/operation words. Kernel int is
	// register-sized, so discard upper bits before validation and lookup.
	fdnum := int(u32(fdword))
	operation := int(u32(opword))
	kind := operation & ~lock_nb
	if kind != lock_sh && kind != lock_ex && kind != lock_un {
		return errno.err, errno.einval
	}
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer { fd.unref() }
	mut handle := fd.handle
	access := handle.flags & resource.o_accmode
	if handle.flags & resource.o_path != 0
		|| (kind != lock_un && access != resource.o_rdonly
			&& access != resource.o_wronly && access != resource.o_rdwr) {
		return errno.err, errno.ebadf
	}
	handle.mac_check(proc.mac_metadata) or { return errno.err, errno.get() }
	if !stat.isreg(handle.resource.stat.mode) && !stat.isdir(handle.resource.stat.mode) {
		return errno.err, errno.einval
	}
	resource_id := lock_resource_id(handle.resource)
	owner := u64(handle)

	write := operation & lock_ex != 0
	if kind != lock_un {
		// Repeating the held kind is a no-op on the open description. In
		// particular, do not wake a waiter by briefly dropping this lock.
		advisory_locks_lock.acquire()
		for held in advisory_locks {
			if held.resource_id == resource_id && held.owner == owner
				&& held.class == lock_class_flock && held.write == write {
				advisory_locks_lock.release()
				return 0, 0
			}
		}
		advisory_locks_lock.release()
	}

	// Conversion first releases the old whole-file lock held by this open file
	// description, matching Linux's non-atomic conversion semantics.
	release_description_locks(handle, true)
	if operation & lock_un != 0 {
		return 0, 0
	}
	for {
		advisory_locks_lock.acquire()
		if _ := conflicting_lock(resource_id, owner, lock_class_flock, 0, u64(-1), write, false) {
			generation := event.generation(mut advisory_lock_event)
			advisory_locks_lock.release()
			if operation & lock_nb != 0 {
				return errno.err, errno.ewouldblock
			}
			event.await_one_from_generation(mut advisory_lock_event, true, generation) or {
				return errno.err, errno.eintr
			}
			continue
		}
		// Nothing slices the list, so growing can free the old block.
		advisory_locks.flags |= .noslices
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
	if !stat.isreg(handle.resource.stat.mode) {
		return errno.err, errno.ebadf
	}
	// POSIX GETLK rejects an invalid query kind before range conversion.
	// The OFD query and all setters convert ranges before kind/PID/access
	// validation. Import the normalized range once, before any table work.
	if cmd == f_getlk && flock.l_type != f_rdlck && flock.l_type != f_wrlck {
		return errno.err, errno.einval
	}
	range := normalize_lock(handle, flock) or { return errno.err, errno.get() }
	if flock.l_type != f_rdlck && flock.l_type != f_wrlck && flock.l_type != f_unlck {
		return errno.err, errno.einval
	}
	ofd := cmd == f_ofd_getlk || cmd == f_ofd_setlk || cmd == f_ofd_setlkw
	if cmd == f_getlk || cmd == f_ofd_getlk {
		if ofd && flock.l_pid != 0 { return errno.err, errno.einval }
		get_record_lock(handle, mut flock, ofd, range) or { return errno.err, errno.get() }
		if !usercopy.copy_to_user(arg, voidptr(&flock), sizeof(Flock)) {
			return errno.err, errno.efault
		}
		return 0, 0
	}
	access := handle.flags & resource.o_accmode
	if flock.l_type == f_rdlck && access != resource.o_rdonly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	if flock.l_type == f_wrlck && access != resource.o_wronly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	if ofd && flock.l_pid != 0 { return errno.err, errno.einval }
	set_record_lock(mut handle, mut flock, cmd == f_setlkw || cmd == f_ofd_setlkw, ofd, range) or {
		return errno.err, errno.get()
	}
	return 0, 0
}
