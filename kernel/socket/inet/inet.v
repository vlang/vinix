@[has_globals]
module inet

import kbudget
import errno
import event
import event.eventstruct
import file
import fs
import ioctl
import katomic
import klock
import krandom
import lib
import limine
import netcore as _
import proc
import resource
import socket.public as sock_pub
import stat
import time
import usercopy

struct C.vinix_socket {}

fn C.vinix_net_init()
fn C.vinix_net_poll(now_ms u32)
fn C.vinix_net_attach(mac &u8, driver i32) i32
fn C.vinix_net_link(mac &u8, mtu &u32) i32
fn C.vinix_net_detach()
fn C.vinix_net_input(frame voidptr, length u64) i32
fn C.vinix_net_config(address &u32, netmask &u32, gateway &u32, dns &u32) i32
fn C.vinix_socket_free(socket &C.vinix_socket)
fn C.vinix_socket_pending(socket &C.vinix_socket) i32
fn C.vinix_socket_abort_close(socket &C.vinix_socket)
fn C.vinix_socket_bind(socket &C.vinix_socket, address u32, port u16) i32
fn C.vinix_socket_connect(socket &C.vinix_socket, address u32, port u16) i32
fn C.vinix_socket_listen(socket &C.vinix_socket, backlog i32) i32
fn C.vinix_socket_accept(socket &C.vinix_socket) &C.vinix_socket
fn C.vinix_socket_send(socket &C.vinix_socket, data voidptr, length u64, address u32, port u16, has_address i32) i32
fn C.vinix_socket_recv(socket &C.vinix_socket, data voidptr, length u64, address &u32, port &u16) i32
fn C.vinix_socket_shutdown(socket &C.vinix_socket, how i32) i32
fn C.vinix_socket_local(socket &C.vinix_socket, address &u32, port &u16) i32
fn C.vinix_socket_peer(socket &C.vinix_socket, address &u32, port &u16) i32
fn C.vinix_socket_ready(socket &C.vinix_socket) i32
fn C.vinix_socket_error(socket &C.vinix_socket, clear i32) i32
fn C.vinix_socket_available(socket &C.vinix_socket) i32
fn C.vinix_socket_set_option(socket &C.vinix_socket, level i32, option i32, value i32) i32
fn C.vinix_socket_get_option(socket &C.vinix_socket, level i32, option i32, value &i32) i32

const max_sockets = 256
const ready_read = 1
const ready_write = 2
const ready_error = 4
const ready_hangup = 8
const ipproto_tcp = 6
const ipproto_ip = 0
const ipproto_ipv6 = 41
const ipv6_v6only = 26
const ipv6_unicast_hops = 16
const tcp_nodelay = 1

// TCP keepalive controls, in seconds and probes, applied by the transport.
const tcp_keepidle = 4
const tcp_keepintvl = 5
const tcp_keepcnt = 6
const ip_tos = 1
const ip_ttl = 2
const ip_recverr = 11

// Driver identifiers shared with netcore.
pub const driver_virtio = 1
pub const driver_apple_wifi = 2
pub const driver_e1000 = 3

pub struct SockaddrIn {
pub mut:
	sin_family u16
	sin_port   u16
	sin_addr   u32
	sin_zero   [8]u8
}

pub struct InetSocket {
pub mut:
	kernel_charge kbudget.Charge
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event

	handle     &C.vinix_socket = unsafe { nil }
	socktype   int
	protocol   int
	family     int
	listening  bool
	// IP_RECVERR, kept for getsockopt(). No error queue is kept: ICMP errors
	// are not reported to a socket at all.
	recverr int
	// SO_RCVTIMEO and SO_SNDTIMEO, in nanoseconds; 0 waits for good.
	recv_timeout_ns u64
	send_timeout_ns u64
	// SO_LINGER controls the final close: wait for queued bytes or abort.
	linger_on      int
	linger_seconds int
	// Observe ACK progress even while POLLOUT remains set.
	last_pending int
	last_available int
	// The interface box its descriptor is made with, freed with the socket.
	box &resource.Resource = unsafe { nil }
}

