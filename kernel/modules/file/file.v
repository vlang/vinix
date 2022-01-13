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

pub const (
	f_dupfd = 1
	f_dupfd_cloexec = 2
	f_getfd = 3
	f_setfd = 4
	f_getfl = 5
	f_setfl = 6
	f_getlk = 7
	f_setlk = 8
	f_setlkw = 9
	f_getown = 10
	f_setown = 11

	fd_cloexec = 1
)

pub struct Handle {
pub mut:
	l             klock.Lock
	resource      &resource.Resource
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

pub const (
	pollin = 0x01
	pollout = 0x02
	pollpri = 0x04
	pollhup = 0x08
	pollerr = 0x10
	pollrdhup = 0x20
	pollnval = 0x40
	pollwrnorm = 0x80
)

pub fn syscall_ppoll(_ voidptr, fds &PollFD, nfds u64, tmo_p &time.TimeSpec, sigmask &u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: ppoll(0x%llx, %llu, 0x%llx, 0x%llx)\n', voidptr(fds),
		nfds, voidptr(tmo_p), voidptr(sigmask))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	if nfds == 0 {
		return 0, 0
	}

	mut thread := proc.current_thread()

	oldmask := thread.masked_signals
	if voidptr(sigmask) != voidptr(0) {
		thread.masked_signals = unsafe { sigmask[0] }
	}
	defer {
		thread.masked_signals = oldmask
	}

	mut fdlist := []&FD{}
	mut fdnums := []u64{}
	mut events := []&eventstruct.Event{}

	defer {
		for mut f in fdlist {
			f.unref()
		}
	}

	mut ret := u64(0)

	for i := u64(0); i < nfds; i++ {
		mut fdd := unsafe { &fds[i] }

		if fdd.fd < 0 {
			fdd.revents = 0
			continue
		}

		mut fd := fd_from_fdnum(voidptr(0), fdd.fd) or {
			fdd.revents = file.pollnval
			ret++
			continue
		}

		mut resource := fd.handle.resource

		status := resource.status

		if i16(status) & fdd.events != 0 {
			fdd.revents = 0
			fdd.revents = i16(status) & fdd.events
			ret++
			fd.unref()
			continue
		}

		fdlist << fd
		fdnums << i
		events << &resource.event
	}

	if ret != 0 {
		return ret, 0
	}

	mut timer := &time.Timer(0)

	if voidptr(tmo_p) != voidptr(0) {
		mut target_time := *tmo_p
		target_time.add(monotonic_clock)

		timer = time.new_timer(target_time)

		events << &timer.event
	}

	defer {
		if voidptr(timer) != voidptr(0) {
			timer.delete()
		}
	}

