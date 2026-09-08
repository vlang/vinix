@[has_globals]
module inet

import errno
import event
import event.eventstruct
import file
import fs
import ioctl
import katomic
import klock
import resource
import socket.public as sock_pub
import stat
import time

struct C.vinix_socket {}

fn C.vinix_net_init()
fn C.vinix_net_poll(now_ms u32)
fn C.vinix_net_attach(mac &u8, driver int) int
fn C.vinix_net_detach()
fn C.vinix_net_input(frame voidptr, length u64) int
fn C.vinix_net_config(address &u32, netmask &u32, gateway &u32, dns &u32) int
fn C.vinix_socket_new(@type int, protocol int) &C.vinix_socket
fn C.vinix_socket_free(socket &C.vinix_socket)
fn C.vinix_socket_bind(socket &C.vinix_socket, address u32, port u16) int
fn C.vinix_socket_connect(socket &C.vinix_socket, address u32, port u16) int
fn C.vinix_socket_listen(socket &C.vinix_socket, backlog int) int
fn C.vinix_socket_accept(socket &C.vinix_socket) &C.vinix_socket
fn C.vinix_socket_send(socket &C.vinix_socket, data voidptr, length u64, address u32, port u16, has_address int) int
fn C.vinix_socket_recv(socket &C.vinix_socket, data voidptr, length u64, address &u32, port &u16) int
fn C.vinix_socket_shutdown(socket &C.vinix_socket, how int) int
fn C.vinix_socket_local(socket &C.vinix_socket, address &u32, port &u16) int
fn C.vinix_socket_peer(socket &C.vinix_socket, address &u32, port &u16) int
fn C.vinix_socket_ready(socket &C.vinix_socket) int
fn C.vinix_socket_error(socket &C.vinix_socket, clear int) int
fn C.vinix_socket_available(socket &C.vinix_socket) int
fn C.vinix_socket_set_option(socket &C.vinix_socket, level int, option int, value int) int
fn C.vinix_socket_get_option(socket &C.vinix_socket, level int, option int, value &int) int

const max_sockets = 256
const ready_read = 1
const ready_write = 2
const ready_error = 4
const ready_hangup = 8
const ipproto_tcp = 6
const ipproto_ip = 0
const tcp_nodelay = 1
const ip_tos = 1
const ip_ttl = 2

// Driver identifiers shared with vinix_net.c.
pub const driver_virtio = 1
pub const driver_apple_wifi = 2

pub struct SockaddrIn {
pub mut:
	sin_family u16
	sin_port   u16
	sin_addr   u32
	sin_zero   [8]u8
}

pub struct InetSocket {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event

	handle     &C.vinix_socket = unsafe { nil }
	socktype   int
	protocol   int
	listening  bool
	reuseaddr  int
	broadcast  int
	keepalive  int
}

__global (
	net_lock       klock.Lock
	sockets_lock   klock.Lock
	sockets        [max_sockets]voidptr
	network_ready  = false
	last_address   = u32(0)
)

pub fn initialise() {
	net_lock.acquire()
	C.vinix_net_init()
	net_lock.release()
}

fn register(mut socket InetSocket) bool {
	sockets_lock.acquire()
	defer {
		sockets_lock.release()
	}
	for i := 0; i < max_sockets; i++ {
		if sockets[i] == unsafe { nil } {
			sockets[i] = voidptr(socket)
			return true
		}
	}
	return false
}

fn unregister(socket &InetSocket) {
	sockets_lock.acquire()
	for i := 0; i < max_sockets; i++ {
		if sockets[i] == voidptr(socket) {
			sockets[i] = unsafe { nil }
			break
		}
	}
	sockets_lock.release()
}

// Refresh every descriptor after an operation that can synchronously deliver
// loopback traffic. The caller holds net_lock, matching the normal poll path.
fn refresh_registered_sockets() {
	sockets_lock.acquire()
	for i := 0; i < max_sockets; i++ {
		if sockets[i] != unsafe { nil } {
			mut socket := unsafe { &InetSocket(sockets[i]) }
			socket.refresh_status()
		}
	}
	sockets_lock.release()
}

