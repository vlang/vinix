// public.v: Constants for socket-related syscalls.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module public

import resource { Resource }

pub const (
	af_inet = 2
	af_inet6 = 10
	af_unix = 1
	af_local = 1
	af_unspec = 0
	af_netlink = 16

	sock_nonblock = 0o4000
	sock_cloexec = 0o2000000
)

pub interface Socket {
	Resource

mut:
	bind(handle voidptr, _addr voidptr, addrlen u64) ?
	connect(handle voidptr, _addr voidptr, addrlen u64) ?
	peername(handle voidptr, _addr voidptr, addrlen &u64) ?
	listen(handle voidptr, backlog int) ?
	accept(handle voidptr) ?&Resource
	recvmsg(handle voidptr, msg &MsgHdr, flags int) ?u64
}

pub struct IoVec {
pub mut:
	iov_base voidptr
	iov_len u64
}

pub struct MsgHdr {
pub mut:
	msg_name voidptr
	msg_namelen u32
	msg_iov &IoVec
	msg_iovlen u64
	msg_control voidptr
	msg_controllen u64
	msg_flags int
}
