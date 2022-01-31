// unix.v: UNIX sockets.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module unix

import stat
import klock
import event.eventstruct
import errno
import proc
import fs
import socket.public as sock_pub
import event
import file

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

	name      SockaddrUn
	listening bool
	backlog   []&UnixSocket

	connected bool
	peer      &UnixSocket
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

fn (mut this UnixSocket) link(handle voidptr) ? {
	return error('')
}

fn (mut this UnixSocket) unlink(handle voidptr) ? {
	return error('')
}

fn (mut this UnixSocket) grow(handle voidptr, new_size u64) ? {
	return error('')
}

fn (mut this UnixSocket) peername(handle voidptr, _addr voidptr, addrlen &u64) ? {
	if this.connected == false {
		errno.set(errno.enotconn)
		return error('')
	}

	mut actual_size := unsafe { *addrlen }
	if actual_size < sizeof(SockaddrUn) {
		actual_size = sizeof(SockaddrUn)
	}

	unsafe { C.memcpy(_addr, voidptr(&this.peer.name), actual_size) }
	unsafe { *addrlen = actual_size }
}

fn (mut this UnixSocket) enqueue(mut sock UnixSocket) ? {
	if this.listening == false {
		errno.set(errno.econnrefused)
		return error('')
	}

	this.backlog << sock

	sock.connected = true
	unsafe { sock.peer = this }

	this.status |= file.pollin
	event.trigger(mut this.event, false)
}

fn (mut this UnixSocket) connect(handle voidptr, _addr voidptr, addrlen u64) ? {
	addr := &SockaddrUn(_addr)

	if addr.sun_family != sock_pub.af_unix {
		errno.set(errno.einval)
		return error('')
	}

	mut thread := proc.current_thread()

	path := unsafe { cstring_to_vstring(&addr.sun_path[0]) }

	C.printf(c'Wants to connect to %s\n', path.str)

	mut target := fs.get_node(thread.process.current_directory, path, true) or {
		return error('')
	}

	target_res := target.resource

	mut socket := &UnixSocket(voidptr(0))

	if target_res is UnixSocket {
		socket = target_res
	} else {
		errno.set(errno.einval)
		return error('')
	}

	socket.enqueue(mut this) or {
		return error('')
	}
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

	this.stat = node.resource.stat
	node.resource = unsafe { this }

	this.name = *addr
}

fn (mut this UnixSocket) listen(handle voidptr, backlog int) ? {
	this.backlog = []&UnixSocket{cap: backlog}
	this.listening = true
}

pub fn create(@type int) ?&UnixSocket {
	return &UnixSocket{
		refcount: 1
		peer: voidptr(0)
	}
}

pub fn create_pair(@type int) ?(&UnixSocket, &UnixSocket) {
	mut a := &UnixSocket{
		refcount: 1
		peer: voidptr(0)
	}
	mut b := &UnixSocket{
		refcount: 1
		peer: voidptr(0)
	}
	return a, b
}
