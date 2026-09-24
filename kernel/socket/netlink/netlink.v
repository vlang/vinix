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
import socket.public as sock_pub

// A very small NETLINK_ROUTE (rtnetlink) socket. It exists for one caller:
// a container runtime bringing the loopback interface up inside a fresh network
// namespace. runc does LinkByName("lo") followed by LinkSetUp("lo"), which is a
// RTM_GETLINK and a RTM_NEWLINK over this socket, so those two are answered for
// real and every other request is acknowledged. There is no general routing
// control here, only enough for a container to start.

// nlmsghdr types.
const nlmsg_noop = u16(1)
const nlmsg_error = u16(2)
const nlmsg_done = u16(3)
const rtm_newlink = u16(16)
const rtm_getlink = u16(18)
const rtm_setlink = u16(19)
const rtm_newaddr = u16(20)
const rtm_getaddr = u16(22)

// nlmsghdr flags.
const nlm_f_request = u16(1)
const nlm_f_multi = u16(2)
const nlm_f_ack = u16(4)
const nlm_f_dump = u16(0x300) // NLM_F_ROOT | NLM_F_MATCH

// Interface facts for lo.
const arphrd_loopback = u16(772)
const iff_up_running_loopback = u32(73) // IFF_UP | IFF_LOOPBACK | IFF_RUNNING
const ifla_ifname = u16(3)

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

pub fn create(@type int, protocol int) ?&NetlinkSocket {
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

// One RTM_NEWLINK record describing lo. `multi` marks it as part of a dump.
fn build_newlink(seq u32, pid u32, multi bool) []u8 {
	mut m := []u8{}
	mut flags := u16(0)
	if multi {
		flags |= nlm_f_multi
	}
	// nlmsghdr (length filled in at the end).
	put_u32(mut m, 0)
	put_u16(mut m, rtm_newlink)
	put_u16(mut m, flags)
	put_u32(mut m, seq)
	put_u32(mut m, pid)
	// ifinfomsg.
	m << u8(0) // ifi_family = AF_UNSPEC
	m << u8(0) // pad
	put_u16(mut m, arphrd_loopback) // ifi_type
	put_u32(mut m, 1) // ifi_index (lo is 1)
	put_u32(mut m, iff_up_running_loopback) // ifi_flags
	put_u32(mut m, 0) // ifi_change
	// IFLA_IFNAME = "lo\0".
	put_u16(mut m, u16(4 + 3)) // rta_len: header + "lo\0"
	put_u16(mut m, ifla_ifname) // rta_type
	m << u8(`l`)
	m << u8(`o`)
	m << u8(0)
	align4(mut m)
	// Backpatch nlmsg_len.
	total := u32(m.len)
	m[0] = u8(total)
	m[1] = u8(total >> 8)
	m[2] = u8(total >> 16)
	m[3] = u8(total >> 24)
	return m
}

// An NLMSG_ERROR carrying `code` (0 is a plain ACK), echoing the request header.
fn build_ack(seq u32, pid u32, code i32, request voidptr, request_len u64) []u8 {
	mut m := []u8{}
	put_u32(mut m, 0) // length, filled below
	put_u16(mut m, nlmsg_error)
	put_u16(mut m, 0)
	put_u32(mut m, seq)
	put_u32(mut m, pid)
	put_u32(mut m, u32(code)) // errno (negative on real errors; 0 = ACK)
	// The original request header (first 16 bytes) follows.
	copy_len := if request_len < 16 { request_len } else { u64(16) }
	rp := unsafe { &u8(request) }
	for i := u64(0); i < copy_len; i++ {
		m << unsafe { rp[i] }
	}
	for m.len < 36 {
		m << u8(0)
	}
	total := u32(m.len)
	m[0] = u8(total)
	m[1] = u8(total >> 8)
	m[2] = u8(total >> 16)
	m[3] = u8(total >> 24)
	return m
}

fn build_done(seq u32, pid u32) []u8 {
	mut m := []u8{}
	put_u32(mut m, 20)
	put_u16(mut m, nlmsg_done)
	put_u16(mut m, nlm_f_multi)
	put_u32(mut m, seq)
	put_u32(mut m, pid)
	put_u32(mut m, 0) // NLMSG_DONE payload: error = 0
	return m
}

// Turn one request datagram into its reply datagram and queue it.
fn (mut this NetlinkSocket) handle_request(buf voidptr, count u64) {
	mut reply := []u8{}
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

		if msg_type == rtm_getlink {
			is_dump := (msg_flags & nlm_f_dump) == nlm_f_dump
			reply << build_newlink(seq, pid, is_dump)
			if is_dump {
				reply << build_done(seq, pid)
			}
		} else if msg_type == rtm_getaddr {
			// No addresses to report; a dump that finds nothing is just DONE.
			reply << build_done(seq, pid)
		} else {
			// RTM_NEWLINK/RTM_SETLINK/RTM_NEWADDR and the rest: acknowledge when
			// asked, which is what LinkSetUp waits for.
			if (msg_flags & nlm_f_ack) != 0 {
				reply << build_ack(seq, pid, 0, req, u64(msg_len))
			}
		}
		off += u64((msg_len + 3) & u32(0xfffffffc))
	}
	if reply.len != 0 {
		this.rx << reply
		this.status |= file.pollin
		event.trigger(mut this.event, false)
	}
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
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this NetlinkSocket) unref(_handle voidptr) ? {
	this.l.acquire()
	defer {
		this.l.release()
	}
	this.refcount--
}

fn (mut this NetlinkSocket) grow(_handle voidptr, _new_size u64) ? {}

fn (mut this NetlinkSocket) link(_handle voidptr) ? {}

fn (mut this NetlinkSocket) unlink(_handle voidptr) ? {}

fn (mut this NetlinkSocket) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}
