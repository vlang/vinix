// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module netlink

import stat
import klock
import event.eventstruct
import event
import errno
import resource
import file
import katomic
import socket.inet
import socket.public as sock_pub

// A small NETLINK_ROUTE (rtnetlink) socket. It reports the interfaces, their
// addresses and routes: lo, and eth0 once a network driver has attached and
// DHCP has configured it. That is what `ip addr` and `ip route` ask, and what
// runc asks when it brings lo up in a container (RTM_GETLINK by name, then an
// RTM_NEWLINK). Changes are acknowledged but not applied: there is one network
// stack, configured by DHCP, and no routing control.

// nlmsghdr types.
const nlmsg_noop = u16(1)
const nlmsg_error = u16(2)
const nlmsg_done = u16(3)
const rtm_newlink = u16(16)
const rtm_getlink = u16(18)
const rtm_setlink = u16(19)
const rtm_newaddr = u16(20)
const rtm_getaddr = u16(22)
const rtm_newroute = u16(24)
const rtm_getroute = u16(26)

// nlmsghdr flags.
const nlm_f_request = u16(1)
const nlm_f_multi = u16(2)
const nlm_f_ack = u16(4)
const nlm_f_dump = u16(0x300) // NLM_F_ROOT | NLM_F_MATCH

const af_inet = u8(2)
const enodev = 19
const eopnotsupp = 95

// Operational states.
const if_oper_unknown = u8(0)
const if_oper_up = u8(6)

// Attribute types.
const ifla_address = u16(1)
const ifla_broadcast = u16(2)
const ifla_ifname = u16(3)
const ifla_mtu = u16(4)
const ifla_txqlen = u16(13)
const ifla_operstate = u16(16)
const ifa_address = u16(1)
const ifa_local = u16(2)
const ifa_label = u16(3)
const ifa_broadcast = u16(4)
const rta_dst = u16(1)
const rta_oif = u16(4)
const rta_gateway = u16(5)
const rta_prefsrc = u16(7)
const rta_table = u16(15)

const ifa_f_permanent = u8(0x80)
const rt_table_main = u8(254)
const rt_scope_universe = u8(0)
const rt_scope_link = u8(253)
const rt_scope_host = u8(254)
const rtprot_kernel = u8(2)
const rtprot_dhcp = u8(16)
const rtn_unicast = u8(1)

pub struct SockaddrNl {
pub mut:
	nl_family u16
	nl_pad    u16
	nl_pid    u32
	nl_groups u32
}

pub struct NetlinkSocket {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event

	protocol int
	nl_pid   u32
	groups   u32
	bound    bool
	// Reply datagrams waiting to be received, one per request sent.
	rx [][]u8
}

// NETLINK_ROUTE is the only family there is. Any other -- kernel uevents,
// generic netlink, netfilter -- is refused as Linux refuses a family it was
// built without, so a program sees EPROTONOSUPPORT and takes its fallback.
// Handing it a socket that answers as rtnetlink would leave a uevent listener
// waiting for ever, and hand a generic-netlink client replies it cannot parse.
const netlink_route = 0

pub fn create(@type int, protocol int) ?&NetlinkSocket {
	if protocol != netlink_route {
		errno.set(errno.eprotonosupport)
		return none
	}
	mut s := &NetlinkSocket{
		protocol: protocol
		status:   file.pollout
	}
	s.stat.mode = stat.ifsock | 0o777
	return s
}

// ── little-endian buffer helpers ─────────────────────────────────────────────

fn put_u16(mut b []u8, v u16) {
	b << u8(v)
	b << u8(v >> 8)
}

fn put_u32(mut b []u8, v u32) {
	b << u8(v)
	b << u8(v >> 8)
	b << u8(v >> 16)
	b << u8(v >> 24)
}

fn align4(mut b []u8) {
	for b.len % 4 != 0 {
		b << u8(0)
	}
}

fn read_u16(buf voidptr, off u64) u16 {
	p := unsafe { &u8(u64(buf) + off) }
	return u16(unsafe { p[0] }) | (u16(unsafe { p[1] }) << 8)
}

