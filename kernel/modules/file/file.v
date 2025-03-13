// file.v: FDs and their operations.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

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

pub const f_dupfd = 0
pub const f_dupfd_cloexec = 1030
pub const f_getfd = 1
pub const f_setfd = 2
pub const f_getfl = 3
pub const f_setfl = 4
pub const f_getlk = 5
pub const f_setlk = 6
pub const f_setlkw = 7
pub const f_getown = 8
pub const f_setown = 9

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

pub fn syscall_ppoll(_ voidptr, fds &PollFD, nfds u64, tmo_p &time.TimeSpec, sigmask &u64) (u64, u64) {
	mut t := proc.current_thread()
	mut process := t.process

	C.printf(c'\n\e[32m%s\e[m: ppoll(0x%llx, %llu, 0x%llx, 0x%llx)\n', process.name.str,
		voidptr(fds), nfds, voidptr(tmo_p), voidptr(sigmask))
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
			fdd.revents = file.pollnval
			ret++
			continue
		}

		mut resource_ := fd.handle.resource

		status := resource_.status

		if i16(status) & fdd.events != 0 {
			fdd.revents = i16(status) & fdd.events
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

		if i16(status) & fdd.events != 0 {
			C.printf(c'Poll exiting on fdnum %d, events %llx\n', fdd.fd, fdd.events)

			fdd.revents = 0
			fdd.revents = i16(status) & fdd.events
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
	this.handle.refcount--
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

	mut handle := fd.handle
	mut res := handle.resource

	res.unref(voidptr(handle))?

	handle.refcount--
	if handle.refcount == 0 {
		unsafe { free(voidptr(handle)) }
	}

	unsafe { free(voidptr(fd)) }

	process.fds[fdnum] = unsafe { nil }
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

	ret.handle.refcount++

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

	mut new_fd := unsafe { &FD(malloc(sizeof(FD))) }
	unsafe { C.memcpy(new_fd, oldfd, sizeof(FD)) }

	new_fdnum := fdnum_create_from_fd(new_process, new_fd, newfdnum, specific) or {
		oldfd.unref()
		return none
	}

	new_fd.flags = flags & resource.file_descriptor_flags_mask
	if cloexec {
		new_fd.flags &= resource.o_cloexec
	}

	oldfd.handle.refcount++
	oldfd.handle.resource.refcount++

	return new_fdnum
}

pub fn syscall_dup3(_ voidptr, oldfdnum int, newfdnum int, flags int) (u64, u64) {
	mut t := proc.current_thread()
	mut process := t.process

	C.printf(c'\n\e[32m%s\e[m: dup3(%d, %d, %d)\n', process.name.str, oldfdnum, newfdnum,
		flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	new_fdnum := fdnum_dup(unsafe { nil }, oldfdnum, unsafe { nil }, newfdnum, flags,
		true, false) or { return errno.err, errno.get() }

	return u64(new_fdnum), 0
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
		file.f_dupfd {
			ret = u64(fdnum_dup(unsafe { nil }, fdnum, unsafe { nil }, int(arg), 0, false,
				false) or { return errno.err, errno.get() })
		}
		file.f_dupfd_cloexec {
			ret = u64(fdnum_dup(unsafe { nil }, fdnum, unsafe { nil }, int(arg), 0, false,
				true) or { return errno.err, errno.get() })
		}
		file.f_getfd {
			ret = if fd.flags & resource.o_cloexec != 0 { u64(file.fd_cloexec) } else { 0 }
			fd.unref()
		}
		file.f_setfd {
			fd.flags = if arg & file.fd_cloexec != 0 { resource.o_cloexec } else { 0 }
			fd.unref()
		}
		file.f_getfl {
			ret = u64(handle.flags)
			fd.unref()
		}
		file.f_setfl {
			handle.flags = int(arg)
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

	ret := mmap.mmap(process.pagemap, addr, length, prot, flags, resource_, offset) or {
		return errno.err, errno.get()
	}

	return u64(ret), 0
}
