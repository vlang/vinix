// epoll.v: epoll() implementation.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module file

import resource
import stat
import klock
import event
import event.eventstruct
import errno
import proc

pub const (
	epollin        = 0x001
	epollpri       = 0x002
	epollout       = 0x004
	epollrdnorm    = 0x040
	epollrdband    = 0x080
	epollwrnorm    = 0x100
	epollwrband    = 0x200
	epollmsg       = 0x400
	epollerr       = 0x008
	epollhup       = 0x010
	epollrdhup     = 0x2000
	epollexclusive = u32(1) << 28
	epollwakeup    = u32(1) << 29
	epolloneshot   = u32(1) << 30
	epollet        = u32(1) << 31
	epoll_cloexec  = 1
	epoll_ctl_add  = 1
	epoll_ctl_del  = 2
	epoll_ctl_mod  = 3
)

union EPollData {
mut:
	ptr    voidptr
	fd     int
	uint32 u32
	uint64 u64
}

struct EPollEvent {
mut:
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
	return none
}

fn (mut this EPoll) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut this EPoll) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return none
}

fn (mut this EPoll) unref(handle voidptr) ? {
	return none
}

fn (mut this EPoll) link(handle voidptr) ? {
	return none
}

fn (mut this EPoll) unlink(handle voidptr) ? {
	return none
}

fn (mut this EPoll) grow(handle voidptr, new_size u64) ? {
	return none
}

pub fn syscall_epoll_ctl(_ voidptr, epfdnum int, op int, fdnum int, event_ &EPollEvent) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: epoll_ctl(%d, %d, %d, 0x%llx)\n', process.name.str, epfdnum,
		op, fdnum, voidptr(event_))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut epoll_fd := fd_from_fdnum(unsafe { nil }, epfdnum) or { return errno.err, errno.get() }
	defer {
		epoll_fd.unref()
	}

	epoll_resource := epoll_fd.handle.resource

	mut epoll := &EPoll(0)

	if epoll_resource is EPoll {
		epoll = epoll_resource
	} else {
		return errno.err, errno.einval
	}

	match op {
		file.epoll_ctl_add {
			if fdnum in epoll.table {
				return errno.err, errno.eexist
			}

			mut event_copy := &EPollEvent{}
			unsafe {
				*event_copy = *event_
			}
			epoll.table[fdnum] = event_copy
		}
		file.epoll_ctl_mod {
			if fdnum !in epoll.table {
				return errno.err, errno.enoent
			}

			mut event_copy := &EPollEvent{}
			unsafe {
				*event_copy = *event_
			}
			epoll.table[fdnum] = event_copy
		}
		file.epoll_ctl_del {
			if fdnum !in epoll.table {
				return errno.err, errno.enoent
			}

			epoll.table.delete(fdnum)
		}
		else {
			return errno.err, errno.einval
		}
	}

	return 0, 0
}

pub fn syscall_epoll_pwait(_ voidptr, epfdnum int, ret_events &EPollEvent, maxevents int, timeout int, sigmask &u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: epoll_pwait(%d, 0x%llx, %d, %d, 0x%llx)\n', process.name.str,
		epfdnum, voidptr(ret_events), maxevents, timeout, voidptr(sigmask))
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut epoll_fd := fd_from_fdnum(unsafe { nil }, epfdnum) or { return errno.err, errno.get() }
	defer {
		epoll_fd.unref()
	}

	epoll_resource := epoll_fd.handle.resource

	mut epoll := &EPoll(0)

	if epoll_resource is EPoll {
		epoll = epoll_resource
	} else {
		return errno.err, errno.einval
	}

	mut thread := proc.current_thread()

	oldmask := thread.masked_signals
	if voidptr(sigmask) != unsafe { nil } {
		thread.masked_signals = unsafe { *sigmask }
	}
	defer {
		thread.masked_signals = oldmask
	}

	mut fdlist := []&FD{}
	mut epoll_events := []EPollEvent{}
	mut events := []&eventstruct.Event{}

	defer {
		for mut f in fdlist {
			f.unref()
		}
	}

	mut i := int(0)
	for fdnum, epoll_event in epoll.table {
		if i >= maxevents {
			break
		}

		mut event_ := unsafe { &ret_events[i] }

		mut fd := fd_from_fdnum(unsafe { nil }, fdnum) or {
			event_.events = file.epollerr
			event_.data.fd = fdnum
			i++
			continue
		}

		mut resource_ := fd.handle.resource

		status := resource_.status

		if u32(status) & epoll_event.events != 0 {
			event_.events = u32(status) & epoll_event.events
			i++
			fd.unref()
			continue
		}

		fdlist << fd
		epoll_events << epoll_event
		events << &resource_.event
	}

	if i != 0 || events.len == 0 {
		return u64(i), 0
	}

	for {
		which := event.await(mut events, true) or { return errno.err, errno.eintr }

		status := fdlist[which].handle.resource.status

		mut epoll_event := unsafe { &epoll_events[which] }
		mut event_ := unsafe { &ret_events[0] }

		if u32(status) & epoll_event.events != 0 {
			event_.events = u32(status) & epoll_event.events
			i = 1
			break
		}
	}

	return u64(i), 0
}

pub fn syscall_epoll_create(_ voidptr, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: epoll_create(%d)\n', process.name.str, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	cloexec := if flags & file.epoll_cloexec != 0 { resource.o_cloexec } else { 0 }

	mut e := &EPoll{
		refcount: 1
	}

	epoll_fdnum := fdnum_create_from_resource(unsafe { nil }, mut e, cloexec, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(epoll_fdnum), 0
}