fn (mut this InetSocket) refresh_status() {
	ready := C.vinix_socket_ready(this.handle)
	mut status := int(0)
	if ready & ready_read != 0 {
		status |= file.pollin
	}
	if ready & ready_write != 0 {
		status |= file.pollout
	}
	if ready & ready_error != 0 {
		status |= file.pollerr
	}
	if ready & ready_hangup != 0 {
		status |= file.pollhup
	}
	if status != this.status {
		this.status = status
		event.trigger(mut this.event, false)
	}
}

// The architecture drivers feed this from the scheduler's existing idle
// poller.  That keeps packet callbacks out of IRQ context and serialises every
// lwIP entry point behind one kernel lock.
pub fn poll() {
	mut address := u32(0)
	mut netmask := u32(0)
	mut gateway := u32(0)
	mut dns := [3]u32{}
	net_lock.acquire()
	C.vinix_net_poll(u32(time.monotonic_ns() / 1000000))
	has_configuration := C.vinix_net_config(&address, &netmask, &gateway, &dns[0]) != 0
	refresh_registered_sockets()
	net_lock.release()

	if has_configuration && (!network_ready || address != last_address) {
		network_ready = true
		last_address = address
		C.printf(c'net: DHCP lease %u.%u.%u.%u\n', address & 0xff, (address >> 8) & 0xff,
			(address >> 16) & 0xff, (address >> 24) & 0xff)
		mut contents := ''
		for server in dns {
			if server != 0 {
				contents += 'nameserver ${server & 0xff}.${(server >> 8) & 0xff}.${(server >> 16) & 0xff}.${(server >> 24) & 0xff}\n'
			}
		}
		contents += 'options attempts:2 timeout:2\n'
		fs.write_kernel_file('/etc/resolv.conf', contents.str, u64(contents.len))
	}
}

pub fn attach(mac &[6]u8, driver int) bool {
	net_lock.acquire()
	ret := unsafe { C.vinix_net_attach(&mac[0], driver) }
	net_lock.release()
	return ret == 0
}

pub fn detach() {
	net_lock.acquire()
	C.vinix_net_detach()
	net_lock.release()
	network_ready = false
	last_address = 0
}

pub fn receive(frame voidptr, length u64) bool {
	net_lock.acquire()
	ret := C.vinix_net_input(frame, length)
	net_lock.release()
	return ret == 0
}

pub fn configuration(address &u32, netmask &u32, gateway &u32, dns &[3]u32) bool {
	net_lock.acquire()
	ret := unsafe { C.vinix_net_config(address, netmask, gateway, &dns[0]) }
	net_lock.release()
	return ret != 0
}

fn set_error(code int) {
	if code > 0 {
		errno.set(u64(code))
	} else {
		errno.set(u64(-code))
	}
}

fn new_with_handle(handle &C.vinix_socket, socktype int, protocol int) ?&InetSocket {
	if handle == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	mut socket := &InetSocket{
		refcount: 1
		handle: unsafe { handle }
		socktype: socktype
		protocol: protocol
	}
	if !register(mut socket) {
		C.vinix_socket_free(handle)
		unsafe { free(socket) }
		errno.set(errno.enfile)
		return none
	}
	net_lock.acquire()
	socket.refresh_status()
	net_lock.release()
	return socket
}

pub fn create(@type int, protocol int) ?&InetSocket {
	socktype := @type & sock_pub.sock_type_mask
	if socktype != sock_pub.sock_stream && socktype != sock_pub.sock_dgram {
		errno.set(errno.esocktnosupport)
		return none
	}
	if (socktype == sock_pub.sock_stream && protocol != 0 && protocol != ipproto_tcp)
		|| (socktype == sock_pub.sock_dgram && protocol != 0 && protocol != 17) {
		errno.set(errno.eprotonosupport)
		return none
	}
	actual_protocol := if protocol != 0 {
		protocol
	} else if socktype == sock_pub.sock_stream {
		ipproto_tcp
	} else {
		17
	}
	net_lock.acquire()
	handle := C.vinix_socket_new(socktype, actual_protocol)
	net_lock.release()
	return new_with_handle(handle, socktype, actual_protocol)
}

