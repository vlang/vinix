module file

import resource
import stat
import klock
import event
import event.eventstruct
import errno

pub const epoll_cloexec = 1

struct EPoll {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this EPoll) mmap(page u64, flags int) voidptr {
	panic('')
}

fn (mut this EPoll) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this EPoll) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this EPoll) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return error('')
}

fn (mut this EPoll) unref(handle voidptr) ? {
	return error('')
}

fn (mut this EPoll) grow(handle voidptr, new_size u64) ? {
	return error('')
}

fn (mut this EPoll) bind(handle voidptr, _addr voidptr, addrlen u64) ? {
	return resource.default_bind(handle, _addr, addrlen)
}

fn (mut this EPoll) listen(handle voidptr, backlog int) ? {
	return resource.default_listen(handle, backlog)
}

pub fn syscall_epoll_create(_ voidptr, flags int) (u64, u64) {
	cloexec := if flags & epoll_cloexec != 0 {
		resource.o_cloexec
	} else {
		0
	}

	mut e := &EPoll{
		refcount: 1
	}

	epoll_fdnum := file.fdnum_create_from_resource(voidptr(0), mut e, cloexec, 0, false) or {
		return -1, errno.get()
	}

	return u64(epoll_fdnum), 0
}
