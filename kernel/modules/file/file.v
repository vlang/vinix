module file

import resource
import proc
import klock
import katomic
import errno
import stat
import event
import event.eventstruct
import memory.mmap
import time
import usercopy

pub const f_dupfd = 0
pub const f_dupfd_cloexec = 1030
pub const f_getfd = 1
pub const f_setfd = 2
pub const f_getfl = 3
pub const f_setfl = 4

// close_range(2) flags.
pub const close_range_cloexec = u32(1) << 2
pub const f_getlk = 5
pub const f_setlk = 6
pub const f_setlkw = 7
pub const f_getown = 8
pub const f_setown = 9

const f_rdlck = i16(0)
const f_wrlck = i16(1)
const f_unlck = i16(2)

struct Flock {
mut:
	l_type   i16
	l_whence i16
	l_start  i64
	l_len    i64
	l_pid    int
}

pub const fd_cloexec = 1

pub struct Handle {
pub mut:
	l             klock.Lock
	resource      &resource.Resource = unsafe { nil }
	node          voidptr
	refcount      int
	loc           i64
	flags         int
	dirlist_valid bool
	dirlist       []stat.Dirent
	dirlist_index u64
}

// A Handle is the open-file description shared by dup() and fork(). Its
// resource reference must therefore be released exactly once, after both the
// final descriptor and every in-flight lookup have dropped their references.
fn (mut this Handle) unref() {
	if katomic.dec(mut &this.refcount) {
		return
	}

	mut res := this.resource
	res.unref(voidptr(this)) or {}
	unsafe { free(voidptr(this)) }
}

fn retain_mmap_handle(handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	mut open_handle := unsafe { &Handle(handle) }
	katomic.inc(mut &open_handle.refcount)
}

fn release_mmap_handle(handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	mut open_handle := unsafe { &Handle(handle) }
	open_handle.unref()
}

struct PollFD {
mut:
	fd      int
	events  i16
	revents i16
}

pub const pollin = 0x01
pub const pollout = 0x04
pub const pollpri = 0x02
pub const pollhup = 0x10
pub const pollerr = 0x08
pub const pollrdhup = 0x2000
pub const pollnval = 0x20
pub const pollwrnorm = 0x100

// POLLERR and POLLHUP are reported even when userspace did not ask for them.
// In particular, readers use POLLHUP to notice that the final writer of a
// pipe has gone away and drain it to EOF.
fn poll_revents(status int, requested i16) i16 {
	return (i16(status) & requested) | (i16(status) & i16(pollerr | pollhup))
}

pub fn syscall_ppoll(_ voidptr, fds &PollFD, nfds u64, tmo_p &time.TimeSpec, sigmask &u64) (u64, u64) {
	mut t := proc.current_thread()
	mut process := t.process

	C.printf(c'\n\e[32m%s\e[m: ppoll(0x%llx, %llu, 0x%llx, 0x%llx)\n', process.name.str, voidptr(fds), nfds, voidptr(tmo_p), voidptr(sigmask))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	if nfds == 0 {
		return 0, 0
	}

	oldmask := t.masked_signals
	if voidptr(sigmask) != unsafe { nil } {
		t.masked_signals = *sigmask
	}
	defer {
		t.masked_signals = oldmask
	}

	mut fdlist := []&FD{}
	mut fdnums := []u64{}
	mut events := []&eventstruct.Event{}

	defer {
		for mut f in fdlist {
			f.unref()
		}
		unsafe {
			events.free()
			fdnums.free()
			fdlist.free()
		}
	}

	mut ret := u64(0)

	C.printf(c'Polling on %d FDs\n', nfds)

	for i := u64(0); i < nfds; i++ {
		mut fdd := unsafe { &fds[i] }

		fdd.revents = 0

		C.printf(c'fdnum %d, events %llx\n', fdd.fd, fdd.events)

		if fdd.fd < 0 {
			continue
		}

		mut fd := fd_from_fdnum(unsafe { nil }, fdd.fd) or {
			fdd.revents = pollnval
			ret++
			continue
		}

		mut resource_ := fd.handle.resource

		status := resource_.status

		revents := poll_revents(status, fdd.events)
		if revents != 0 {
			fdd.revents = revents
			C.printf(c'Poll detected event on fdnum %d, events %llx\n', fdd.fd, fdd.events)
			ret++
			fd.unref()
			continue
		}

		fdlist << fd
		fdnums << i
		events << &resource_.event
	}

	if ret != 0 {
		return ret, 0
	}

	mut timer := &time.Timer(unsafe { nil })

	if voidptr(tmo_p) != unsafe { nil } {
		mut target_time := *tmo_p

		timer = time.new_timer(target_time)

		events << &timer.event
	}

	defer {
		if voidptr(timer) != unsafe { nil } {
			timer.disarm()
			unsafe { free(timer) }
		}
	}

	for {
		which := event.await(mut events, true) or { return errno.err, errno.eintr }

		if voidptr(timer) != unsafe { nil } {
			if which == u64(events.len) - 1 {
				return 0, 0
			}
		}

		status := fdlist[which].handle.resource.status

		mut fdd := unsafe { &fds[fdnums[which]] }

		revents := poll_revents(status, fdd.events)
		if revents != 0 {
			C.printf(c'Poll exiting on fdnum %d, events %llx\n', fdd.fd, fdd.events)

			fdd.revents = revents
			ret++
			break
		}
	}

	return ret, 0
}