fn address(_addr voidptr, addrlen u32) ?&SockaddrIn {
	if _addr == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	if addrlen < sizeof(SockaddrIn) {
		errno.set(errno.einval)
		return none
	}
	addr := unsafe { &SockaddrIn(_addr) }
	if addr.sin_family != sock_pub.af_inet {
		errno.set(errno.eafnosupport)
		return none
	}
	return addr
}

fn wait_for_event(mut this InetSocket) bool {
	this.l.release()
	mut events := [&this.event]
	event.await(mut events, true) or {
		unsafe { events.free() }
		this.l.acquire()
		errno.set(errno.eintr)
		return false
	}
	unsafe { events.free() }
	this.l.acquire()
	return true
}

fn (mut this InetSocket) read(handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	open_handle := unsafe { &file.Handle(handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}
	for {
		net_lock.acquire()
		ret := C.vinix_socket_recv(this.handle, buf, count, unsafe { nil }, unsafe { nil })
		this.refresh_status()
		net_lock.release()
		if ret >= 0 {
			return i64(ret)
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			set_error(ret)
			return none
		}
		if !wait_for_event(mut this) {
			return none
		}
	}
	return none
}

fn (mut this InetSocket) write(handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	open_handle := unsafe { &file.Handle(handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}
	for {
		net_lock.acquire()
		ret := C.vinix_socket_send(this.handle, buf, count, 0, 0, 0)
		refresh_registered_sockets()
		net_lock.release()
		if ret >= 0 {
			return i64(ret)
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			set_error(ret)
			return none
		}
		if !wait_for_event(mut this) {
			return none
		}
	}
	return none
}

pub fn (mut this InetSocket) sendto(handle voidptr, buf voidptr, count u64, _addr voidptr, addrlen u32) ?i64 {
	open_handle := unsafe { &file.Handle(handle) }
	mut addr := &SockaddrIn(unsafe { nil })
	mut has_address := 0
	if _addr != unsafe { nil } {
		addr = address(_addr, addrlen)?
		has_address = 1
	}
	this.l.acquire()
	defer {
		this.l.release()
	}
	for {
		net_lock.acquire()
		ret := C.vinix_socket_send(this.handle, buf, count,
			if has_address != 0 { addr.sin_addr } else { u32(0) },
			if has_address != 0 { addr.sin_port } else { u16(0) }, has_address)
		refresh_registered_sockets()
		net_lock.release()
		if ret >= 0 {
			return i64(ret)
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			set_error(ret)
			return none
		}
		if !wait_for_event(mut this) {
			return none
		}
	}
	return none
}

pub fn (mut this InetSocket) recvfrom(handle voidptr, buf voidptr, count u64, _addr voidptr, addrlen &u32) ?i64 {
	open_handle := unsafe { &file.Handle(handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}
	for {
		mut source := SockaddrIn{sin_family: sock_pub.af_inet}
		net_lock.acquire()
		ret := C.vinix_socket_recv(this.handle, buf, count, &source.sin_addr, &source.sin_port)
		this.refresh_status()
		net_lock.release()
		if ret >= 0 {
			if _addr != unsafe { nil } && addrlen != unsafe { nil } {
				sock_pub.copy_out_sockaddr(_addr, addrlen, &source, sizeof(SockaddrIn))
			}
			return i64(ret)
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			set_error(ret)
			return none
		}
		if !wait_for_event(mut this) {
			return none
		}
	}
	return none
}

fn (mut this InetSocket) bind(_handle voidptr, _addr voidptr, addrlen u32) ? {
	addr := address(_addr, addrlen)?
	net_lock.acquire()
	ret := C.vinix_socket_bind(this.handle, addr.sin_addr, addr.sin_port)
	this.refresh_status()
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
}

fn (mut this InetSocket) connect(handle voidptr, _addr voidptr, addrlen u32) ? {
	addr := address(_addr, addrlen)?
	open_handle := unsafe { &file.Handle(handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}
	net_lock.acquire()
	ret := C.vinix_socket_connect(this.handle, addr.sin_addr, addr.sin_port)
	refresh_registered_sockets()
	net_lock.release()
	if ret == 0 {
		return
	}
	if ret != int(errno.einprogress) {
		set_error(ret)
		return none
	}
	if open_handle.flags & resource.o_nonblock != 0 {
		errno.set(errno.einprogress)
		return none
	}
	for {
		if !wait_for_event(mut this) {
			return none
		}
		net_lock.acquire()
		error_code := C.vinix_socket_error(this.handle, 0)
		this.refresh_status()
		connected := this.status & file.pollout != 0
		net_lock.release()
		if error_code != 0 {
			set_error(error_code)
			return none
		}
		if connected {
			return
		}
	}
}

fn (mut this InetSocket) listen(_handle voidptr, backlog int) ? {
	net_lock.acquire()
	ret := C.vinix_socket_listen(this.handle, backlog)
	this.refresh_status()
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
	this.listening = true
}

fn (mut this InetSocket) accept(handle voidptr) ?&resource.Resource {
	open_handle := unsafe { &file.Handle(handle) }
	if !this.listening {
		errno.set(errno.einval)
		return none
	}
	this.l.acquire()
	defer {
		this.l.release()
	}
	for {
		net_lock.acquire()
		child_handle := C.vinix_socket_accept(this.handle)
		this.refresh_status()
		net_lock.release()
		if child_handle != unsafe { nil } {
			mut child := new_with_handle(child_handle, sock_pub.sock_stream, ipproto_tcp)?
			return &resource.Resource(*child)
		}
		if open_handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.ewouldblock)
			return none
		}
		if !wait_for_event(mut this) {
			return none
		}
	}
	return none
}

fn socket_name(mut this InetSocket, peer bool, _addr voidptr, addrlen &u32) ? {
	if addrlen == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	mut addr := SockaddrIn{sin_family: sock_pub.af_inet}
	net_lock.acquire()
	ret := if peer {
		C.vinix_socket_peer(this.handle, &addr.sin_addr, &addr.sin_port)
	} else {
		C.vinix_socket_local(this.handle, &addr.sin_addr, &addr.sin_port)
	}
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
	sock_pub.copy_out_sockaddr(_addr, addrlen, &addr, sizeof(SockaddrIn))
}

fn (mut this InetSocket) peername(_handle voidptr, _addr voidptr, addrlen &u32) ? {
	socket_name(mut this, true, _addr, addrlen)?
}

fn (mut this InetSocket) sockname(_handle voidptr, _addr voidptr, addrlen &u32) ? {
	socket_name(mut this, false, _addr, addrlen)?
}

fn (mut this InetSocket) shutdown(_handle voidptr, how int) ? {
	net_lock.acquire()
	ret := C.vinix_socket_shutdown(this.handle, how)
	this.refresh_status()
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
}

fn (mut this InetSocket) recvmsg(handle voidptr, msg &sock_pub.MsgHdr, flags int) ?u64 {
	if flags != 0 {
		errno.set(errno.eopnotsupp)
		return none
	}
	mut count := u64(0)
	for i := u64(0); i < msg.msg_iovlen; i++ {
		count += unsafe { msg.msg_iov[i].iov_len }
	}
	buffer := unsafe { malloc(if count > 0 { count } else { 1 }) }
	if buffer == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	mut source_len := msg.msg_namelen
	read_count := this.recvfrom(handle, buffer, count, msg.msg_name, &source_len) or {
		unsafe { free(buffer) }
		return none
	}
	unsafe { msg.msg_namelen = source_len }
	mut copied := u64(0)
	for i := u64(0); i < msg.msg_iovlen && copied < u64(read_count); i++ {
		iov := unsafe { msg.msg_iov[i] }
		amount := if iov.iov_len < u64(read_count) - copied { iov.iov_len } else { u64(read_count) - copied }
		unsafe { C.memcpy(iov.iov_base, voidptr(u64(buffer) + copied), amount) }
		copied += amount
	}
	unsafe { free(buffer) }
	return copied
}

fn (mut this InetSocket) getsockopt(_handle voidptr, level int, optname int) ?int {
	if level == sock_pub.sol_socket {
		match optname {
			sock_pub.so_type { return this.socktype }
			sock_pub.so_error {
				net_lock.acquire()
				value := C.vinix_socket_error(this.handle, 1)
				this.refresh_status()
				net_lock.release()
				return value
			}
			sock_pub.so_acceptconn { return if this.listening { 1 } else { 0 } }
			sock_pub.so_domain { return sock_pub.af_inet }
			sock_pub.so_protocol { return this.protocol }
			sock_pub.so_sndbuf, sock_pub.so_rcvbuf { return 16 * 1460 }
			sock_pub.so_reuseaddr, sock_pub.so_reuseport { return this.reuseaddr }
			sock_pub.so_keepalive { return this.keepalive }
			sock_pub.so_broadcast { return this.broadcast }
			else {}
		}
	} else if level == ipproto_ip && optname in [ip_tos, ip_ttl] {
		mut value := int(0)
		net_lock.acquire()
		ret := C.vinix_socket_get_option(this.handle, level, optname, &value)
		net_lock.release()
		if ret == 0 {
			return value
		}
	} else if level == ipproto_tcp && optname == tcp_nodelay && this.socktype == sock_pub.sock_stream {
		mut value := int(0)
		net_lock.acquire()
		ret := C.vinix_socket_get_option(this.handle, level, optname, &value)
		net_lock.release()
		if ret == 0 {
			return value
		}
	}
	errno.set(errno.enoprotoopt)
	return none
}

fn (mut this InetSocket) setsockopt(_handle voidptr, level int, optname int, value int) ? {
	mut supported := false
	if level == sock_pub.sol_socket {
		match optname {
			sock_pub.so_reuseaddr, sock_pub.so_reuseport {
				this.reuseaddr = value
				supported = true
			}
			sock_pub.so_keepalive {
				this.keepalive = value
				supported = true
			}
			sock_pub.so_broadcast {
				this.broadcast = value
				supported = true
			}
			sock_pub.so_sndbuf, sock_pub.so_rcvbuf, sock_pub.so_linger, sock_pub.so_oobinline {
				return
			}
			else {}
		}
	} else if level == ipproto_ip && optname in [ip_tos, ip_ttl] {
		supported = true
	} else if level == ipproto_tcp && optname == tcp_nodelay && this.socktype == sock_pub.sock_stream {
		supported = true
	}
	if !supported {
		errno.set(errno.enoprotoopt)
		return none
	}
	net_lock.acquire()
	ret := C.vinix_socket_set_option(this.handle, level, optname, value)
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
}

fn (mut this InetSocket) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	if request == ioctl.fionread {
		if argp == unsafe { nil } {
			errno.set(errno.efault)
			return none
		}
		net_lock.acquire()
		value := C.vinix_socket_available(this.handle)
		net_lock.release()
		unsafe { *&int(argp) = value }
		return 0
	}
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this InetSocket) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	unregister(this)
	net_lock.acquire()
	C.vinix_socket_free(this.handle)
	net_lock.release()
}

fn (mut this InetSocket) grow(_handle voidptr, _new_size u64) ? {}
fn (mut this InetSocket) link(_handle voidptr) ? {}
fn (mut this InetSocket) unlink(_handle voidptr) ? {}
fn (mut this InetSocket) mmap(_handle voidptr, _page u64, _flags int) voidptr { return 0 }
