module file

import resource
import proc
import klock

pub const f_dupfd = 1
pub const f_dupfd_cloexec = 2
pub const f_getfd = 3
pub const f_setfd = 4
pub const f_getfl = 5
pub const f_setfl = 6
pub const f_getlk = 7
pub const f_setlk = 8
pub const f_setlkw = 9
pub const f_getown = 10
pub const f_setown = 11

pub const fd_cloexec = 1

pub struct Handle {
pub mut:
	l klock.Lock
	resource &resource.Resource
	node voidptr
	refcount int
	loc i64
	flags int
}

pub fn (mut this Handle) read(buf voidptr, count u64) i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	ret := this.resource.read(buf, u64(this.loc), count)
	if ret > 0 {
		this.loc += ret
	}
	return ret
}

pub fn (mut this Handle) write(buf voidptr, count u64) i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	ret := this.resource.write(buf, u64(this.loc), count)
	if ret > 0 {
		this.loc += ret
	}
	return ret
}

pub struct FD {
pub mut:
	handle &Handle
	flags int
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
		// errno = ebadf
		return error('')
	}

	process.fds_lock.acquire()
	defer {
		process.fds_lock.release()
	}

	mut fd := &FD(process.fds[fdnum])
	if voidptr(fd) == voidptr(0) {
		// errno = ebadf
		return error('')
	}

	mut handle := fd.handle
	mut res := handle.resource

	res.refcount--
	if res.refcount == 0 {
		// res.cleanup()
	}

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
		//fd_close(oldfd)
		process.fds[oldfd] = voidptr(fd)
		return oldfd
	}
}

pub fn fd_create_from_resource(_res &resource.Resource, flags int) ?&FD {
	mut res := unsafe { _res }
	res.refcount++

	mut new_handle := unsafe { &Handle(C.malloc(sizeof(Handle))) }
	new_handle.resource = res
	new_handle.refcount = 1
	new_handle.flags = flags & resource.file_status_flags_mask

	mut new_fd := unsafe { &FD(C.malloc(sizeof(FD))) }
	new_fd.handle = new_handle
	new_fd.flags = flags & resource.file_descriptor_flags_mask

	return new_fd
}

pub fn fdnum_create_from_resource(_process &proc.Process, res &resource.Resource,
								  flags int, oldfd int, specific bool) ?int {
	new_fd := fd_create_from_resource(res, flags) or {
		return none
	}
	return fdnum_create_from_fd(_process, new_fd, oldfd, specific)
}

pub fn fd_from_fdnum(_process &proc.Process, fdnum int) ?&FD {
	mut process := &proc.Process(0)
	if voidptr(_process) == voidptr(0) {
		process = proc.current_thread().process
	} else {
		process = unsafe { _process }
	}

	if fdnum >= proc.max_fds {
		// errno = ebadf
		return none
	}

	process.fds_lock.acquire()
	defer {
		process.fds_lock.release()
	}

	mut ret := &FD(process.fds[fdnum])
	if voidptr(ret) == voidptr(0) {
		// errno = ebadf
		return none
	}

	ret.handle.resource.refcount++
	ret.handle.refcount++

	return ret
}

pub fn syscall_dup3(_ voidptr, oldfdnum int, newfdnum int, flags int) (u64, u64) {
	if oldfdnum == newfdnum {
		// errno = einval
		return -1, -1
	}

	mut oldfd := file.fd_from_fdnum(voidptr(0), oldfdnum) or {
		return -1, -1
	}

	mut new_fd := unsafe { &FD(C.malloc(sizeof(FD))) }
	unsafe { C.memcpy(new_fd, oldfd, sizeof(FD)) }

	mut new_fdnum := fdnum_create_from_fd(voidptr(0), new_fd, newfdnum, true) or {
		oldfd.unref()
		return -1, -1
	}

	new_fd.flags = flags & resource.file_descriptor_flags_mask

	return u64(new_fdnum), 0
}

pub fn syscall_fcntl(_ voidptr, fdnum int, cmd int, arg u64) (u64, u64) {
	mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
		return -1, -1
	}

	mut handle := fd.handle

	mut ret := u64(0)

	match cmd {
		f_dupfd {
			mut new_fd := unsafe { &FD(C.malloc(sizeof(FD))) }
			unsafe { C.memcpy(new_fd, fd, sizeof(FD)) }
			ret = u64(fdnum_create_from_fd(voidptr(0), new_fd, int(arg), false) or {
				fd.unref()
				return -1, -1
			})
		}
		f_getfd {
			ret = if fd.flags & resource.o_cloexec != 0 {
				u64(fd_cloexec)
			} else {
				0
			}
			fd.unref()
		}
		f_setfd {
			fd.flags = if arg & fd_cloexec != 0 {
				resource.o_cloexec
			} else {
				0
			}
			fd.unref()
		}
		f_getfl {
			ret = u64(handle.flags)
			fd.unref()
		}
		f_setfl {
			handle.flags = int(arg)
			fd.unref()
		}
		else {
			print('\nfcntl: Unhandled command: $cmd\n')
			fd.unref()
			return -1, -1
		}
	}

	return ret, 0
}
