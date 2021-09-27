module unix

import stat
import klock
import event.eventstruct
import errno
import proc
import fs
import socket.public as sock_pub

struct SockaddrUn {
	sun_family u32
	sun_path   [108]byte
}

struct UnixSocket {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event

	name SockaddrUn
	listening bool
	backlog []&UnixSocket
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

fn (mut this UnixSocket) bind(handle voidptr, _addr voidptr, addrlen u64) ? {
	addr := &SockaddrUn(_addr)

	if addr.sun_family != sock_pub.af_unix {
		errno.set(errno.einval)
		return error('')
	}

	mut thread := proc.current_thread()

	path := unsafe { cstring_to_vstring(&addr.sun_path[0]) }

	mut node := fs.create(thread.process.current_directory, path, stat.ifsock) or {
		return error('')
	}

	node.resource = unsafe { this }

	this.name = *addr
}

fn (mut this UnixSocket) listen(handle voidptr, backlog int) ? {
	this.backlog = []&UnixSocket{cap: backlog}
	this.listening = true
}

pub fn create(@type int) ?&UnixSocket {
	return &UnixSocket{refcount: 1}
}

pub fn create_pair(@type int) ?(&UnixSocket, &UnixSocket) {
	mut a := &UnixSocket{refcount: 1}
	mut b := &UnixSocket{refcount: 1}
	return a, b
}
