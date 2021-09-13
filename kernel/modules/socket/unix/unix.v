module unix

import stat
import klock
import event.eventstruct
import socket.public as sock_pub

struct UnixSocket {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event
}

fn (mut this UnixSocket) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this UnixSocket) read(_handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	return error('')
}

fn (mut this UnixSocket) write(handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	return error('')
}

fn (mut this UnixSocket) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return error('')
}

fn (mut this UnixSocket) unref(handle voidptr) ? {
	return error('')
}

fn (mut this UnixSocket) grow(handle voidptr, new_size u64) ? {
	return error('')
}

pub fn create(@type int) ?&UnixSocket {
	return &UnixSocket{refcount: 1}
}
