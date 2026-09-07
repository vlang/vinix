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
	sockname(handle voidptr, _addr voidptr, addrlen &u32) ?
	shutdown(handle voidptr, how int) ?
	listen(handle voidptr, backlog int) ?
	accept(handle voidptr) ?&Resource
	recvmsg(handle voidptr, msg &MsgHdr, flags int) ?u64
	getsockopt(handle voidptr, level int, optname int) ?int
	setsockopt(handle voidptr, level int, optname int, value int) ?
}

// shutdown(2).
pub const shut_rd = 0

pub const shut_wr = 1

pub const shut_rdwr = 2

// Socket types, as they appear in the low bits of socket(2)'s type argument.
pub const sock_type_mask = 0xf

pub const sock_stream = 1

pub const sock_dgram = 2

pub const sock_seqpacket = 5

// getsockopt(2)/setsockopt(2).
pub const sol_socket = 1

pub const scm_rights = 1

pub const so_reuseaddr = 2

pub const so_type = 3

pub const so_error = 4

pub const so_broadcast = 6

pub const so_sndbuf = 7

pub const so_rcvbuf = 8

pub const so_keepalive = 9

pub const so_oobinline = 10

pub const so_linger = 13

pub const so_reuseport = 15

pub const so_acceptconn = 30

pub const so_domain = 39

pub const so_protocol = 38

// Copy an address out the way getsockname(2) and getpeername(2) ask for it:
// write no more than the caller's buffer holds, but report the length the
// address actually needs, so a short buffer is reported as truncated rather
// than being overrun.
pub fn copy_out_sockaddr(dest voidptr, addrlen &u32, source voidptr, full_size u32) {
	if addrlen == unsafe { nil } {
		return
	}

	capacity := unsafe { *addrlen }
	if dest != unsafe { nil } && capacity > 0 {
		mut to_copy := full_size
		if to_copy > capacity {
			to_copy = capacity
		}
		unsafe { C.memcpy(dest, source, to_copy) }
	}

	unsafe {
		*addrlen = full_size
	}
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
