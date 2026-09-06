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

// Abstract UNIX socket registry — sockets bound with sun_path[0]=='\0'
// are stored here instead of in the filesystem.
struct AbstractSocketEntry {
mut:
	in_use   bool
	name_len u32
	name     [108]u8
	socket   &UnixSocket = unsafe { nil }
}

__global (
	abstract_sockets      [64]AbstractSocketEntry
	abstract_sockets_lock klock.Lock
)

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

	// shutdown(2) state. `read_closed` and `write_closed` are this socket's own
	// halves; `peer_finished` records that the other end promised to send
	// nothing further, so a reader drains what is buffered and only then sees
	// end of file.
	read_closed   bool
	write_closed  bool
	peer_finished bool

	// Remembered so getsockopt(SO_TYPE) and friends have something true to say.
	socktype int
	// Options this kernel accepts but does not act on, kept so that a program
	// that sets one and reads it back is not told it failed.
	reuseaddr int
	keepalive int
	broadcast int

	data      &u8 = unsafe { nil }
	read_ptr  u64
	write_ptr u64
	capacity  u64
	used      u64
}

fn (mut this UnixSocket) mmap(_handle voidptr, page u64, flags int) voidptr {
	return 0
}

fn (mut this UnixSocket) read(_handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	mut count := _count

	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := unsafe { &file.Handle(_handle) }

	// shutdown(SHUT_RD) here: reads report end of file whatever is buffered.
	if this.read_closed {
		return 0
	}

	// If pipe is empty, block or return if nonblock
	for katomic.load(&this.used) == 0 {
		// The peer shut its write half: drain first, then end of file. Without
		// this a reader waits for data that can never arrive.
		if this.peer_finished {
			return 0
		}
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
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
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

	if this.write_closed {
		errno.set(errno.epipe)
		return none
	}

	mut peer := this.peer
	if peer == unsafe { nil } {
		errno.set(errno.enotconn)
		return none
	}
	if peer.read_closed {
		errno.set(errno.epipe)
		return none
	}

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
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
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
			mut retp := unsafe { &u64(argp) }
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

	// This used to round the copy *up* to the full struct when the caller
	// offered a smaller buffer, writing past the end of it.
	sock_pub.copy_out_sockaddr(_addr, addrlen, voidptr(&this.peer.name), sizeof(SockaddrUn))
}

fn (mut this UnixSocket) sockname(handle voidptr, _addr voidptr, addrlen &u32) ? {
	// An unbound socket has no path, and getsockname(2) reports just the family.
	mut full := u32(sizeof(SockaddrUn))
	if this.name.sun_path[0] == 0 {
		full = u32(sizeof(u16))
	}

	sock_pub.copy_out_sockaddr(_addr, addrlen, voidptr(&this.name), full)
}

// shutdown(2). Closing the write half is how a peer is told that nothing more
// is coming, which is the only way a reader blocked on this socket ever learns
// to stop waiting.
fn (mut this UnixSocket) shutdown(handle voidptr, how int) ? {
	if how != sock_pub.shut_rd && how != sock_pub.shut_wr && how != sock_pub.shut_rdwr {
		errno.set(errno.einval)
		return none
	}

	if how == sock_pub.shut_rd || how == sock_pub.shut_rdwr {
		this.read_closed = true
		this.status |= file.pollin
		event.trigger(mut &this.event, false)
	}

	if how == sock_pub.shut_wr || how == sock_pub.shut_rdwr {
		this.write_closed = true

		mut peer := this.peer
		if this.connected && peer != unsafe { nil } {
			peer.peer_finished = true
			peer.status |= file.pollin
			event.trigger(mut &peer.event, false)
		}
	}
}

fn (mut this UnixSocket) getsockopt(handle voidptr, level int, optname int) ?int {
	if level != sock_pub.sol_socket {
		errno.set(errno.enoprotoopt)
		return none
	}

	match optname {
		sock_pub.so_type { return this.socktype }
		sock_pub.so_error { return 0 }
		sock_pub.so_acceptconn { return if this.listening { 1 } else { 0 } }
		sock_pub.so_domain { return sock_pub.af_unix }
		sock_pub.so_protocol { return 0 }
		sock_pub.so_sndbuf, sock_pub.so_rcvbuf { return int(this.capacity) }
		sock_pub.so_reuseaddr { return this.reuseaddr }
		sock_pub.so_keepalive { return this.keepalive }
		sock_pub.so_broadcast { return this.broadcast }
		else {
			errno.set(errno.enoprotoopt)
			return none
		}
	}
}

fn (mut this UnixSocket) setsockopt(handle voidptr, level int, optname int, value int) ? {
	if level != sock_pub.sol_socket {
		errno.set(errno.enoprotoopt)
		return none
	}

	// The options below change nothing about how a unix socket behaves here,
	// but a program that sets one and reads it back should see what it wrote.
	match optname {
		sock_pub.so_reuseaddr, sock_pub.so_reuseport { this.reuseaddr = value }
		sock_pub.so_keepalive { this.keepalive = value }
		sock_pub.so_broadcast { this.broadcast = value }
		sock_pub.so_sndbuf, sock_pub.so_rcvbuf, sock_pub.so_linger, sock_pub.so_oobinline {}
		else {
			errno.set(errno.enoprotoopt)
			return none
		}
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
		print('unix accept: waiting for connection\n')
		this.l.release()
		mut events := [&this.event]
		event.await(mut events, true) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
		this.l.acquire()
	}

	print('unix accept: got connection, setting up peer\n')

	mut peer := this.backlog.pop()

	mut connection_socket := &UnixSocket{
		refcount:  1
		peer:      peer
		connected: true
		name:      peer.name
		data:      unsafe { malloc(sock_buf) }
		capacity:  sock_buf
	}

	peer.refcount++
	peer.peer = connection_socket
	peer.connected = true

	if this.backlog.len == 0 {
		this.status &= ~file.pollin
	}

	print('unix accept: triggering client connection_event\n')
	event.trigger(mut peer.connection_event, false)

	print('unix accept: done\n')
	return connection_socket
}

fn (mut this UnixSocket) connect(handle voidptr, _addr voidptr, addrlen u32) ? {
	addr := unsafe { &SockaddrUn(_addr) }

	if addr.sun_family != sock_pub.af_unix {
		errno.set(errno.einval)
		return none
	}

	mut socket := &UnixSocket(unsafe { nil })

	// Abstract socket: sun_path[0] == '\0'
	if addrlen > 2 && addr.sun_path[0] == 0 {
		name_len := addrlen - 2
		abstract_sockets_lock.acquire()
		for i in 0 .. 64 {
			if abstract_sockets[i].in_use && abstract_sockets[i].name_len == name_len {
				if unsafe { C.memcmp(&abstract_sockets[i].name[0], &addr.sun_path[0], name_len) } == 0 {
					socket = abstract_sockets[i].socket
					break
				}
			}
		}
		abstract_sockets_lock.release()
		if socket == unsafe { nil } {
			errno.set(errno.econnrefused)
			return none
		}
	} else {
		mut t := proc.current_thread()
		path := unsafe { cstring_to_vstring(&addr.sun_path[0]) }

		mut target := fs.get_node(t.process.current_directory, path, true) or {
			return none
		}

		mut target_res := target.resource

		if mut target_res is UnixSocket {
			socket = target_res
		} else {
			errno.set(errno.econnrefused)
			return none
		}
	}

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
		unsafe { events.free() }
		errno.set(errno.eintr)
		return none
	}
	unsafe { events.free() }

	this.status |= file.pollout
	event.trigger(mut this.event, false)
}

