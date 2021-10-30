module file

import resource
import stat
import klock
import event
import event.eventstruct
import errno

pub const epollin = 0x001

pub const epollpri = 0x002

pub const epollout = 0x004

pub const epollrdnorm = 0x040

pub const epollrdband = 0x080

pub const epollwrnorm = 0x100

pub const epollwrband = 0x200

pub const epollmsg = 0x400

pub const epollerr = 0x008

pub const epollhup = 0x010

pub const epollrdhup = 0x2000

pub const epollexclusive = u32(1) << 28

pub const epollwakeup = u32(1) << 29

pub const epolloneshot = u32(1) << 30

pub const epollet = u32(1) << 31

pub const epoll_cloexec = 1

pub const epoll_ctl_add = 1

pub const epoll_ctl_del = 2

pub const epoll_ctl_mod = 3

union EPollData {
	ptr    voidptr
	fd     int
	uint32 u32
	uint64 u64
}

struct EPollEvent {
	events u32
	data   EPollData
}

struct EPoll {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	table map[int]&EPollEvent
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

pub fn syscall_epoll_ctl(_ voidptr, epfdnum int, op int, fdnum int, event &EPollEvent) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: epoll_ctl(%d, %d, %d, 0x%llx)\n', epfdnum, op, fdnum,
		voidptr(event))
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut epoll_fd := fd_from_fdnum(voidptr(0), epfdnum) or { return -1, errno.get() }
	defer {
		epoll_fd.unref()
	}

	epoll_resource := epoll_fd.handle.resource

	mut epoll := &EPoll(voidptr(0))

	if epoll_resource is EPoll {
		epoll = epoll_resource
	} else {
		return -1, errno.einval
	}

	match op {
		file.epoll_ctl_add {
			if fdnum in epoll.table {
				return -1, errno.eexist
			}

			mut event_copy := &EPollEvent{}
			unsafe {
				*event_copy = *event
			}
			epoll.table[fdnum] = event_copy
		}
		file.epoll_ctl_mod {
			if fdnum !in epoll.table {
				return -1, errno.enoent
			}

			mut event_copy := &EPollEvent{}
			unsafe {
				*event_copy = *event
			}
			epoll.table[fdnum] = event_copy
		}
		file.epoll_ctl_del {
			if fdnum !in epoll.table {
				return -1, errno.enoent
			}

			epoll.table.delete(fdnum)
		}
		else {
			return -1, errno.einval
		}
	}

	return 0, 0
}

pub fn syscall_epoll_create(_ voidptr, flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: epoll_create(%d)\n', flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	cloexec := if flags & file.epoll_cloexec != 0 { resource.o_cloexec } else { 0 }

	mut e := &EPoll{
		refcount: 1
	}

	epoll_fdnum := fdnum_create_from_resource(voidptr(0), mut e, cloexec, 0, false) or {
		return -1, errno.get()
	}

	return u64(epoll_fdnum), 0
}
