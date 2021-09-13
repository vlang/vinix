module netlink

import stat
import klock
import event.eventstruct
import socket.public as sock_pub

struct NetlinkSocket {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event
}

fn (mut this NetlinkSocket) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this NetlinkSocket) read(_handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	return error('')
}

fn (mut this NetlinkSocket) write(handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	return error('')
}

fn (mut this NetlinkSocket) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return error('')
}

fn (mut this NetlinkSocket) unref(handle voidptr) ? {
	return error('')
}

fn (mut this NetlinkSocket) grow(handle voidptr, new_size u64) ? {
	return error('')
}

fn (mut this NetlinkSocket) bind(handle voidptr, _addr voidptr, addrlen u64) ? {
	return error('')
}

pub fn create(@type int, protocol int) ?&NetlinkSocket {
	return &NetlinkSocket{refcount: 1}
}
