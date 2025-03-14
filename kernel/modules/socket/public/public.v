module public

import resource { Resource }

pub const af_inet = 2
pub const af_inet6 = 10
pub const af_unix = 1
pub const af_local = 1
pub const af_unspec = 0
pub const af_netlink = 16

pub const sock_nonblock = 0o4000
pub const sock_cloexec = 0o2000000

pub interface Socket {
	Resource
mut:
	bind(handle voidptr, _addr voidptr, addrlen u32) ?
	connect(handle voidptr, _addr voidptr, addrlen u32) ?
	peername(handle voidptr, _addr voidptr, addrlen &u32) ?
	listen(handle voidptr, backlog int) ?
	accept(handle voidptr) ?&Resource
	recvmsg(handle voidptr, msg &MsgHdr, flags int) ?u64
}

pub struct IoVec {
pub mut:
	iov_base voidptr
	iov_len  u64
}

pub struct MsgHdr {
pub mut:
	msg_name       voidptr
	msg_namelen    u32
	msg_iov        &IoVec
	msg_iovlen     u64
	msg_control    voidptr
	msg_controllen u64
	msg_flags      int
}