	for {
		which := event.await(mut events, true) or { return -1, errno.eintr }

		if voidptr(timer) != voidptr(0) {
			if which == events.len - 1 {
				return 0, 0
			}
		}

		status := fdlist[which].handle.resource.status

		mut fdd := unsafe { &fds[fdnums[which]] }

		if i16(status) & fdd.events != 0 {
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
	handle &Handle
	flags  int
}

pub fn (mut this FD) unref() {
	this.handle.refcount--
}

pub fn fdnum_close(_process &proc.Process, fdnum int) ? {
	mut process := &proc.Process(0)
	if voidptr(_process) == voidptr(0) {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	if fdnum >= proc.max_fds {
		errno.set(errno.ebadf)
		return error('')
	}

	process.fds_lock.acquire()
	defer {
		process.fds_lock.release()
	}

	mut fd := &FD(process.fds[fdnum])
	if voidptr(fd) == voidptr(0) {
		errno.set(errno.ebadf)
		return error('')
	}

	mut handle := fd.handle
	mut res := handle.resource

	res.unref(voidptr(handle)) ?

	handle.refcount--
	if handle.refcount == 0 {
		C.free(voidptr(handle))
	}

	C.free(voidptr(fd))

	process.fds[fdnum] = voidptr(0)
}

pub fn fdnum_create_from_fd(_process &proc.Process, fd &FD, oldfd int, specific bool) ?int {
	mut process := &proc.Process(0)
	if voidptr(_process) == voidptr(0) {
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
			if process.fds[i] == voidptr(0) {
				process.fds[i] = voidptr(fd)
				return i
			}
		}
		return none
	} else {
		// fdnum_close(process, oldfd) or {}
		process.fds[oldfd] = voidptr(fd)
		return oldfd
	}
}

pub fn fd_create_from_resource(mut res resource.Resource, flags int) ?&FD {
	katomic.inc(res.refcount)

	mut new_handle := unsafe { &Handle(C.malloc(sizeof(Handle))) }
	new_handle.resource = unsafe { res }
	new_handle.refcount = 1
	new_handle.flags = flags & resource.file_status_flags_mask
	new_handle.dirlist = []stat.Dirent{}

	mut new_fd := unsafe { &FD(C.malloc(sizeof(FD))) }
	new_fd.handle = new_handle
	new_fd.flags = flags & resource.file_descriptor_flags_mask

	return new_fd
}

pub fn fdnum_create_from_resource(_process &proc.Process, mut res resource.Resource, flags int, oldfd int, specific bool) ?int {
	new_fd := fd_create_from_resource(mut res, flags) or { return none }
	return fdnum_create_from_fd(_process, new_fd, oldfd, specific)
}

pub fn fd_from_fdnum(_process &proc.Process, fdnum int) ?&FD {
	mut process := &proc.Process(0)
	if voidptr(_process) == voidptr(0) {
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

	mut ret := &FD(process.fds[fdnum])
	if voidptr(ret) == voidptr(0) {
		errno.set(errno.ebadf)
		return none
	}

	ret.handle.refcount++

	return ret
}

pub fn fdnum_dup(_old_process &proc.Process, oldfdnum int, _new_process &proc.Process, newfdnum int, flags int, specific bool) ?int {
	mut old_process := &proc.Process(0)
	if voidptr(_old_process) == voidptr(0) {
		old_process = proc.current_thread().process
	} else {
		old_process = unsafe { _old_process }
	}

	mut new_process := &proc.Process(0)
	if voidptr(_new_process) == voidptr(0) {
		new_process = proc.current_thread().process
	} else {
		new_process = unsafe { _new_process }
	}

	if specific && oldfdnum == newfdnum && voidptr(old_process) == voidptr(new_process) {
		errno.set(errno.einval)
		return none
	}

	mut oldfd := fd_from_fdnum(old_process, oldfdnum) or { return none }

	mut new_fd := unsafe { &FD(C.malloc(sizeof(FD))) }
	unsafe { C.memcpy(new_fd, oldfd, sizeof(FD)) }

	new_fdnum := fdnum_create_from_fd(new_process, new_fd, newfdnum, specific) or {
		oldfd.unref()
		return none
	}

	new_fd.flags = flags & resource.file_descriptor_flags_mask

	oldfd.handle.refcount++
	oldfd.handle.resource.refcount++

	return new_fdnum
}

pub fn syscall_dup3(_ voidptr, oldfdnum int, newfdnum int, flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: dup3(%d, %d, %d)\n', oldfdnum, newfdnum, flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	new_fdnum := fdnum_dup(voidptr(0), oldfdnum, voidptr(0), newfdnum, flags, true) or {
		return -1, errno.get()
	}

	return u64(new_fdnum), 0
}

pub fn syscall_fcntl(_ voidptr, fdnum int, cmd int, arg u64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: fcntl(%d, %d, %lld)\n', fdnum, cmd, arg)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut fd := fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.ebadf }

	mut handle := fd.handle

	mut ret := u64(0)

	match cmd {
		file.f_dupfd {
			ret = u64(fdnum_dup(voidptr(0), fdnum, voidptr(0), int(arg), 0, false) or {
				return -1, errno.get()
			})
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
			print('\nfcntl: Unhandled command: $cmd\n')
			fd.unref()
			return -1, errno.einval
		}
	}

	return ret, 0
}

pub fn syscall_mmap(_ voidptr, addr voidptr, length u64, prot_and_flags u64, fdnum int, offset i64) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: mmap(0x%llx, 0x%llx, 0x%llx, %d, %lld)\n', addr, length,
		prot_and_flags, fdnum, offset)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut resource := &resource.Resource(voidptr(0))
	mut fd := &FD(voidptr(0))

	if fdnum != -1 {
		fd = fd_from_fdnum(voidptr(0), fdnum) or { return -1, errno.get() }
		resource = fd.handle.resource
	}

	defer {
		if fdnum != -1 {
			fd.unref()
		}
	}

	prot := int((prot_and_flags >> 32) & 0xffffffff)
	flags := int(prot_and_flags & 0xffffffff)

	if flags & mmap.map_anonymous == 0 && voidptr(resource) == voidptr(0) {
		return -1, errno.ebadf
	}

	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	ret := mmap.mmap(process.pagemap, addr, length, prot, flags, resource, offset) or {
		return -1, errno.get()
	}

	return u64(ret), 0
}
