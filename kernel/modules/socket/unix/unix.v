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
import ioctl

pub const sock_buf = 0x100000

pub struct SockaddrUn {
pub mut:
	sun_family u16
	sun_path   [108]u8
}

pub struct UnixSocket {
pub mut:
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
	connected        bool
	peer             &UnixSocket = unsafe { nil }

	data      &u8 = unsafe { nil }
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

	handle := unsafe { &file.Handle(_handle) }

	// If pipe is empty, block or return if nonblock
	for katomic.load(&this.used) == 0 {
		// Return EOF if the pipe was closed
		//		if this.refcount <= 1 {
		//			return 0
		//		}
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
		unsafe { C.memcpy(voidptr(u64(buf) + before_wrap), this.data, after_wrap) }
	}

	this.read_ptr = new_ptr_loc
	this.used -= count

	this.peer.status |= file.pollout
	event.trigger(mut this.peer.event, false)

	this.status &= ~file.pollin

	return i64(count)
}

fn (mut this UnixSocket) write(_handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	mut peer := this.peer

	peer.l.acquire()
	defer {
		peer.l.release()
	}

	handle := unsafe { &file.Handle(_handle) }

	// If pipe is full, block or return if nonblock
	for katomic.load(&peer.used) == peer.capacity {
		if handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.ewouldblock)
			return none
		}

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
		unsafe { C.memcpy(peer.data, voidptr(u64(buf) + before_wrap), after_wrap) }
	}

	peer.write_ptr = new_ptr_loc
	peer.used += count

	peer.status |= file.pollin
	event.trigger(mut peer.event, false)

	return i64(count)
}

fn (mut this UnixSocket) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	match request {
		ioctl.fionread {
			if this.listening {
				errno.set(errno.einval)
				return none
			}
			mut retp := &u64(argp)
			unsafe {
				*retp = this.used
			}
			return 0
		}
		else {
			return resource.default_ioctl(handle, request, argp)
		}
	}
}

fn (mut this UnixSocket) unref(handle voidptr) ? {
	return none
}

fn (mut this UnixSocket) link(handle voidptr) ? {
	return none
}

fn (mut this UnixSocket) unlink(handle voidptr) ? {
	return none
}

fn (mut this UnixSocket) grow(handle voidptr, new_size u64) ? {
	return none
}

fn (mut this UnixSocket) peername(handle voidptr, _addr voidptr, addrlen &u32) ? {
	if this.connected == false {
		errno.set(errno.enotconn)
		return none
	}

	mut actual_size := unsafe { *addrlen }
	if actual_size < sizeof(SockaddrUn) {
		actual_size = sizeof(SockaddrUn)
	}

	unsafe { C.memcpy(_addr, voidptr(&this.peer.name), actual_size) }
	unsafe {
		*addrlen = actual_size
	}
}

