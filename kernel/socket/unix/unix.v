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

const msg_cmsg_cloexec = 0x40000000
const msg_ctrunc = 0x08
const msg_peek = 0x02
const msg_trunc = 0x20
const msg_dontwait = 0x40
const msg_waitall = 0x100
const cmsg_header_size = u64(16)
const cmsg_align = u64(8)

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

struct PendingFdGroup {
mut:
	// Number of unread stream bytes before the first byte carrying these
	// descriptor rights, and the number of bytes from that sendmsg(). UNIX
	// stream ancillary data forms a boundary after the descriptor-bearing
	// message: recvmsg returns any preceding bytes plus this span and its rights.
	offset u64
	span   u64
	fds    []&file.FD
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
	// Credentials are captured when the connection is established, matching
	// Linux SO_PEERCRED rather than whatever identity the peer has later.
	owner_pid int
	owner_uid u32
	owner_gid u32
	peer_pid  int
	peer_uid  u32
	peer_gid  u32

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
	// SO_PASSCRED: every recvmsg on this socket is given the peer's identity as
	// an SCM_CREDENTIALS record. Crashpad, D-Bus and systemd-style services use
	// it to find out who is on the other end of a connection they accepted.
	passcred int
	// Keep closed endpoint objects as small tombstones because their peers refer
	// to them without taking a resource reference; the large receive buffer and
	// queued state are still reclaimed immediately.
	closed bool

	data      &u8 = unsafe { nil }
	read_ptr  u64
	write_ptr u64
	capacity  u64
	used      u64

	// Open-file descriptions waiting to be delivered by recvmsg(SCM_RIGHTS),
	// kept in sendmsg-sized groups. The boundary matters: Wine sends its request
	// and reply pipe ends in consecutive messages and expects one descriptor
	// from each corresponding recvmsg call.
	pending_fd_groups []PendingFdGroup

	// SOCK_SEQPACKET preserves message boundaries: each send is one record and
	// each receive returns exactly one, its remainder discarded if it did not
	// fit. This is the byte length of every buffered record, oldest first. It
	// stays empty for SOCK_STREAM, which has no boundaries. runc's sync protocol
	// relies on it: it reads a record's length with
	// recvfrom(0, MSG_PEEK|MSG_TRUNC) and then reads the record itself.
	packet_lengths []u64
}

// Whether this endpoint keeps message boundaries (SOCK_SEQPACKET).
pub fn (this &UnixSocket) is_seqpacket() bool {
	return this.socktype & sock_pub.sock_type_mask == sock_pub.sock_seqpacket
}

// The byte length of the next record to be received, or all buffered bytes for
// a stream socket that keeps no boundaries.
fn (this &UnixSocket) next_message_length() u64 {
	if this.is_seqpacket() && this.packet_lengths.len > 0 {
		return this.packet_lengths[0]
	}
	return this.used
}

fn (mut this UnixSocket) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

