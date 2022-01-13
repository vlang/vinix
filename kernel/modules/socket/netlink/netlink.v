// netlink.v: Communication between sockets and kernel (mostly a stub).
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module netlink

import stat
import klock
import event.eventstruct
import errno
import socket.public as sock_pub

pub const netlink_route = 0

pub const netlink_usersock = 2

pub const netlink_firewall = 3

pub const netlink_ip6_fw = 13

pub const netlink_kobject_uevent = 15

struct SockaddrNL {
	nl_family u32
	nl_pad    u16
	nl_pid    u32
	nl_groups u32
}

struct NetlinkSocket {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event

	name      SockaddrNL
	listening bool
	backlog   []&NetlinkSocket
}

fn (mut this NetlinkSocket) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this NetlinkSocket) read(_handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	return error('')
}

fn (mut this NetlinkSocket) write(handle voidptr, buf voidptr, loc u64, _count u64) ?i64 {
	return error('')
}

fn (mut this NetlinkSocket) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return error('')
}

fn (mut this NetlinkSocket) unref(handle voidptr) ? {
	return error('')
}

fn (mut this NetlinkSocket) grow(handle voidptr, new_size u64) ? {
	return error('')
}

fn (mut this NetlinkSocket) bind(handle voidptr, _addr voidptr, addrlen u64) ? {
	addr := &SockaddrNL(_addr)

	if addr.nl_family != sock_pub.af_netlink {
		errno.set(errno.einval)
		return error('')
	}

	this.name = *addr
}

fn (mut this NetlinkSocket) listen(handle voidptr, backlog int) ? {
	this.backlog = []&NetlinkSocket{cap: backlog}
	this.listening = true
}

pub fn create(@type int, protocol int) ?&NetlinkSocket {
	return &NetlinkSocket{
		refcount: 1
	}
}