fn read_u32(buf voidptr, off u64) u32 {
	p := unsafe { &u8(u64(buf) + off) }
	return u32(unsafe { p[0] }) | (u32(unsafe { p[1] }) << 8) | (u32(unsafe { p[2] }) << 16) | (u32(unsafe { p[3] }) << 24)
}

// ── message builders ─────────────────────────────────────────────────────────

// Start a message in `m`, returning where it starts so finish_message can
// fill in its length.
fn start_message(mut m []u8, kind u16, flags u16, seq u32, pid u32) int {
	start := m.len
	put_u32(mut m, 0)
	put_u16(mut m, kind)
	put_u16(mut m, flags)
	put_u32(mut m, seq)
	put_u32(mut m, pid)
	return start
}

fn finish_message(mut m []u8, start int) {
	align4(mut m)
	total := u32(m.len - start)
	m[start] = u8(total)
	m[start + 1] = u8(total >> 8)
	m[start + 2] = u8(total >> 16)
	m[start + 3] = u8(total >> 24)
}

fn put_attr_bytes(mut m []u8, kind u16, data &u8, len int) {
	put_u16(mut m, u16(4 + len))
	put_u16(mut m, kind)
	for i in 0 .. len {
		m << unsafe { data[i] }
	}
	align4(mut m)
}

fn put_attr_u32(mut m []u8, kind u16, value u32) {
	put_u16(mut m, 8)
	put_u16(mut m, kind)
	put_u32(mut m, value)
}

fn put_attr_u8(mut m []u8, kind u16, value u8) {
	put_u16(mut m, 5)
	put_u16(mut m, kind)
	m << value
	align4(mut m)
}

fn put_attr_string(mut m []u8, kind u16, text string) {
	put_u16(mut m, u16(4 + text.len + 1))
	put_u16(mut m, kind)
	for i in 0 .. text.len {
		m << text[i]
	}
	m << u8(0)
	align4(mut m)
}

fn put_link(mut m []u8, iface inet.Interface, seq u32, pid u32, multi bool) {
	start := start_message(mut m, rtm_newlink, if multi { nlm_f_multi } else { u16(0) }, seq,
		pid)
	// ifinfomsg.
	m << u8(0) // ifi_family = AF_UNSPEC
	m << u8(0)
	put_u16(mut m, iface.kind)
	put_u32(mut m, iface.index)
	put_u32(mut m, iface.flags)
	put_u32(mut m, 0) // ifi_change
	put_attr_string(mut m, ifla_ifname, iface.name)
	put_attr_u32(mut m, ifla_mtu, iface.mtu)
	put_attr_u32(mut m, ifla_txqlen, iface.txqlen)
	put_attr_u8(mut m, ifla_operstate, if iface.kind == inet.arphrd_ether {
		if_oper_up
	} else {
		if_oper_unknown
	})
	mut broadcast := [6]u8{}
	if iface.kind == inet.arphrd_ether {
		for i in 0 .. 6 {
			broadcast[i] = 0xff
		}
	}
	put_attr_bytes(mut m, ifla_address, &iface.mac[0], 6)
	put_attr_bytes(mut m, ifla_broadcast, &broadcast[0], 6)
	finish_message(mut m, start)
}

fn put_address(mut m []u8, iface inet.Interface, seq u32, pid u32) {
	start := start_message(mut m, rtm_newaddr, nlm_f_multi, seq, pid)
	loopback := iface.kind == inet.arphrd_loopback
	// ifaddrmsg.
	m << af_inet
	m << inet.prefix_length(iface.netmask)
	m << if loopback { ifa_f_permanent } else { u8(0) }
	m << if loopback { rt_scope_host } else { rt_scope_universe }
	put_u32(mut m, iface.index)
	put_attr_u32(mut m, ifa_address, iface.address)
	put_attr_u32(mut m, ifa_local, iface.address)
	if !loopback {
		put_attr_u32(mut m, ifa_broadcast, iface.address | ~iface.netmask)
	}
	put_attr_string(mut m, ifa_label, iface.name)
	finish_message(mut m, start)
}