fn (mut this UnixSocket) read(_handle voidptr, buf voidptr, _loc u64, _count u64) ?i64 {
	// A SOCK_SEQPACKET read still returns exactly one record; the framed path
	// owns the boundary bookkeeping.
	if this.is_seqpacket() {
		return this.recv_seqpacket(_handle, buf, _count, 0)
	}

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

	// Do not cross the end of an ancillary-bearing sendmsg. A plain read that
	// reaches the first byte carrying rights consumes and discards the group,
	// just like recvmsg with no control buffer.
	mut discard_fd_group := false
	if count != 0 && this.pending_fd_groups.len != 0 {
		group := this.pending_fd_groups[0]
		boundary := group.offset + group.span
		if count > boundary {
			count = boundary
		}
		discard_fd_group = count > group.offset
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

	if discard_fd_group {
		mut pending_fds := unsafe { this.pending_fd_groups[0].fds }
		for mut dropped in pending_fds {
			dropped.unref()
			unsafe { free(voidptr(dropped)) }
		}
		unsafe { pending_fds.free() }
		this.pending_fd_groups.delete(0)
	}
	for i in 0 .. this.pending_fd_groups.len {
		this.pending_fd_groups[i].offset -= count
	}

	this.peer.status |= file.pollout
	event.trigger(mut this.peer.event, false)

	if this.used == 0 {
		this.status &= ~file.pollin
	}

	return i64(count)
}

// Receive one SOCK_SEQPACKET record, honouring the recvfrom(2) flags a length
// prefix protocol needs: MSG_PEEK leaves the record queued, MSG_TRUNC reports
// its true length even when the buffer is shorter, and the two together with a
// zero-length buffer answer "how long is the next record" without consuming it.
// runc's sync channel drives exactly this. Any descriptors a peeked-past record
// carried are dropped, as a plain recvfrom does.
pub fn (mut this UnixSocket) recv_seqpacket(_handle voidptr, buf voidptr, count u64, flags int) ?i64 {
	peek := flags & msg_peek != 0
	trunc := flags & msg_trunc != 0

	this.l.acquire()
	defer {
		this.l.release()
	}

	handle := unsafe { &file.Handle(_handle) }

	if this.read_closed {
		return 0
	}

	for katomic.load(&this.used) == 0 {
		if this.peer_finished {
			return 0
		}
		if handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.ewouldblock)
			return none
		}
		// Sample the event's generation while the socket lock still protects the
		// empty state. A writer that fills the socket after this check and
		// before the wait attaches raises the generation, so the generation-aware
		// wait returns at once instead of sleeping on a notification another
		// reader has already consumed. runc's synchronous sync channel deadlocked
		// on exactly that lost wakeup.
		generation := event.generation(mut this.event)
		this.l.release()
		mut events := [&this.event]
		event.await_from_generation(mut events, true, 0, generation) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
		this.l.acquire()
	}

	message_length := this.next_message_length()
	mut to_copy := if count < message_length { count } else { message_length }

	if to_copy != 0 {
		mut before_wrap := to_copy
		mut after_wrap := u64(0)
		if this.read_ptr + to_copy > this.capacity {
			before_wrap = this.capacity - this.read_ptr
			after_wrap = to_copy - before_wrap
		}
		unsafe { C.memcpy(buf, &this.data[this.read_ptr], before_wrap) }
		if after_wrap != 0 {
			unsafe { C.memcpy(voidptr(u64(buf) + before_wrap), this.data, after_wrap) }
		}
	}

	// MSG_TRUNC reports the record's real length; the default reports how much
	// was handed back.
	ret := if trunc { message_length } else { to_copy }

	if !peek {
		// The whole record leaves the queue even when it did not all fit.
		this.read_ptr = (this.read_ptr + message_length) % this.capacity
		this.used -= message_length
		if this.packet_lengths.len > 0 {
			this.packet_lengths.delete(0)
		}
		// A plain recvfrom past a descriptor-bearing record drops its rights.
		if this.pending_fd_groups.len != 0 && this.pending_fd_groups[0].offset < message_length {
			mut pending_fds := unsafe { this.pending_fd_groups[0].fds }
			for mut dropped in pending_fds {
				dropped.unref()
				unsafe { free(voidptr(dropped)) }
			}
			unsafe { pending_fds.free() }
			this.pending_fd_groups.delete(0)
		}
		for i in 0 .. this.pending_fd_groups.len {
			this.pending_fd_groups[i].offset -= message_length
		}
		this.peer.status |= file.pollout
		event.trigger(mut this.peer.event, false)
		if this.used == 0 {
			this.status &= ~file.pollin
		}
	}

	return i64(ret)
}

fn (mut this UnixSocket) write(_handle voidptr, buf voidptr, _loc u64, _count u64) ?i64 {
	return this.write_with_fds(_handle, buf, _count, []&file.FD{})
}