__global (
	net_lock             klock.Lock
	sockets_lock         klock.Lock
	sockets              [max_sockets]voidptr
	socket_inode_counter = u64(1)
	network_ready        = false
	last_address         = u32(0)
	// Whether the resolver file has actually reached the root init will see,
	// and the text waiting to be written there.
	resolver_published   = false
	pending_resolver     = ''
	last_poll_ms         = u32(0)
	// Resolvers the boot command line lists after the ones DHCP gives.
	extra_nameservers    [max_extra_nameservers]u32
)

// Two, so that with DHCP's own at least one fits in the three that musl and
// glibc read from resolv.conf.
const max_extra_nameservers = 2

pub fn initialise() {
	read_extra_nameservers()
	// lwIP draws its ports, IDs and sequence numbers from the kernel's
	// generator (inet/net_random.v) from lwip_init() on, before /dev/random is
	// set up.
	krandom.initialise()
	net_lock.acquire()
	C.vinix_net_init()
	net_lock.release()
	fs.register_net_tcp_snapshot(proc_net_tcp_text)
	fs.register_net_ipv6_snapshots(proc_net_tcp6_text, proc_net_if_inet6_text)
}

// Linux tools match the inode in /proc/net/tcp with /proc/<pid>/fd links.
// Both views must describe the same live Vinix socket.
fn proc_net_tcp_text() string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(4096) }
	text.add('  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n')
	net_lock.acquire()
	sockets_lock.acquire()
	mut row := 0
	for i := 0; i < max_sockets; i++ {
		if sockets[i] == unsafe { nil } {
			continue
		}
		socket := unsafe { &InetSocket(sockets[i]) }
		if socket.socktype != sock_pub.sock_stream || socket.family != sock_pub.af_inet {
			continue
		}
		mut local_address := u32(0)
		mut local_port := u16(0)
		if C.vinix_socket_local(socket.handle, &local_address, &local_port) != 0 || local_port == 0 {
			continue
		}
		mut remote_address := u32(0)
		mut remote_port := u16(0)
		connected := C.vinix_socket_peer(socket.handle, &remote_address, &remote_port) == 0
		if !connected && !socket.listening {
			continue
		}
		text.add_unsigned(u64(row))
		text.add(': ')
		text.add_radix(u64(local_address), 16, 8)
		text.add_byte(`:`)
		text.add_radix(u64((local_port >> 8) | (local_port << 8)), 16, 4)
		text.add_byte(` `)
		text.add_radix(u64(remote_address), 16, 8)
		text.add_byte(`:`)
		text.add_radix(u64((remote_port >> 8) | (remote_port << 8)), 16, 4)
		text.add(if connected { ' 01 ' } else { ' 0a ' })
		text.add('00000000:00000000 00:00000000 00000000 0 0 ')
		text.add_unsigned(socket.stat.ino)
		text.add_byte(`\n`)
		row++
	}
	sockets_lock.release()
	net_lock.release()
	return text.str()
}