fn put_route(mut m []u8, iface inet.Interface, seq u32, pid u32, default_route bool) {
	start := start_message(mut m, rtm_newroute, nlm_f_multi, seq, pid)
	// rtmsg.
	m << af_inet
	m << if default_route { u8(0) } else { inet.prefix_length(iface.netmask) }
	m << u8(0) // rtm_src_len
	m << u8(0) // rtm_tos
	m << rt_table_main
	m << if default_route { rtprot_dhcp } else { rtprot_kernel }
	m << if default_route { rt_scope_universe } else { rt_scope_link }
	m << rtn_unicast
	put_u32(mut m, 0) // rtm_flags
	put_attr_u32(mut m, rta_table, u32(rt_table_main))
	if default_route {
		put_attr_u32(mut m, rta_gateway, iface.gateway)
	} else {
		put_attr_u32(mut m, rta_dst, iface.address & iface.netmask)
		put_attr_u32(mut m, rta_prefsrc, iface.address)
	}
	put_attr_u32(mut m, rta_oif, iface.index)
	finish_message(mut m, start)
}

// The interface a non-dump RTM_GETLINK names by index or IFLA_IFNAME. One
// that names neither gets lo, which is all such a request has ever wanted here.
fn requested_link(list []inet.Interface, request voidptr, length u64) ?inet.Interface {
	if length < 32 {
		return list[0]
	}
	index := read_u32(request, 20)
	mut off := u64(32)
	for off + 4 <= length {
		attr_len := u64(read_u16(request, off))
		if attr_len < 4 || off + attr_len > length {
			break
		}
		if read_u16(request, off + 2) == ifla_ifname {
			name := unsafe { tos_clone(&u8(u64(request) + off + 4)) }
			defer {
				unsafe { name.free() }
			}
			for iface in list {
				if iface.name == name {
					return iface
				}
			}
			return none
		}
		off += (attr_len + 3) & ~u64(3)
	}
	if index == 0 {
		return list[0]
	}
	for iface in list {
		if iface.index == index {
			return iface
		}
	}
	return none
}

// An NLMSG_ERROR carrying `code` (0 is a plain ACK), echoing the request header.
fn put_ack(mut m []u8, seq u32, pid u32, code i32, request voidptr, request_len u64) {
	start := start_message(mut m, nlmsg_error, 0, seq, pid)
	put_u32(mut m, u32(code)) // errno (negative on real errors; 0 = ACK)
	// The original request header (first 16 bytes) follows.
	copy_len := if request_len < 16 { request_len } else { u64(16) }
	rp := unsafe { &u8(request) }
	for i := u64(0); i < copy_len; i++ {
		m << unsafe { rp[i] }
	}
	for m.len - start < 36 {
		m << u8(0)
	}
	finish_message(mut m, start)
}

fn put_done(mut m []u8, seq u32, pid u32) {
	start := start_message(mut m, nlmsg_done, nlm_f_multi, seq, pid)
	put_u32(mut m, 0) // NLMSG_DONE payload: error = 0
	finish_message(mut m, start)
}