// Write stream data and attach descriptor rights to the same wakeup. Queuing
// the rights while the peer lock is held prevents recvmsg() from consuming the
// bytes before their ancillary data has become visible.
pub fn (mut this UnixSocket) write_with_fds(_handle voidptr, buf voidptr, _count u64, fds []&file.FD) ?i64 {
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
	// A SOCK_SEQPACKET record is all-or-nothing, so one larger than the whole
	// receive buffer can never be delivered whole and must be refused rather
	// than truncated into a bogus boundary.
	if peer.is_seqpacket() && _count > peer.capacity {
		errno.set(errno.emsgsize)
		return none
	}
	peer.l.acquire()
	defer {
		peer.l.release()
	}
	// close_endpoint() serialises freeing the receive buffer with writers on
	// this lock. Recheck after acquiring it rather than racing a peer close.
	if peer.read_closed || peer.closed {
		errno.set(errno.epipe)
		return none
	}

	handle := unsafe { &file.Handle(_handle) }

	// A blocking stream write that fits in the socket buffer must not return a
	// short count merely because the peer has not drained enough space yet.
	// Wine relies on this for its writev()-based request protocol and treats a
	// short request as fatal.  Large writes can still make partial progress once
	// any room is available, matching the existing stream behaviour.
	requested_room := if count <= peer.capacity { count } else { u64(1) }
	for peer.capacity - katomic.load(&peer.used) < requested_room {
		if handle.flags & resource.o_nonblock != 0 {
			if peer.used == peer.capacity {
				errno.set(errno.ewouldblock)
				return none
			}
			break
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
		if peer.read_closed {
			errno.set(errno.epipe)
			return none
		}
	}

	if peer.used + count > peer.capacity {
		count = peer.capacity - peer.used
	}
	if count == 0 && fds.len != 0 {
		errno.set(errno.eagain)
		return none
	}

	// Descriptor rights are attached to the first byte written by this
	// sendmsg(), after any data already queued on the peer.
	fd_offset := peer.used

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
	if fds.len != 0 {
		mut group := PendingFdGroup{
			offset: fd_offset
			span:   count
			fds:    []&file.FD{}
		}
		group.fds << fds
		peer.pending_fd_groups << group
	}
	// On a SOCK_SEQPACKET peer this send is one record. The write above did not
	// split it -- a message larger than the buffer is refused, and the wait
	// loop held out for room for the whole of it -- so its length is `count`.
	if peer.is_seqpacket() {
		peer.packet_lengths << count
	}

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

// Give up the abstract name this socket was bound to, if it had one. The table
// is the whole of the abstract namespace: an entry left behind by a socket that
// has gone keeps its name reserved for the life of the machine, so the next
// server to ask for it is refused, and a connect to it is handed a socket that
// no longer exists. An X server binds both the filesystem path and the abstract
// name, which is why restarting one used to fail with "Cannot establish any
// listening sockets - Make sure an X server isn't already running" even after
// its socket file was gone.
fn release_abstract_name(socket &UnixSocket) {
	abstract_sockets_lock.acquire()
	defer {
		abstract_sockets_lock.release()
	}
	for i in 0 .. 64 {
		if abstract_sockets[i].in_use
			&& voidptr(abstract_sockets[i].socket) == voidptr(socket) {
			abstract_sockets[i].in_use = false
			abstract_sockets[i].name_len = 0
			abstract_sockets[i].socket = unsafe { nil }
		}
	}
}

// Drop all allocation and peer state owned by an endpoint whose last open file
// description has gone away. Unix sockets used to keep their initial resource
// reference and 1 MiB receive buffer forever. A desktop build starts enough
// short-lived helpers for those leaked buffers to exhaust an 8 GiB VM before
// the replacement compositor can finish starting.
fn (mut this UnixSocket) close_endpoint() {
	this.l.acquire()
	if this.closed {
		this.l.release()
		return
	}
	this.closed = true
	this.listening = false
	this.read_closed = true
	this.write_closed = true
	this.peer_finished = true
	this.status &= ~file.pollout
	this.status |= file.pollin | file.pollhup | file.pollerr

	mut peer := this.peer
	this.peer = unsafe { nil }
	mut queued := unsafe { this.backlog }
	this.backlog = []&UnixSocket{}
	mut pending := unsafe { this.pending_fd_groups }
	this.pending_fd_groups = []PendingFdGroup{}
	unsafe { this.packet_lengths.free() }
	this.packet_lengths = []u64{}
	data := this.data
	this.data = unsafe { nil }
	this.capacity = 0
	this.used = 0
	this.read_ptr = 0
	this.write_ptr = 0
	this.l.release()

	if data != unsafe { nil } {
		unsafe { free(data) }
	}
	for group in pending {
		mut descriptors := unsafe { group.fds }
		for mut descriptor in descriptors {
			descriptor.unref()
			unsafe { free(voidptr(descriptor)) }
		}
		unsafe { descriptors.free() }
	}
	unsafe { pending.free() }

	if peer != unsafe { nil } {
		peer.l.acquire()
		peer.peer_finished = true
		peer.status &= ~file.pollout
		peer.status |= file.pollin | file.pollhup | file.pollerr
		peer.l.release()
		event.trigger(mut peer.event, false)
	}

	// A listener owns accepted endpoints until accept(2) publishes a file
	// descriptor for them. Closing the listener must release those buffers too.
	for mut connection in queued {
		connection.close_endpoint()
	}
	unsafe { queued.free() }
	event.trigger(mut this.event, false)
}

fn (mut this UnixSocket) unref(handle voidptr) ? {
	still_referenced := katomic.dec(mut &this.refcount)
	// A nil handle is the VFS dropping a pathname, not an open socket being
	// closed. If a descriptor is still alive it must retain the endpoint.
	if handle == unsafe { nil } && still_referenced {
		return
	}

	// Constructors retain one resource reference for unnamed sockets, while a
	// path-bound socket uses it as its namespace reference. Either way, an
	// open-handle release at count one is the final descriptor close.
	release_abstract_name(this)
	this.close_endpoint()
}

fn (mut this UnixSocket) link(_handle voidptr) ? {
	return none
}

fn (mut this UnixSocket) unlink(_handle voidptr) ? {
	// The VFS owns the socket path. Once it has passed its namespace checks,
	// there is no backing store operation left for a UNIX socket to perform.
	return
}

fn (mut this UnixSocket) grow(_handle voidptr, _new_size u64) ? {
	return none
}

fn (mut this UnixSocket) peername(_handle voidptr, _addr voidptr, addrlen &u32) ? {
	if this.connected == false {
		errno.set(errno.enotconn)
		return none
	}

	// This used to round the copy *up* to the full struct when the caller
	// offered a smaller buffer, writing past the end of it.
	sock_pub.copy_out_sockaddr(_addr, addrlen, voidptr(&this.peer.name), sizeof(SockaddrUn))
}

fn (mut this UnixSocket) sockname(_handle voidptr, _addr voidptr, addrlen &u32) ? {
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
fn (mut this UnixSocket) shutdown(_handle voidptr, how int) ? {
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

fn (mut this UnixSocket) getsockopt(_handle voidptr, level int, optname int) ?int {
	if level != sock_pub.sol_socket {
		errno.set(errno.enoprotoopt)
		return none
	}

	match optname {
		sock_pub.so_type {
			return this.socktype
		}
		sock_pub.so_error {
			return 0
		}
		sock_pub.so_acceptconn {
			return if this.listening { 1 } else { 0 }
		}
		sock_pub.so_domain {
			return sock_pub.af_unix
		}
		sock_pub.so_protocol {
			return 0
		}
		sock_pub.so_sndbuf, sock_pub.so_rcvbuf {
			return int(this.capacity)
		}
		sock_pub.so_reuseaddr {
			return this.reuseaddr
		}
		sock_pub.so_keepalive {
			return this.keepalive
		}
		sock_pub.so_broadcast {
			return this.broadcast
		}
		sock_pub.so_passcred {
			return this.passcred
		}
		else {
			errno.set(errno.enoprotoopt)
			return none
		}
	}
}

pub fn (this &UnixSocket) peer_credentials() ?sock_pub.UCred {
	if !this.connected || this.peer == unsafe { nil } {
		errno.set(errno.enotconn)
		return none
	}
	return sock_pub.UCred{
		pid: this.peer_pid
		uid: this.peer_uid
		gid: this.peer_gid
	}
}

fn (mut this UnixSocket) setsockopt(_handle voidptr, level int, optname int, value int) ? {
	if level != sock_pub.sol_socket {
		errno.set(errno.enoprotoopt)
		return none
	}

	// The options below change nothing about how a unix socket behaves here,
	// but a program that sets one and reads it back should see what it wrote.
	match optname {
		sock_pub.so_reuseaddr, sock_pub.so_reuseport {
			this.reuseaddr = value
		}
		sock_pub.so_keepalive {
			this.keepalive = value
		}
		sock_pub.so_broadcast {
			this.broadcast = value
		}
		sock_pub.so_passcred {
			this.passcred = value
		}
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

	// connect() builds both ends before it returns, then queues the server end
	// here. Waiting until accept() to join the pair made a normal single-threaded
	// connect-then-accept sequence deadlock.
	mut connection_socket := this.backlog[0]
	this.backlog.delete(0)

	if this.backlog.len == 0 {
		this.status &= ~file.pollin
	}

	// A blocked connect may now have room in the listening queue.
	event.trigger(mut this.event, false)

	print('unix accept: done\n')
	return connection_socket
}

fn (mut this UnixSocket) connect(_handle voidptr, _addr voidptr, addrlen u32) ? {
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

		mut target := fs.get_node(proc.current_directory_of(t.process), path, true) or {
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

	socket.l.acquire()
	defer {
		socket.l.release()
	}
	// A pathname keeps the small socket object alive after its descriptor is
	// closed. Recheck under the listener lock so connect cannot queue a new
	// endpoint while close_endpoint() is tearing that listener down.
	if !socket.listening || socket.closed {
		errno.set(errno.econnrefused)
		return none
	}

	// A connected UNIX stream is established when connect() places it in the
	// listener's queue, not when accept() eventually removes it. This permits a
	// client to connect and send before the server calls accept(), as Linux does.
	mut connection_socket := &UnixSocket{
		refcount:  1
		peer:      this
		connected: true
		name:      socket.name
		data:      unsafe { malloc(sock_buf) }
		capacity:  sock_buf
		status:    file.pollout
		socktype:  this.socktype
		owner_pid: socket.owner_pid
		owner_uid: socket.owner_uid
		owner_gid: socket.owner_gid
	}
	client := proc.current_thread().process
	connection_socket.peer_pid = client.pid
	connection_socket.peer_uid = client.euid
	connection_socket.peer_gid = client.egid

	this.peer = connection_socket
	this.connected = true
	this.peer_pid = socket.owner_pid
	this.peer_uid = socket.owner_uid
	this.peer_gid = socket.owner_gid
	this.status |= file.pollout
	socket.backlog << connection_socket

	socket.status |= file.pollin
	event.trigger(mut socket.event, false)
	event.trigger(mut this.event, false)
}

fn (mut this UnixSocket) bind(_handle voidptr, _addr voidptr, addrlen u32) ? {
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

	mut node := fs.create(proc.current_directory_of(t.process), path, stat.ifsock | 0o777) or {
		return none
	}

	mut replaced := node.resource
	this.stat = node.resource.stat
	node.resource = unsafe { this }
	replaced.unref(unsafe { nil }) or {}

	this.name = *addr
}

fn (mut this UnixSocket) listen(_handle voidptr, backlog int) ? {
	this.backlog = []&UnixSocket{cap: backlog}
	this.listening = true
}

fn (mut this UnixSocket) recvmsg(_handle voidptr, msg &sock_pub.MsgHdr, flags int) ?u64 {
	if flags & ~msg_cmsg_cloexec != 0 {
		errno.set(errno.eopnotsupp)
		return none
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

	// A SOCK_SEQPACKET recvmsg returns at most one record; never read across
	// its boundary.
	mut seq_msg_len := u64(0)
	if this.is_seqpacket() {
		seq_msg_len = this.next_message_length()
		if count > seq_msg_len {
			count = seq_msg_len
		}
	}

	// SCM_RIGHTS is associated with one sendmsg in the byte stream. Linux
	// returns any data before it plus that sendmsg's bytes and descriptors, then
	// stops before subsequently queued data.
	mut deliver_fd_group := false
	if count != 0 && this.pending_fd_groups.len != 0 {
		group := this.pending_fd_groups[0]
		boundary := group.offset + group.span
		if count > boundary {
			count = boundary
		}
		deliver_fd_group = count > group.offset
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

	// Linux cmsghdr is 16 bytes on aarch64: size_t, level, type. Records are
	// written in the order the kernel produces them: the peer's credentials
	// first when SO_PASSCRED asked for them, then any queued SCM_RIGHTS
	// descriptors that still fit in the caller's control buffer.
	control_capacity := msg.msg_controllen
	unsafe {
		msg.msg_controllen = 0
		msg.msg_flags = 0
	}
	mut control_used := u64(0)
	if this.passcred != 0 && msg.msg_control != unsafe { nil } {
		cmsg_len := cmsg_header_size + sizeof(sock_pub.UCred)
		cmsg_space := (cmsg_len + cmsg_align - 1) & ~(cmsg_align - 1)
		if cmsg_space <= control_capacity {
			// A connected stream never changes identity, so the credentials
			// captured when the connection was established are the sending
			// process's own.
			credentials := sock_pub.UCred{
				pid: i32(this.peer_pid)
				uid: this.peer_uid
				gid: this.peer_gid
			}
			control := unsafe { &u8(msg.msg_control) }
			unsafe {
				*(&u64(control)) = cmsg_len
				*(&i32(voidptr(u64(control) + 8))) = i32(sock_pub.sol_socket)
				*(&i32(voidptr(u64(control) + 12))) = i32(sock_pub.scm_credentials)
				C.memcpy(voidptr(u64(control) + cmsg_header_size), &credentials,
					sizeof(sock_pub.UCred))
			}
			control_used = cmsg_space
			unsafe {
				msg.msg_controllen = control_used
			}
		} else {
			unsafe { msg.msg_flags |= msg_ctrunc }
		}
	}
	if deliver_fd_group {
		mut pending_fds := unsafe { this.pending_fd_groups[0].fds }
		remaining_control := control_capacity - control_used
		mut capacity_fds := u64(0)
		if msg.msg_control != unsafe { nil } && remaining_control >= cmsg_header_size + sizeof(i32) {
			capacity_fds = (remaining_control - cmsg_header_size) / sizeof(i32)
			// msg_controllen includes the cmsghdr's trailing alignment. A
			// CMSG_LEN-sized buffer can hold the bytes but cannot represent a
			// complete ancillary record, so report truncation instead.
			for capacity_fds > 0 {
				cmsg_len := cmsg_header_size + capacity_fds * sizeof(i32)
				cmsg_space := (cmsg_len + cmsg_align - 1) & ~(cmsg_align - 1)
				if cmsg_space <= remaining_control {
					break
				}
				capacity_fds--
			}
		}
		mut deliver := u64(pending_fds.len)
		if deliver > capacity_fds {
			deliver = capacity_fds
			unsafe { msg.msg_flags |= msg_ctrunc }
		}

		if deliver != 0 {
			control := unsafe { &u8(voidptr(u64(msg.msg_control) + control_used)) }
			unsafe {
				*(&u64(control)) = cmsg_header_size + deliver * sizeof(i32)
				*(&i32(voidptr(u64(control) + 8))) = i32(sock_pub.sol_socket)
				*(&i32(voidptr(u64(control) + 12))) = i32(sock_pub.scm_rights)
			}

			mut installed := u64(0)
			for installed < deliver {
				mut passed_fd := pending_fds[int(installed)]
				if flags & msg_cmsg_cloexec != 0 {
					passed_fd.flags |= resource.o_cloexec
				}
				new_fdnum := file.fdnum_create_from_fd(unsafe { nil }, passed_fd, 0, false) or {
					unsafe { msg.msg_flags |= msg_ctrunc }
					break
				}
				unsafe {
					*(&i32(voidptr(u64(control) + cmsg_header_size + installed * sizeof(i32)))) = i32(new_fdnum)
				}
				installed++
			}

			if installed != 0 {
				cmsg_len := cmsg_header_size + installed * sizeof(i32)
				unsafe {
					*(&u64(control)) = cmsg_len
					msg.msg_controllen = control_used +
						((cmsg_len + cmsg_align - 1) & ~(cmsg_align - 1))
				}
			}
			deliver = installed
		}

		// Ancillary data accompanies the bytes just consumed. Descriptors that
		// did not fit are discarded with MSG_CTRUNC, matching recvmsg semantics.
		for i in int(deliver) .. pending_fds.len {
			mut dropped := pending_fds[i]
			dropped.unref()
			unsafe { free(voidptr(dropped)) }
		}
		unsafe { pending_fds.free() }
		this.pending_fd_groups.delete(0)
	}
	for i in 0 .. this.pending_fd_groups.len {
		this.pending_fd_groups[i].offset -= transferred
	}

	// One SOCK_SEQPACKET recvmsg consumes exactly one record: drop whatever of
	// it did not fit, and its descriptors, then retire its boundary.
	if this.is_seqpacket() && seq_msg_len > 0 {
		remainder := seq_msg_len - transferred
		if remainder > 0 {
			for this.pending_fd_groups.len > 0 && this.pending_fd_groups[0].offset < remainder {
				mut pending_fds := unsafe { this.pending_fd_groups[0].fds }
				for mut dropped in pending_fds {
					dropped.unref()
					unsafe { free(voidptr(dropped)) }
				}
				unsafe { pending_fds.free() }
				this.pending_fd_groups.delete(0)
			}
			this.read_ptr = (this.read_ptr + remainder) % this.capacity
			this.used -= remainder
			for i in 0 .. this.pending_fd_groups.len {
				this.pending_fd_groups[i].offset -= remainder
			}
			unsafe { msg.msg_flags |= msg_trunc }
		}
		if this.packet_lengths.len > 0 {
			this.packet_lengths.delete(0)
		}
	}

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

	if this.used == 0 {
		this.status &= ~file.pollin
	}

	return transferred
}

pub fn create(@type int) ?&UnixSocket {
	process := proc.current_thread().process
	mut ret := &UnixSocket{
		refcount:  1
		peer:      unsafe { nil }
		data:      unsafe { malloc(sock_buf) }
		capacity:  sock_buf
		owner_pid: process.pid
		owner_uid: process.euid
		owner_gid: process.egid
	}
	ret.name.sun_family = sock_pub.af_unix
	ret.socktype = @type & sock_pub.sock_type_mask
	ret.status |= file.pollout
	return ret
}

pub fn create_pair(@type int) ?(&UnixSocket, &UnixSocket) {
	process := proc.current_thread().process
	mut a := &UnixSocket{
		refcount:  1
		peer:      unsafe { nil }
		data:      unsafe { malloc(sock_buf) }
		capacity:  sock_buf
		owner_pid: process.pid
		owner_uid: process.euid
		owner_gid: process.egid
	}
	a.name.sun_family = sock_pub.af_unix
	a.socktype = @type & sock_pub.sock_type_mask
	a.status |= file.pollout
	mut b := &UnixSocket{
		refcount:  1
		peer:      unsafe { nil }
		data:      unsafe { malloc(sock_buf) }
		capacity:  sock_buf
		owner_pid: process.pid
		owner_uid: process.euid
		owner_gid: process.egid
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
	a.peer_pid = b.owner_pid
	a.peer_uid = b.owner_uid
	a.peer_gid = b.owner_gid
	b.peer_pid = a.owner_pid
	b.peer_uid = a.owner_uid
	b.peer_gid = a.owner_gid

	return a, b
}