fn register(mut socket InetSocket) bool {
	sockets_lock.acquire()
	defer {
		sockets_lock.release()
	}
	for i := 0; i < max_sockets; i++ {
		if sockets[i] == unsafe { nil } {
			socket.stat.ino = socket_inode_counter
			socket_inode_counter++
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
	is_ready := C.vinix_socket_ready(this.handle)
	mut status := int(0)
	if is_ready & ready_read != 0 {
		status |= file.pollin
	}
	if is_ready & ready_write != 0 {
		status |= file.pollout
	}
	if is_ready & ready_error != 0 {
		status |= file.pollerr
	}
	if is_ready & ready_hangup != 0 {
		status |= file.pollhup
	}
	pending := C.vinix_socket_pending(this.handle)
	available := C.vinix_socket_available(this.handle)
	if status != this.status || pending != this.last_pending || available != this.last_available {
		this.last_pending = pending
		this.last_available = available
		this.status = status
		event.trigger(mut this.event, false)
	}
}

// The architecture drivers feed this from the scheduler's existing idle
// poller.  That keeps packet callbacks out of IRQ context and serialises every
// lwIP entry point behind one kernel lock.
pub fn poll() {
	// The idle loop calls this hundreds of thousands of times a second, and
	// every call takes the one lock that every socket operation also needs.
	// lwIP's finest timer runs at 250 ms and received frames arrive through
	// receive() rather than from here, so there is nothing to gain from
	// entering the stack more often than once a millisecond -- and plenty to
	// lose: a thread waiting to send or receive was starved by the poller
	// holding the lock, and transfers stalled mid-download.
	now_ms := u32(time.monotonic_ns() / 1000000)
	if last_poll_ms != 0 && now_ms == last_poll_ms {
		return
	}
	last_poll_ms = now_ms

	mut address := u32(0)
	mut netmask := u32(0)
	mut gateway := u32(0)
	mut dns := [3]u32{}
	if !net_lock.test_and_acquire() {
		// Somebody is inside the stack. It will be polled on the next tick.
		return
	}
	C.vinix_net_poll(now_ms)
	has_configuration := C.vinix_net_config(&address, &netmask, &gateway, &dns[0]) != 0
	refresh_registered_sockets()
	net_lock.release()

	// Built once per address and kept until publish_resolver() writes it.
	// Rebuilt at every poll until then, each copy was lost: a millisecond at
	// a time for as long as the root had no /etc.
	if has_configuration && (address != last_address
		|| (!resolver_published && pending_resolver.len == 0)) {
		// kprintf(), not the C printf this used: that one is compiled out of a
		// PROD kernel, so the one line that says whether the machine has an
		// address was invisible in exactly the builds anyone debugs.
		if !network_ready {
			C.kprintf(c'net: DHCP lease %llu.%llu.%llu.%llu\n', u64(address & 0xff),
				u64((address >> 8) & 0xff), u64((address >> 16) & 0xff), u64(address >> 24))
		}
		network_ready = true
		mut contents := lib.new_text(160)
		mut listed := 0
		for server in dns {
			if server != 0 {
				add_nameserver(mut contents, server)
				listed++
			}
		}
		for server in extra_nameservers {
			if server == 0 || listed >= 3 || server == dns[0] || server == dns[1]
				|| server == dns[2] {
				continue
			}
			add_nameserver(mut contents, server)
			listed++
		}
		contents.add('options attempts:2 timeout:2\n')
		// This runs from the scheduler's poll callback, which is no place to
		// walk the VFS and write to a disk-backed root. Leave the text for
		// publish_resolver(), which a kernel thread calls. The text it replaces
		// is not freed: publish_resolver() may be writing it out right now.
		pending_resolver = contents.str()
		last_address = address
	}
}

fn add_nameserver(mut contents lib.Text, server u32) {
	contents.add('nameserver ')
	contents.add_unsigned(u64(server & 0xff))
	contents.add_byte(`.`)
	contents.add_unsigned(u64((server >> 8) & 0xff))
	contents.add_byte(`.`)
	contents.add_unsigned(u64((server >> 16) & 0xff))
	contents.add_byte(`.`)
	contents.add_unsigned(u64((server >> 24) & 0xff))
	contents.add_byte(`\n`)
}

fn is_cmdline_space(c u8) bool {
	return c == ` ` || c == `\t` || c == `\r` || c == `\n`
}

// `vinix.nameservers=A.B.C.D[,A.B.C.D]` on the command line names resolvers to
// list after DHCP's. QEMU's user network answers DNS at 10.0.2.3 by asking
// only the first resolver the host has; when that one does not answer -- one
// set by hand for another network -- the guest resolved nothing while the
// host, which asks the others too, worked. scripts/run-aarch64.sh passes the others.
fn read_extra_nameservers() {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return
	}
	text := unsafe { &u8(kernel_file.cmdline) }
	key := 'vinix.nameservers='
	mut index := 0
	for unsafe { text[index] } != 0 {
		if is_cmdline_space(unsafe { text[index] }) {
			index++
			continue
		}
		// The command line's terminating zero differs from every key byte,
		// so this stops at the end of a short command line.
		mut matches := true
		for offset := 0; offset < key.len; offset++ {
			if unsafe { text[index + offset] } != key[offset] {
				matches = false
				break
			}
		}
		if matches {
			parse_nameservers(unsafe { &text[index + key.len] })
			return
		}
		for unsafe { text[index] } != 0 && !is_cmdline_space(unsafe { text[index] }) {
			index++
		}
	}
}

// Dotted quads separated by commas, up to a space or the end. One that does
// not parse is skipped. The address is kept in network order, as lwIP's are.
fn parse_nameservers(value &u8) {
	mut count := 0
	mut address := u32(0)
	mut octet := u32(0)
	mut octets := 0
	mut digits := 0
	mut valid := true
	for index := 0; count < max_extra_nameservers; index++ {
		c := unsafe { value[index] }
		if c >= `0` && c <= `9` {
			octet = octet * 10 + u32(c - `0`)
			digits++
			if digits > 3 || octet > 255 {
				valid = false
			}
			continue
		}
		if c != `.` && c != `,` && c != 0 && !is_cmdline_space(c) {
			valid = false
			continue
		}
		if digits == 0 || octets == 4 {
			valid = false
		} else {
			address |= octet << (8 * octets)
			octets++
		}
		octet = 0
		digits = 0
		if c == `.` {
			continue
		}
		if valid && octets == 4 && address != 0 {
			extra_nameservers[count] = address
			count++
		}
		if c != `,` {
			return
		}
		address = 0
		octets = 0
		valid = true
	}
}

// Write out the resolver list DHCP produced, from a context that is allowed to
// touch the filesystem. DHCP finishes long before the system volume is mounted,
// so the first attempts land on a root that has no /etc and is about to be
// replaced; the text is kept until a write succeeds. Publishing it once and
// latching left the machine with no resolver at all after the root moved to
// disk, and every package operation failed with "DHCP did not create
// /etc/resolv.conf" on a machine whose network was working.
pub fn publish_resolver() {
	if resolver_published || pending_resolver.len == 0 {
		return
	}
	contents := pending_resolver
	if fs.write_kernel_file('/etc/resolv.conf', contents.str, u64(contents.len)) {
		resolver_published = true
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
	resolver_published = false
	pending_resolver = ''
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

// The hardware address and MTU of the network interface, once a driver has
// attached one.
pub fn link_info(mac &[6]u8, mtu &u32) bool {
	net_lock.acquire()
	ret := C.vinix_net_link(&mac[0], mtu)
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

fn new_with_handle(handle &C.vinix_socket, socktype int, protocol int, family int) ?&InetSocket {
	if handle == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	charge := proc.reserve_kernel(.socket, 128 * 1024) or {
		net_lock.acquire(); C.vinix_socket_free(handle); net_lock.release()
		return none
	}
	// The descriptor made from it holds the only reference, so closing the
	// last one frees the pcb. A creator's reference that nothing dropped kept
	// every closed socket's pcb, and the 65th UDP socket, one DNS query in a
	// docker pull, failed with ENOMEM.
	mut socket := &InetSocket{
		kernel_charge: charge
		refcount: 0
		handle:   unsafe { handle }
		family:   family
		socktype: socktype
		protocol: protocol
		family: family
	}
	socket.stat.mode = stat.ifsock | 0o777
	if !register(mut socket) {
		net_lock.acquire()
		C.vinix_socket_free(handle)
		net_lock.release()
		kbudget.release(charge)
		unsafe { free(socket) }
		errno.set(errno.enfile)
		return none
	}
	socket.box = &resource.Resource(socket) @[freed]
	net_lock.acquire()
	socket.refresh_status()
	net_lock.release()
	return socket
}

pub fn create(@type int, protocol int) ?&InetSocket {
	return create_family(@type, protocol, sock_pub.af_inet)
}

pub fn create_family(@type int, protocol int, family int) ?&InetSocket {
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
	handle := C.vinix_socket_new_family(socktype, actual_protocol, family)
	net_lock.release()
	return new_with_handle(handle, socktype, actual_protocol, family)
}

// When a call that may wait `timeout_ns` gives up, or 0 for never.
fn deadline_after(timeout_ns u64) u64 {
	return if timeout_ns == 0 { u64(0) } else { time.monotonic_ns() + timeout_ns }
}

// Wait for the socket to change, until `deadline` if it is not 0. A wait that
// runs out ends as EAGAIN, as a timeout SO_RCVTIMEO or SO_SNDTIMEO set does.
fn wait_for_event(mut this InetSocket, deadline u64) bool {
	generation := event.generation(mut this.event)
	return wait_for_event_since(mut this, deadline, generation)
}

fn wait_for_event_since(mut this InetSocket, deadline u64, generation u64) bool {
	mut timer := &time.Timer(unsafe { nil })
	if deadline != 0 {
		now := time.monotonic_ns()
		if now >= deadline {
			errno.set(errno.eagain)
			return false
		}
		left := deadline - now
		timer = time.new_timer(time.TimeSpec{
			tv_sec:  i64(left / 1000000000)
			tv_nsec: i64(left % 1000000000)
		})
	}
	this.l.release()
	mut storage := [&this.event, &this.event]!
	mut count := 1
	if timer != unsafe { nil } {
		storage[1] = &timer.event
		count = 2
	}
	mut events := unsafe { event.stack_list(&storage[0], count) }
	result := event.await_from_generation(mut events, true, 0, generation)
	if timer != unsafe { nil } {
		timer.disarm()
		unsafe { free(timer) }
	}
	this.l.acquire()
	which := result or {
		errno.set(errno.eintr)
		return false
	}
	if which == 1 {
		errno.set(errno.eagain)
		return false
	}
	return true
}

// SO_RCVTIMEO or SO_SNDTIMEO, for setsockopt(2) and getsockopt(2).
pub fn (mut this InetSocket) set_timeout(send bool, timeout_ns u64) {
	if send {
		this.send_timeout_ns = timeout_ns
	} else {
		this.recv_timeout_ns = timeout_ns
	}
}

pub fn (this &InetSocket) timeout(send bool) u64 {
	return if send { this.send_timeout_ns } else { this.recv_timeout_ns }
}

// SO_LINGER, for setsockopt(2) and getsockopt(2).
pub fn (mut this InetSocket) set_linger(on int, seconds int) ? {
	if seconds < 0 {
		errno.set(errno.einval)
		return none
	}
	this.linger_on = if on != 0 { 1 } else { 0 }
	this.linger_seconds = seconds
}

pub fn (this &InetSocket) linger() (int, int) {
	return this.linger_on, this.linger_seconds
}

fn (mut this InetSocket) read(handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	open_handle := unsafe { &file.Handle(handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}
	deadline := deadline_after(this.recv_timeout_ns)
	for {
		net_lock.acquire()
		ret := C.vinix_socket_recv(this.handle, buf, count, unsafe { nil }, unsafe { nil })
		this.refresh_status()
		net_lock.release()
		if ret >= 0 {
			proc.account_network_transfer(i64(ret), false)
			return i64(ret)
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			set_error(ret)
			return none
		}
		if !wait_for_event(mut this, deadline) {
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
	deadline := deadline_after(this.send_timeout_ns)
	for {
		net_lock.acquire()
		ret := C.vinix_socket_send(this.handle, buf, count, 0, 0, 0)
		refresh_registered_sockets()
		net_lock.release()
		if ret >= 0 {
			proc.account_network_transfer(i64(ret), true)
			return i64(ret)
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			set_error(ret)
			return none
		}
		if !wait_for_event(mut this, deadline) {
			return none
		}
	}
	return none
}

pub fn (mut this InetSocket) sendto(handle voidptr, buf voidptr, count u64, _addr voidptr, addrlen u32) ?i64 {
	open_handle := unsafe { &file.Handle(handle) }
	mut endpoint := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	mut has_address := 0
	if _addr != unsafe { nil } {
		fill_endpoint(_addr, addrlen, this.family, mut endpoint)?
		has_address = 1
	}
	this.l.acquire()
	defer {
		this.l.release()
	}
	deadline := deadline_after(this.send_timeout_ns)
	for {
		net_lock.acquire()
		ret := C.vinix_socket_send_endpoint(this.handle, buf, count, endpoint, has_address)
		refresh_registered_sockets()
		net_lock.release()
		if ret >= 0 {
			proc.account_network_transfer(i64(ret), true)
			return i64(ret)
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			set_error(ret)
			return none
		}
		if !wait_for_event(mut this, deadline) {
			return none
		}
	}
	return none
}

pub fn (mut this InetSocket) recvfrom(handle voidptr, buf voidptr, count u64, _addr voidptr, addrlen &u32) ?i64 {
	return this.recvfrom_flags(handle, buf, count, _addr, addrlen, 0)
}

pub fn (mut this InetSocket) recvfrom_flags(handle voidptr, buf voidptr, count u64, _addr voidptr, addrlen &u32, flags int) ?i64 {
	open_handle := unsafe { &file.Handle(handle) }
	this.l.acquire()
	defer { this.l.release() }
	mut endpoint := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	deadline := deadline_after(this.recv_timeout_ns)
	peek := flags & 2 != 0
	waitall := this.socktype == sock_pub.sock_stream && flags & 0x100 != 0 && open_handle.flags & resource.o_nonblock == 0
	mut done := u64(0)
	for {
		net_lock.acquire()
		// A wait-all peek must not repeat the same packet into successive slots.
		// Wait for the requested prefix or EOF, then copy without consuming it.
		available := C.vinix_socket_available(this.handle)
		mut ret := i32(-int(errno.eagain))
		if !peek || !waitall || available >= i32(count) || available == 0 || this.status & file.pollhup != 0 {
			ret = C.vinix_socket_recv_endpoint_flags(this.handle, unsafe { voidptr(u64(buf) + done) }, count - done, endpoint, flags)
		}
		this.refresh_status()
		generation := event.generation(mut this.event)
		net_lock.release()
		if ret >= 0 {
			if !peek { proc.account_network_transfer(i64(ret), false) }
			if done == 0 && _addr != unsafe { nil } && addrlen != unsafe { nil } { copy_endpoint_out(endpoint, _addr, addrlen) }
			done += u64(ret)
			if peek || !waitall || ret == 0 || done >= count { return i64(done) }
			continue
		}
		if ret != -int(errno.eagain) || open_handle.flags & resource.o_nonblock != 0 {
			if done != 0 { return i64(done) }
			set_error(ret)
			return none
		}
		if !wait_for_event_since(mut this, deadline, generation) {
			if done != 0 { return i64(done) }
			return none
		}
	}
	return none
}

fn (mut this InetSocket) bind(_handle voidptr, _addr voidptr, addrlen u32) ? {
	mut endpoint := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	fill_endpoint(_addr, addrlen, this.family, mut endpoint)?
	net_lock.acquire()
	ret := C.vinix_socket_bind_endpoint(this.handle, endpoint)
	this.refresh_status()
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
}

fn (mut this InetSocket) connect(handle voidptr, _addr voidptr, addrlen u32) ? {
	mut endpoint := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	fill_endpoint(_addr, addrlen, this.family, mut endpoint)?
	open_handle := unsafe { &file.Handle(handle) }
	this.l.acquire()
	defer {
		this.l.release()
	}
	net_lock.acquire()
	ret := C.vinix_socket_connect_endpoint(this.handle, endpoint)
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
	// Linux gives up a blocking connect after SO_SNDTIMEO with EINPROGRESS;
	// the connection goes on being made.
	deadline := deadline_after(this.send_timeout_ns)
	for {
		if !wait_for_event(mut this, deadline) {
			if errno.get() == errno.eagain {
				errno.set(errno.einprogress)
			}
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
	deadline := deadline_after(this.recv_timeout_ns)
	for {
		net_lock.acquire()
		child_handle := C.vinix_socket_accept(this.handle)
		this.refresh_status()
		net_lock.release()
		if child_handle != unsafe { nil } {
			// Hand out the registered socket itself. Converting *child copied
			// it, and the copy's status never saw the traffic that arrived.
			mut child := new_with_handle(child_handle, sock_pub.sock_stream, ipproto_tcp, this.family)?
			child.recv_timeout_ns = this.recv_timeout_ns
			child.send_timeout_ns = this.send_timeout_ns
			child.linger_on = this.linger_on
			child.linger_seconds = this.linger_seconds
			return child.box
		}
		if open_handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.ewouldblock)
			return none
		}
		if !wait_for_event(mut this, deadline) {
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
	mut endpoint := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	net_lock.acquire()
	ret := C.vinix_socket_name_endpoint(this.handle, endpoint, if peer { 1 } else { 0 })
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
	copy_endpoint_out(endpoint, _addr, addrlen)
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
	scratch := proc.reserve_kernel(.scratch, count * 2 + 128)?
 defer { kbudget.release(scratch) }
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
	// No IPv4 ancillary data is supplied by this socket implementation. The
	// caller's msg_controllen is an input capacity, not an output length;
	// leaving it intact makes qemu-user parse uninitialised control bytes.
	unsafe {
		msg.msg_namelen = source_len
		msg.msg_controllen = 0
		msg.msg_flags = 0
	}
	mut copied := u64(0)
	for i := u64(0); i < msg.msg_iovlen && copied < u64(read_count); i++ {
		iov := unsafe { msg.msg_iov[i] }
		amount := if iov.iov_len < u64(read_count) - copied {
			iov.iov_len
		} else {
			u64(read_count) - copied
		}
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
			sock_pub.so_domain { return this.family }
			sock_pub.so_protocol { return this.protocol }
			else {}
		}
	} else if level == ipproto_ipv6 && this.family == sock_pub.af_inet6
		&& (optname == ipv6_v6only || optname == ipv6_unicast_hops) {
		mut value := i32(0)
		net_lock.acquire()
		ret := C.vinix_socket_get_option(this.handle, level, optname, unsafe { &value })
		net_lock.release()
		if ret == 0 { return int(value) }
		set_error(ret)
		return none
	} else if level == ipproto_ip && optname == ip_recverr {
		return this.recverr
	}
	mut value := i32(0)
	net_lock.acquire()
	ret := C.vinix_socket_get_option(this.handle, level, optname, &value)
	net_lock.release()
	if ret != 0 {
		set_error(ret)
		return none
	}
	return int(value)
}

fn (mut this InetSocket) setsockopt(_handle voidptr, level int, optname int, value int) ? {
	if level == ipproto_ip && optname == ip_recverr {
		// Existing glibc resolver compatibility. An ICMP/error queue is still
		// required before this setting can implement Linux IP_RECVERR.
		this.recverr = value
		return
	}
	net_lock.acquire()
	ret := C.vinix_socket_set_option(this.handle, level, optname, value)
	this.refresh_status()
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
		queued := i32(value)
		if !usercopy.copy_to_user(u64(argp), voidptr(&queued), sizeof(i32)) {
			errno.set(errno.efault)
			return none
		}
		return 0
	}
	if is_interface_ioctl(request) {
		return interface_ioctl(request, argp)
	}
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this InetSocket) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	// exit_process hands the dying thread to kernel_process before fd cleanup.
	// Positive linger runs in the background there, rather than delaying exit.
	closing_thread := proc.current_thread()
	may_wait := closing_thread != unsafe { nil } && voidptr(closing_thread.process) != voidptr(kernel_process)
	if this.socktype == sock_pub.sock_stream && this.linger_on != 0
		&& (this.linger_seconds == 0 || may_wait) {
		this.l.acquire()
		deadline := deadline_after(u64(this.linger_seconds) * 1000000000)
		for {
			net_lock.acquire()
			pending := C.vinix_socket_pending(this.handle)
			net_lock.release()
			if this.linger_seconds == 0 || (pending != 0 && time.monotonic_ns() >= deadline) {
				net_lock.acquire()
				C.vinix_socket_abort_close(this.handle)
				net_lock.release()
				break
			}
			if pending == 0 { break }
			if !wait_for_event(mut this, deadline) {
				net_lock.acquire()
				C.vinix_socket_abort_close(this.handle)
				net_lock.release()
				break
			}
		}
		this.l.release()
	}
	unregister(this)
	net_lock.acquire()
	C.vinix_socket_free(this.handle)
	net_lock.release()
	kbudget.release(this.kernel_charge)
	unsafe {
		free(voidptr(this.box))
		free(this)
	}
}

fn (mut this InetSocket) grow(_handle voidptr, _new_size u64) ? {}

fn (mut this InetSocket) link(_handle voidptr) ? {}

fn (mut this InetSocket) unlink(_handle voidptr) ? {}

fn (mut this InetSocket) mmap(_handle voidptr, _page u64, _flags int) voidptr { return 0 }