// Turn one request datagram into its reply datagram and queue it.
fn (mut this NetlinkSocket) handle_request(buf voidptr, count u64) {
	mut reply := []u8{cap: 1024}
	mut off := u64(0)
	for off + 16 <= count {
		msg_len := read_u32(buf, off)
		if msg_len < 16 {
			break
		}
		if u64(msg_len) > count - off {
			break
		}
		msg_type := read_u16(buf, off + 4)
		msg_flags := read_u16(buf, off + 6)
		seq := read_u32(buf, off + 8)
		pid := read_u32(buf, off + 12)
		req := voidptr(u64(buf) + off)

		is_dump := (msg_flags & nlm_f_dump) == nlm_f_dump
		// RTM_GET* types are the ones that are 2 mod 4.
		is_get := msg_type >= rtm_newlink && msg_type & 3 == 2
		if msg_type == rtm_getlink && is_dump {
			list := inet.interfaces()
			for iface in list {
				put_link(mut reply, iface, seq, pid, true)
			}
			unsafe { list.free() }
			put_done(mut reply, seq, pid)
		} else if msg_type == rtm_getlink {
			list := inet.interfaces()
			if iface := requested_link(list, req, u64(msg_len)) {
				put_link(mut reply, iface, seq, pid, false)
			} else {
				put_ack(mut reply, seq, pid, -enodev, req, u64(msg_len))
			}
			unsafe { list.free() }
		} else if msg_type == rtm_getaddr && is_dump {
			list := inet.interfaces()
			for iface in list {
				if iface.address != 0 {
					put_address(mut reply, iface, seq, pid)
				}
			}
			unsafe { list.free() }
			put_done(mut reply, seq, pid)
		} else if msg_type == rtm_getroute && is_dump {
			list := inet.interfaces()
			for iface in list {
				if iface.kind != inet.arphrd_ether || iface.address == 0 {
					continue
				}
				if iface.gateway != 0 {
					put_route(mut reply, iface, seq, pid, true)
				}
				put_route(mut reply, iface, seq, pid, false)
			}
			unsafe { list.free() }
			put_done(mut reply, seq, pid)
		} else if is_get && is_dump {
			// Neighbours, rules, qdiscs and the rest: there are none to list.
			put_done(mut reply, seq, pid)
		} else if is_get {
			// A lookup that is not answered would leave its caller waiting.
			put_ack(mut reply, seq, pid, -eopnotsupp, req, u64(msg_len))
		} else {
			// RTM_NEWLINK/RTM_SETLINK/RTM_NEWADDR and the rest: acknowledge when
			// asked, which is what LinkSetUp waits for.
			if (msg_flags & nlm_f_ack) != 0 {
				put_ack(mut reply, seq, pid, 0, req, u64(msg_len))
			}
		}
		off += u64((msg_len + 3) & u32(0xfffffffc))
	}
	if reply.len == 0 {
		unsafe { reply.free() }
		return
	}
	this.rx << reply
	this.status |= file.pollin
	event.trigger(mut this.event, false)
}

// ── resource methods ─────────────────────────────────────────────────────────

fn (mut this NetlinkSocket) write(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	this.handle_request(buf, count)
	return i64(count)
}

