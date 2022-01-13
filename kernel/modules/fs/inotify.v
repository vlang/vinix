// inotify.v: FS for monitoring FS events (stub for now).
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module fs

// This is a stub
import resource
import stat
import klock
import file
import errno
import event.eventstruct

struct INotify {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this INotify) mmap(page u64, flags int) voidptr {
	return voidptr(0)
}

fn (mut this INotify) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this INotify) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this INotify) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this INotify) unref(handle voidptr) ? {
	return error('')
}

fn (mut this INotify) grow(handle voidptr, new_size u64) ? {
	return error('')
}

pub fn syscall_inotify_init(_ voidptr, flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: inotify_init(%d)\n', flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut inotify := &INotify{
		refcount: 1
	}

	fdnum := file.fdnum_create_from_resource(voidptr(0), mut inotify, 0, 0, false) or {
		return -1, errno.get()
	}

	return u64(fdnum), 0
}
