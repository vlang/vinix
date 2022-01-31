// public.v: Constants for socket-related syscalls.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module public

import resource { Resource }

pub const (
	af_inet = 1
	af_inet6 = 2
	af_unix = 3
	af_local = 3
	af_unspec = 4
	af_netlink = 5

	sock_nonblock = 0x10000
	sock_cloexec = 0x20000
)

pub interface Socket {
	Resource

mut:
	bind(handle voidptr, _addr voidptr, addrlen u64) ?
	connect(handle voidptr, _addr voidptr, addrlen u64) ?
	peername(handle voidptr, _addr voidptr, addrlen &u64) ?
	listen(handle voidptr, backlog int) ?
	accept(handle voidptr) ?&Resource
}
