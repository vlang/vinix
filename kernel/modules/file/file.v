module file

import resource
import proc
import klock

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

pub struct FD {
pub mut:
	handle &Handle
	refcount int
	flags int
}

pub fn (mut this FD) unref() {
	this.refcount--
	this.handle.refcount--
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

pub fn fd_create_from_resource(res &resource.Resource, flags int) ?&FD {
	mut new_handle := unsafe { &Handle(C.malloc(sizeof(Handle))) }
	new_handle.resource = unsafe { res }
	new_handle.refcount = 1
	new_handle.flags = flags & resource.file_status_flags_mask

	mut new_fd := unsafe { &FD(C.malloc(sizeof(FD))) }
	new_fd.handle = new_handle
	new_fd.refcount = 1
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

	ret.handle.refcount++
	ret.refcount++

	return ret
}