pub fn (mut this Handle) read(buf voidptr, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	ret := this.resource.read(voidptr(this), buf, u64(this.loc), count) or { return none }
	this.loc += ret
	return ret
}

pub fn (mut this Handle) write(buf voidptr, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	ret := this.resource.write(voidptr(this), buf, u64(this.loc), count) or { return none }
	this.loc += ret
	return ret
}

pub fn (mut this Handle) ioctl(request u64, argp voidptr) ?int {
	return this.resource.ioctl(voidptr(this), request, argp)
}

pub struct FD {
pub mut:
	handle &Handle = unsafe { nil }
	flags  int
}

pub fn (mut this FD) unref() {
	mut handle := this.handle
	handle.unref()
}

pub fn fdnum_close(_process &proc.Process, fdnum int, do_lock bool) ? {
	mut process := &proc.Process(unsafe { nil })
	if voidptr(_process) == unsafe { nil } {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	if fdnum >= proc.max_fds {
		errno.set(errno.ebadf)
		return none
	}

	if do_lock {
		process.fds_lock.acquire()
	}
	defer {
		if do_lock {
			process.fds_lock.release()
		}
	}

	mut fd := unsafe { &FD(process.fds[fdnum]) }
	if fd == unsafe { nil } {
		errno.set(errno.ebadf)
		return none
	}

	process.fds[fdnum] = unsafe { nil }
	mut handle := fd.handle
	unsafe { free(voidptr(fd)) }
	handle.unref()
}

pub fn fdnum_create_from_fd(_process &proc.Process, fd &FD, oldfd int, specific bool) ?int {
	mut process := &proc.Process(unsafe { nil })
	if voidptr(_process) == unsafe { nil } {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	process.fds_lock.acquire()
	defer {
		process.fds_lock.release()
	}

	if specific == false {
		for i := oldfd; i < proc.max_fds; i++ {
			if process.fds[i] == unsafe { nil } {
				process.fds[i] = voidptr(fd)
				return i
			}
		}
		return none
	} else {
		fdnum_close(process, oldfd, false) or {}
		process.fds[oldfd] = voidptr(fd)
		return oldfd
	}
}

pub fn fd_create_from_resource(mut res resource.Resource, flags int) ?&FD {
	katomic.inc(mut &res.refcount)

	mut new_handle := &Handle{}
	new_handle.resource = unsafe { res }
	new_handle.refcount = 1
	new_handle.flags = flags & resource.file_status_flags_mask

	mut new_fd := &FD{}
	new_fd.handle = new_handle
	new_fd.flags = flags & resource.file_descriptor_flags_mask

	return new_fd
}

pub fn fdnum_create_from_resource(_process &proc.Process, mut res resource.Resource, flags int, oldfd int, specific bool) ?int {
	new_fd := fd_create_from_resource(mut res, flags) or { return none }
	return fdnum_create_from_fd(_process, new_fd, oldfd, specific)
}

pub fn fd_from_fdnum(_process &proc.Process, fdnum int) ?&FD {
	mut process := &proc.Process(unsafe { nil })
	if voidptr(_process) == unsafe { nil } {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	if fdnum >= proc.max_fds || fdnum < 0 {
		errno.set(errno.ebadf)
		return none
	}

	process.fds_lock.acquire()
	defer {
		process.fds_lock.release()
	}

	mut ret := unsafe { &FD(process.fds[fdnum]) }
	if voidptr(ret) == unsafe { nil } {
		errno.set(errno.ebadf)
		return none
	}

	katomic.inc(mut &ret.handle.refcount)

	return ret
}

pub fn fdnum_dup(_old_process &proc.Process, oldfdnum int, _new_process &proc.Process, newfdnum int, flags int, specific bool, cloexec bool) ?int {
	mut old_process := &proc.Process(unsafe { nil })
	if voidptr(_old_process) == unsafe { nil } {
		old_process = proc.current_thread().process
	} else {
		old_process = unsafe { _old_process }
	}

	mut new_process := &proc.Process(unsafe { nil })
	if voidptr(_new_process) == unsafe { nil } {
		new_process = proc.current_thread().process
	} else {
		new_process = unsafe { _new_process }
	}

	if specific && oldfdnum == newfdnum && voidptr(old_process) == voidptr(new_process) {
		errno.set(errno.einval)
		return none
	}

	mut oldfd := fd_from_fdnum(old_process, oldfdnum) or { return none }
	defer {
		oldfd.unref()
	}

	mut new_fd := unsafe { &FD(malloc(sizeof(FD))) }
	unsafe { C.memcpy(new_fd, oldfd, sizeof(FD)) }
	katomic.inc(mut &oldfd.handle.refcount)

	new_fdnum := fdnum_create_from_fd(new_process, new_fd, newfdnum, specific) or {
		mut handle := new_fd.handle
		unsafe { free(voidptr(new_fd)) }
		handle.unref()
		return none
	}

	new_fd.flags = flags & resource.file_descriptor_flags_mask
	if cloexec {
		new_fd.flags |= resource.o_cloexec
	}

	return new_fdnum
}

pub fn syscall_dup3(_ voidptr, oldfdnum int, newfdnum int, flags int) (u64, u64) {
	mut t := proc.current_thread()
	mut process := t.process

	C.printf(c'\n\e[32m%s\e[m: dup3(%d, %d, %d)\n', process.name.str, oldfdnum, newfdnum, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	// dup2 quietly returns oldfd here; dup3 is required to refuse.
	if oldfdnum == newfdnum {
		return errno.err, errno.einval
	}

	new_fdnum := fdnum_dup(unsafe { nil }, oldfdnum, unsafe { nil }, newfdnum, flags, true, false) or { return errno.err, errno.get() }

	return u64(new_fdnum), 0
}

// close_range(first, last, flags): close every descriptor in the range, or mark
// it close-on-exec when CLOSE_RANGE_CLOEXEC is given. Used by libcs and daemons
// to shed inherited descriptors without walking /proc.
pub fn syscall_close_range(_ voidptr, first u32, last u32, flags u32) (u64, u64) {
	if first > last || flags & ~u32(close_range_cloexec) != 0 {
		return errno.err, errno.einval
	}

	mut process := proc.current_thread().process

	mut top := u64(last)
	if top >= u64(proc.max_fds) {
		top = u64(proc.max_fds) - 1
	}

	for i := u64(first); i <= top; i++ {
		if flags & close_range_cloexec != 0 {
			mut fd := fd_from_fdnum(process, int(i)) or { continue }
			fd.flags |= resource.o_cloexec
			fd.unref()
			continue
		}
		fdnum_close(process, int(i), false) or { continue }
	}

	return 0, 0
}

// fsync/fdatasync. Writes here reach the resource as they are made — there is
// no dirty page cache between a write and its backing store — so there is
// nothing to flush. The descriptor is still validated, because reporting
// success for a closed one would hide a real bug in the caller.
pub fn syscall_fsync(_ voidptr, fdnum int) (u64, u64) {
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	fd.unref()

	return 0, 0
}

// ftruncate(fd, length): set the file's size, zero-filling when it grows.
pub fn syscall_ftruncate(_ voidptr, fdnum int, length i64) (u64, u64) {
	if length < 0 {
		return errno.err, errno.einval
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer {
		fd.unref()
	}

	mut handle := fd.handle
	mut res := handle.resource

	if stat.isdir(res.stat.mode) {
		return errno.err, errno.eisdir
	}
	if handle.flags & resource.o_accmode == resource.o_rdonly {
		return errno.err, errno.einval
	}

	res.grow(voidptr(handle), u64(length)) or { return errno.err, errno.get() }

	return 0, 0
}

pub fn syscall_fcntl(_ voidptr, fdnum int, cmd int, arg u64) (u64, u64) {
	mut t := proc.current_thread()
	mut process := t.process

	C.printf(c'\n\e[32m%s\e[m: fcntl(%d, %d, %lld)\n', process.name.str, fdnum, cmd, arg)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }

	mut handle := fd.handle

	mut ret := u64(0)

	match cmd {
		f_dupfd {
			ret = u64(fdnum_dup(unsafe { nil }, fdnum, unsafe { nil }, int(arg), 0, false, false) or { return errno.err, errno.get() })
		}
		f_dupfd_cloexec {
			ret = u64(fdnum_dup(unsafe { nil }, fdnum, unsafe { nil }, int(arg), 0, false, true) or { return errno.err, errno.get() })
		}
		f_getfd {
			ret = if fd.flags & resource.o_cloexec != 0 { u64(fd_cloexec) } else { 0 }
			fd.unref()
		}
		f_setfd {
			fd.flags = if arg & fd_cloexec != 0 { resource.o_cloexec } else { 0 }
			fd.unref()
		}
		f_getfl {
			ret = u64(handle.flags)
			fd.unref()
		}
		f_setfl {
			// Only the status flags are settable. Taking the argument whole
			// would drop the access mode the file was opened with, leaving a
			// writable handle looking read-only.
			handle.flags = (handle.flags & ~resource.file_settable_flags_mask) | (int(arg) & resource.file_settable_flags_mask)
			fd.unref()
		}
		f_getlk, f_setlk, f_setlkw {
			if arg == 0 {
				fd.unref()
				return errno.err, errno.efault
			}

			mut flock := Flock{}
			if !usercopy.copy_from_user(voidptr(&flock), arg, sizeof(Flock)) {
				fd.unref()
				return errno.err, errno.efault
			}
			if flock.l_type != f_rdlck && flock.l_type != f_wrlck && flock.l_type != f_unlck {
				fd.unref()
				return errno.err, errno.einval
			}

			// Vinix has no advisory-lock owner table yet. With no locks to
			// conflict, F_GETLK reports F_UNLCK and the setters succeed. This is
			// the observable result for the uncontended locks used by SQLite.
			if cmd == f_getlk {
				flock.l_type = f_unlck
				flock.l_pid = 0
				if !usercopy.copy_to_user(arg, voidptr(&flock), sizeof(Flock)) {
					fd.unref()
					return errno.err, errno.efault
				}
			}
			fd.unref()
		}
		else {
			print('\nfcntl: Unhandled command: ${cmd}\n')
			fd.unref()
			return errno.err, errno.einval
		}
	}

	return ret, 0
}

pub fn syscall_mmap(_ voidptr, addr voidptr, length u64, prot_and_flags u64, fdnum int, offset i64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: mmap(0x%llx, 0x%llx, 0x%llx, %d, %lld)\n', process.name.str,
		addr, length, prot_and_flags, fdnum, offset)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut resource_ := &resource.Resource(unsafe { nil })
	mut fd := &FD(unsafe { nil })

	if fdnum != -1 {
		fd = fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
		resource_ = fd.handle.resource
	}

	defer {
		if fdnum != -1 {
			fd.unref()
		}
	}

	prot := int((prot_and_flags >> 32) & 0xffffffff)
	flags := int(prot_and_flags & 0xffffffff)

	if flags & mmap.map_anonymous == 0 && voidptr(resource_) == unsafe { nil } {
		return errno.err, errno.ebadf
	}

	mut mapping_handle := voidptr(0)
	if fdnum != -1 {
		mapping_handle = voidptr(fd.handle)
	}
	ret := mmap.mmap(process.pagemap, addr, length, prot, flags, resource_, offset,
		mapping_handle,
		retain_mmap_handle, release_mmap_handle) or {
		return errno.err, errno.get()
	}

	return u64(ret), 0
}

// Apply descriptor and status flags to an already-open fd. accept4(2) and
// pipe2(2) take them alongside the operation itself rather than needing a
// separate fcntl.
pub fn set_fd_flags(fdnum int, flags int) {
	mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or { return }
	defer {
		fd.unref()
	}

	if flags & resource.o_cloexec != 0 {
		fd.flags |= resource.o_cloexec
	}
	if flags & resource.o_nonblock != 0 {
		mut handle := fd.handle
		handle.flags |= resource.o_nonblock
	}
}