fn (mut this UnixSocket) accept(_handle voidptr) ?&resource.Resource {
	if this.listening == false {
		errno.set(errno.einval)
		return none
	}

	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := unsafe { &file.Handle(_handle) }

	for this.backlog.len == 0 {
		this.status &= ~file.pollin
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

	mut connection_socket := &UnixSocket{
		refcount: 1
		peer: peer
		connected: true
		name: peer.name
		data: unsafe { C.malloc(unix.sock_buf) }
		capacity: unix.sock_buf
	}

	peer.refcount++
	peer.peer = connection_socket
	peer.connected = true

	if this.backlog.len == 0 {
		this.status &= ~file.pollin
	}

	event.trigger(mut peer.connection_event, false)

	mut events := [&this.connection_event]
	event.await(mut events, true) or {
		errno.set(errno.eintr)
		return none
	}

	return connection_socket
}

fn (mut this UnixSocket) connect(handle voidptr, _addr voidptr, addrlen u32) ? {
	addr := unsafe { &SockaddrUn(_addr) }

	if addr.sun_family != sock_pub.af_unix {
		errno.set(errno.einval)
		return none
	}

	mut t := proc.current_thread()

	path := unsafe { cstring_to_vstring(&addr.sun_path[0]) }

	C.printf(c'UNIX socket: Wants to connect to %s\n', path.str)

	mut target := fs.get_node(t.process.current_directory, path, true) or { return none }

	target_res := target.resource

	mut socket := &UnixSocket(unsafe { nil })

	if target_res is UnixSocket {
		socket = target_res
	} else {
		errno.set(errno.einval)
		return none
	}

	// ----

	if socket.listening == false {
		errno.set(errno.econnrefused)
		return none
	}

	socket.l.acquire()

	socket.backlog << this

	socket.status |= file.pollin
	event.trigger(mut socket.event, false)

	socket.l.release()

	mut events := [&this.connection_event]
	event.await(mut events, true) or {
		errno.set(errno.eintr)
		return none
	}

	event.trigger(mut socket.connection_event, false)

	C.printf(c'UNIX socket: Connected!\n')

	this.status |= file.pollout
	event.trigger(mut this.event, false)
}

fn (mut this UnixSocket) bind(handle voidptr, _addr voidptr, addrlen u32) ? {
	addr := unsafe { &SockaddrUn(_addr) }

	if addr.sun_family != sock_pub.af_unix {
		errno.set(errno.einval)
		return none
	}

	mut t := proc.current_thread()

	path := unsafe { cstring_to_vstring(&addr.sun_path[0]) }

	mut node := fs.create(t.process.current_directory, path, stat.ifsock) or { return none }

	this.stat = node.resource.stat
	node.resource = unsafe { this }

	this.name = *addr
}

fn (mut this UnixSocket) listen(handle voidptr, backlog int) ? {
	this.backlog = []&UnixSocket{cap: backlog}
	this.listening = true
}

fn (mut this UnixSocket) recvmsg(_handle voidptr, msg &sock_pub.MsgHdr, flags int) ?u64 {
	if flags != 0 {
		panic('UNIX socket recv does not support flags')
	}

	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := unsafe { &file.Handle(_handle) }

	mut count := u64(0)
	for i := u64(0); i < msg.msg_iovlen; i++ {
		count += unsafe { msg.msg_iov[i].iov_len }
	}

	C.printf(c'%d iovecs, %llu bytes\n', msg.msg_iovlen, count)

	// If pipe is empty, block or return if nonblock
	for katomic.load(&this.used) == 0 {
		// Return EOF if the pipe was closed
		//		if this.refcount <= 1 {
		//			return 0
		//		}
		this.peer.status |= file.pollout
		event.trigger(mut this.peer.event, false)
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

	mut tmpbuf := unsafe { &u8(C.malloc(before_wrap + after_wrap)) }
	unsafe { C.memcpy(tmpbuf, &this.data[this.read_ptr], before_wrap) }
	if after_wrap != 0 {
		unsafe { C.memcpy(voidptr(u64(tmpbuf) + before_wrap), this.data, after_wrap) }
	}

	mut transferred := u64(0)
	mut left := before_wrap + after_wrap
	for i := u64(0); i < msg.msg_iovlen; i++ {
		iov := unsafe { &msg.msg_iov[i] }

		to_transfer := if iov.iov_len < left { iov.iov_len } else { left }

		unsafe {
			C.memcpy(iov.iov_base, voidptr(u64(tmpbuf) + transferred), to_transfer)
		}

		transferred += to_transfer
		left -= to_transfer
	}

	unsafe { C.free(tmpbuf) }

	this.read_ptr = new_ptr_loc
	this.used -= transferred

	this.peer.status |= file.pollout
	event.trigger(mut this.peer.event, false)

	if msg.msg_name != unsafe { nil } && this.connected {
		mut actual_size := msg.msg_namelen
		if actual_size < sizeof(SockaddrUn) {
			actual_size = sizeof(SockaddrUn)
		}

		unsafe { C.memcpy(msg.msg_name, voidptr(&this.peer.name), actual_size) }
		unsafe {
			msg.msg_namelen = actual_size
		}
	}

	C.printf(c'Successfully received %llu bytes\n', transferred)

	this.status &= ~file.pollin

	return transferred
}

pub fn create(@type int) ?&UnixSocket {
	mut ret := &UnixSocket{
		refcount: 1
		peer: unsafe { nil }
		data: unsafe { C.malloc(unix.sock_buf) }
		capacity: unix.sock_buf
	}
	ret.name.sun_family = sock_pub.af_unix
	return ret
}

pub fn create_pair(@type int) ?(&UnixSocket, &UnixSocket) {
	mut a := &UnixSocket{
		refcount: 1
		peer: unsafe { nil }
		data: unsafe { C.malloc(unix.sock_buf) }
		capacity: unix.sock_buf
	}
	a.name.sun_family = sock_pub.af_unix
	mut b := &UnixSocket{
		refcount: 1
		peer: unsafe { nil }
		data: unsafe { C.malloc(unix.sock_buf) }
		capacity: unix.sock_buf
	}
	b.name.sun_family = sock_pub.af_unix
	return a, b
}