fn (mut this UnixSocket) bind(handle voidptr, _addr voidptr, addrlen u32) ? {
	addr := unsafe { &SockaddrUn(_addr) }

	if addr.sun_family != sock_pub.af_unix {
		errno.set(errno.einval)
		return none
	}

	// Abstract socket: sun_path[0] == '\0', name is in sun_path[1..addrlen-2]
	if addrlen > 2 && addr.sun_path[0] == 0 {
		name_len := addrlen - 2 // subtract sizeof(sun_family)
		abstract_sockets_lock.acquire()
		defer {
			abstract_sockets_lock.release()
		}
		// Check for duplicate
		for i in 0 .. 64 {
			if abstract_sockets[i].in_use && abstract_sockets[i].name_len == name_len {
				if unsafe { C.memcmp(&abstract_sockets[i].name[0], &addr.sun_path[0], name_len) } == 0 {
					errno.set(errno.eaddrinuse)
					return none
				}
			}
		}
		// Find free slot
		for i in 0 .. 64 {
			if !abstract_sockets[i].in_use {
				abstract_sockets[i].in_use = true
				abstract_sockets[i].name_len = name_len
				unsafe { C.memcpy(&abstract_sockets[i].name[0], &addr.sun_path[0], name_len) }
				abstract_sockets[i].socket = unsafe { this }
				this.name = *addr
				return
			}
		}
		// No free slots
		errno.set(errno.enomem)
		return none
	}

	mut t := proc.current_thread()

	path := unsafe { cstring_to_vstring(&addr.sun_path[0]) }

	mut node := fs.create(t.process.current_directory, path, stat.ifsock | 0o777) or {
		return none
	}

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
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
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

	mut tmpbuf := unsafe { &u8(malloc(before_wrap + after_wrap)) }
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

	unsafe { free(tmpbuf) }

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
		peer:     unsafe { nil }
		data:     unsafe { malloc(sock_buf) }
		capacity: sock_buf
	}
	ret.name.sun_family = sock_pub.af_unix
	ret.socktype = @type & sock_pub.sock_type_mask
	ret.status |= file.pollout
	return ret
}

pub fn create_pair(@type int) ?(&UnixSocket, &UnixSocket) {
	mut a := &UnixSocket{
		refcount: 1
		peer:     unsafe { nil }
		data:     unsafe { malloc(sock_buf) }
		capacity: sock_buf
	}
	a.name.sun_family = sock_pub.af_unix
	a.socktype = @type & sock_pub.sock_type_mask
	a.status |= file.pollout
	mut b := &UnixSocket{
		refcount: 1
		peer:     unsafe { nil }
		data:     unsafe { malloc(sock_buf) }
		capacity: sock_buf
	}
	b.name.sun_family = sock_pub.af_unix
	b.socktype = @type & sock_pub.sock_type_mask
	b.status |= file.pollout

	// The two ends were never joined up, so socketpair(2) handed back a pair
	// that was not connected to anything: a write dereferenced a nil peer and a
	// read waited for data that had nowhere to come from.
	a.peer = b
	b.peer = a
	a.connected = true
	b.connected = true

	return a, b
}