fn (mut this NetlinkSocket) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}
	handle := unsafe { &file.Handle(_handle) }
	for this.rx.len == 0 {
		if _handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0 {
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
	mut datagram := this.rx[0]
	this.rx.delete(0)
	if this.rx.len == 0 {
		this.status &= ~file.pollin
	}
	mut n := u64(datagram.len)
	if n > count {
		n = count
	}
	unsafe { C.memcpy(buf, datagram.data, n) }
	unsafe { datagram.free() }
	return i64(n)
}

pub fn (mut this NetlinkSocket) bind(_handle voidptr, _addr voidptr, addrlen u32) ? {
	if addrlen >= u32(sizeof(SockaddrNl)) {
		addr := unsafe { &SockaddrNl(_addr) }
		this.nl_pid = addr.nl_pid
		this.groups = addr.nl_groups
	}
	this.bound = true
}

pub fn (mut this NetlinkSocket) sockname(_handle voidptr, _addr voidptr, addrlen &u32) ? {
	mut out := SockaddrNl{
		nl_family: u16(sock_pub.af_netlink)
		nl_pid:    this.nl_pid
		nl_groups: this.groups
	}
	mut want := unsafe { *addrlen }
	if want > u32(sizeof(SockaddrNl)) {
		want = u32(sizeof(SockaddrNl))
	}
	unsafe { C.memcpy(_addr, voidptr(&out), want) }
	unsafe {
		*addrlen = u32(sizeof(SockaddrNl))
	}
}

pub fn (mut this NetlinkSocket) recvmsg(_handle voidptr, msg &sock_pub.MsgHdr, flags int) ?u64 {
	mut count := u64(0)
	for i := u64(0); i < msg.msg_iovlen; i++ {
		count += unsafe { msg.msg_iov[i].iov_len }
	}

	this.l.acquire()
	handle := unsafe { &file.Handle(_handle) }
	for this.rx.len == 0 {
		if _handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0 {
			this.l.release()
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
	mut datagram := this.rx[0]
	this.rx.delete(0)
	if this.rx.len == 0 {
		this.status &= ~file.pollin
	}
	this.l.release()

	// Scatter the datagram across the caller's iovecs.
	mut transferred := u64(0)
	mut left := u64(datagram.len)
	for i := u64(0); i < msg.msg_iovlen; i++ {
		if left == 0 {
			break
		}
		iov := unsafe { &msg.msg_iov[i] }
		n := if iov.iov_len < left { iov.iov_len } else { left }
		unsafe { C.memcpy(iov.iov_base, voidptr(u64(datagram.data) + transferred), n) }
		transferred += n
		left -= n
	}
	unsafe {
		msg.msg_controllen = 0
		msg.msg_flags = if left > 0 { 0x20 } else { 0 } // MSG_TRUNC
	}
	// Every reply comes from the kernel, port 0. iproute2 and busybox ip skip
	// any message whose sender has another port, so leaving the caller's
	// uninitialised address there made `ip addr` wait for a reply for ever.
	if msg.msg_name != unsafe { nil } {
		write_kernel_source(msg.msg_name, unsafe { &msg.msg_namelen })
	}
	unsafe { datagram.free() }
	return transferred
}

pub fn (mut this NetlinkSocket) connect(_handle voidptr, _addr voidptr, addrlen u32) ? {
	// Netlink "connects" to the kernel; nothing to establish.
}

pub fn (mut this NetlinkSocket) peername(_handle voidptr, _addr voidptr, addrlen &u32) ? {
	mut out := SockaddrNl{
		nl_family: u16(sock_pub.af_netlink)
	}
	mut want := unsafe { *addrlen }
	if want > u32(sizeof(SockaddrNl)) {
		want = u32(sizeof(SockaddrNl))
	}
	unsafe { C.memcpy(_addr, voidptr(&out), want) }
	unsafe {
		*addrlen = u32(sizeof(SockaddrNl))
	}
}

pub fn (mut this NetlinkSocket) shutdown(_handle voidptr, how int) ? {}

pub fn (mut this NetlinkSocket) listen(_handle voidptr, backlog int) ? {
	errno.set(errno.eopnotsupp)
	return none
}

pub fn (mut this NetlinkSocket) accept(_handle voidptr) ?&resource.Resource {
	errno.set(errno.eopnotsupp)
	return none
}

pub fn (mut this NetlinkSocket) getsockopt(_handle voidptr, level int, optname int) ?int {
	// Buffer sizes and the like are reported back as a plausible value; nothing
	// here acts on them.
	return 0
}

pub fn (mut this NetlinkSocket) setsockopt(_handle voidptr, level int, optname int, value int) ? {
	// Accept SO_SNDBUF/SO_RCVBUF, NETLINK_EXT_ACK and friends without acting.
}

// Write the address a received datagram came from: the kernel, pid 0. runc's
// netlink library asserts the source of every reply is a netlink sockaddr.
pub fn write_kernel_source(addr voidptr, addrlen &u32) {
	if addr == unsafe { nil } || addrlen == unsafe { nil } {
		return
	}
	mut out := SockaddrNl{
		nl_family: u16(sock_pub.af_netlink)
	}
	mut want := unsafe { *addrlen }
	if want > u32(sizeof(SockaddrNl)) {
		want = u32(sizeof(SockaddrNl))
	}
	unsafe { C.memcpy(addr, voidptr(&out), want) }
	unsafe {
		*addrlen = u32(sizeof(SockaddrNl))
	}
}

fn (mut this NetlinkSocket) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	if inet.is_interface_ioctl(request) {
		return inet.interface_ioctl(request, argp)
	}
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this NetlinkSocket) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	// The last descriptor is gone, and with it anything that could still be
	// waiting for a reply. runc opens one of these for every container.
	for i in 0 .. this.rx.len {
		unsafe { this.rx[i].free() }
	}
	unsafe {
		this.rx.free()
		free(this)
	}
}

fn (mut this NetlinkSocket) grow(_handle voidptr, _new_size u64) ? {}

fn (mut this NetlinkSocket) link(_handle voidptr) ? {}

fn (mut this NetlinkSocket) unlink(_handle voidptr) ? {}

fn (mut this NetlinkSocket) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}
