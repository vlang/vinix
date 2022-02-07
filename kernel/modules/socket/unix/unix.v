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
import resource
import katomic

pub const sock_buf = 4096

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

	connection_event eventstruct.Event
	connected bool
	peer      &UnixSocket


	data      &byte
	read_ptr  u64
	write_ptr u64
	capacity  u64
	used      u64
}

fn (mut this UnixSocket) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this UnixSocket) read(_handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := &file.Handle(_handle)

	// If pipe is empty, block or return if nonblock
	for katomic.load(this.used) == 0 {
		// Return EOF if the pipe was closed
		if this.refcount <= 1 {
			return 0
		}
		if handle.flags & resource.o_nonblock != 0 {
			return 0
		}
		this.l.release()
		mut events := [&this.event]
		event.await(mut events, true) or {
			errno.set(errno.eintr)
			return none
		}
		this.l.acquire()
	}

	if this.used < count {
		count = this.used
	}

	// Calculate sizes before and after wrap-around and new ptr location
	mut before_wrap := u64(0)
	mut after_wrap := u64(0)
	mut new_ptr_loc := u64(0)
	if this.read_ptr + count > this.capacity {
		before_wrap = this.capacity - this.read_ptr
		after_wrap = count - before_wrap
		new_ptr_loc = after_wrap
	} else {
		before_wrap = count
		after_wrap = 0
		new_ptr_loc = this.read_ptr + count
		if new_ptr_loc == this.capacity {
			new_ptr_loc = 0
		}
	}

	unsafe { C.memcpy(buf, &this.data[this.read_ptr], before_wrap) }
	if after_wrap != 0 {
		unsafe { C.memcpy(voidptr(u64(buf) + before_wrap), &this.data[0], after_wrap) }
	}

	this.read_ptr = new_ptr_loc
	this.used -= count

	this.peer.status |= file.epollout
	event.trigger(mut this.peer.event, false)

	return i64(count)
}

fn (mut this UnixSocket) write(handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	mut peer := this.peer

	peer.l.acquire()
	defer {
		peer.l.release()
	}

	// If pipe is full, block or return if nonblock
	for katomic.load(peer.used) == peer.capacity {
		// We don't do nonblock yet
		peer.l.release()
		mut events := [&peer.event]
		event.await(mut events, true) or {
			errno.set(errno.eintr)
			return none
		}
		peer.l.acquire()
	}

	if peer.used + count > peer.capacity {
		count = peer.capacity - peer.used
	}

	// Calculate sizes before and after wrap-around and new ptr location
	mut before_wrap := u64(0)
	mut after_wrap := u64(0)
	mut new_ptr_loc := u64(0)
	if peer.write_ptr + count > peer.capacity {
		before_wrap = peer.capacity - peer.write_ptr
		after_wrap = count - before_wrap
		new_ptr_loc = after_wrap
	} else {
		before_wrap = count
		after_wrap = 0
		new_ptr_loc = peer.write_ptr + count
		if new_ptr_loc == peer.capacity {
			new_ptr_loc = 0
		}
	}

	unsafe { C.memcpy(&peer.data[peer.write_ptr], buf, before_wrap) }
	if after_wrap != 0 {
		unsafe { C.memcpy(&peer.data[0], voidptr(u64(buf) + before_wrap), after_wrap) }
	}

	peer.write_ptr = new_ptr_loc
	peer.used += count

	peer.status |= file.epollin
	event.trigger(mut peer.event, false)

	return i64(count)
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

fn (mut this UnixSocket) accept(_handle voidptr) ?&resource.Resource {
	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := &file.Handle(_handle)

	for this.backlog.len == 0 {
		if handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.ewouldblock)
			return none
		}
		this.l.release()
		mut events := [&this.event]
		event.await(mut events, true) or {
			errno.set(errno.eintr)
			return none
		}
		this.l.acquire()
	}

	mut peer := this.backlog.pop()

	connection_socket := &UnixSocket{
		refcount: 1
		peer: peer
		connected: true
		name: this.name
		data: unsafe { C.malloc(sock_buf) }
		capacity: sock_buf
	}

	peer.refcount++
	peer.peer = connection_socket
	peer.connected = true

	event.trigger(mut peer.connection_event, false)

	mut events := [&this.connection_event]
	event.await(mut events, true) or {
		errno.set(errno.eintr)
		return error('')
	}

	return connection_socket
}

fn (mut this UnixSocket) connect(handle voidptr, _addr voidptr, addrlen u64) ? {
	addr := &SockaddrUn(_addr)

	if addr.sun_family != sock_pub.af_unix {
		errno.set(errno.einval)
		return error('')
	}

	mut thread := proc.current_thread()

	path := unsafe { cstring_to_vstring(&addr.sun_path[0]) }

	C.printf(c'UNIX socket: Wants to connect to %s\n', path.str)

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

	// ----

	if socket.listening == false {
		errno.set(errno.econnrefused)
		return error('')
	}

	socket.l.acquire()

	socket.backlog << this

	socket.status = 0
	socket.status |= file.pollin
	event.trigger(mut socket.event, true)

	socket.l.release()

	mut events := [&this.connection_event]
	event.await(mut events, true) or {
		errno.set(errno.eintr)
		return error('')
	}

	event.trigger(mut socket.connection_event, false)

	C.printf(c'UNIX socket: Connected!\n')

	this.status = 0
	this.status |= file.pollout
	event.trigger(mut this.event, true)
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

fn (mut this UnixSocket) recvmsg(handle voidptr, msg &sock_pub.MsgHdr, flags int) ?u64 {
	if this.connected == false {
		errno.set(errno.enotconn)
		return error('')
	}

	this.peer.status |= file.pollout
	event.trigger(mut this.peer.event, true)

	for {}


	return 0
}

pub fn create(@type int) ?&UnixSocket {
	return &UnixSocket{
		refcount: 1
		peer: voidptr(0)
		data: unsafe { C.malloc(sock_buf) }
		capacity: sock_buf
	}
}

pub fn create_pair(@type int) ?(&UnixSocket, &UnixSocket) {
	mut a := &UnixSocket{
		refcount: 1
		peer: voidptr(0)
		data: unsafe { C.malloc(sock_buf) }
		capacity: sock_buf
	}
	mut b := &UnixSocket{
		refcount: 1
		peer: voidptr(0)
		data: unsafe { C.malloc(sock_buf) }
		capacity: sock_buf
	}
	return a, b
}
