// SPDX-License-Identifier: GPL-2.0-or-later
// Real Linux-ABI syscalls, intended to run on the Vinix guest kernel.
module main

#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

struct C.iovec {
mut:
	iov_base voidptr
	iov_len  usize
}

struct C.msghdr {
mut:
	msg_name       voidptr
	msg_namelen    u32
	msg_iov        &C.iovec = unsafe { nil }
	msg_iovlen     usize
	msg_control    voidptr
	msg_controllen usize
	msg_flags      i32
}

struct C.cmsghdr {
mut:
	cmsg_len   usize
	cmsg_level i32
	cmsg_type  i32
}

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.recvmsg(i32, &C.msghdr, i32) isize
fn C.sendmsg(i32, &C.msghdr, i32) isize
fn C.send(i32, voidptr, usize, i32) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.CMSG_FIRSTHDR(&C.msghdr) &C.cmsghdr
fn C.CMSG_DATA(&C.cmsghdr) voidptr
fn C.CMSG_LEN(usize) usize
fn C.CMSG_SPACE(usize) usize
fn C.memcpy(voidptr, voidptr, usize) voidptr

fn require(ok bool, label string) ! {
	if !ok { return error(label + ' errno=${C.errno}') }
}

fn receive_flags(kind i32) ! {
	unsafe {
		mut pair := [i32(-1), i32(-1)]!
		require(C.socketpair(C.AF_UNIX, kind, 0, &pair[0]) == 0, 'socketpair')!
		defer {
			C.close(pair[0])
			C.close(pair[1])
		}
		mut byte := u8(0)
		mut iov := C.iovec{ iov_base: &byte, iov_len: 1 }
		mut message := C.msghdr{ msg_iov: &iov, msg_iovlen: 1 }
		require(C.recvmsg(pair[1], &message, C.MSG_NOSIGNAL | C.MSG_DONTWAIT) == -1
			&& C.errno == C.EAGAIN, 'empty MSG_NOSIGNAL | MSG_DONTWAIT')!
		require((C.fcntl(pair[1], C.F_GETFL) & C.O_NONBLOCK) == 0,
			'per-call flags changed descriptor status')!
		require(C.send(pair[0], c'a', 1, C.MSG_NOSIGNAL) == 1, 'send payload')!
		// MSG_ERRQUEUE remains outside the supported Unix receive flags. A
		// rejected call must leave the queued payload available to the next read.
		require(C.recvmsg(pair[1], &message, C.MSG_NOSIGNAL | 0x2000) == -1
			&& C.errno == C.EOPNOTSUPP, 'unsupported receive flag accepted')!
		require(C.recvmsg(pair[1], &message, C.MSG_NOSIGNAL) == 1 && byte == `a`
			&& message.msg_flags == 0 && message.msg_controllen == 0,
			'MSG_NOSIGNAL queued receive')!
		require(C.recvmsg(pair[1], &message,
			C.MSG_NOSIGNAL | C.MSG_CMSG_CLOEXEC | C.MSG_DONTWAIT) == -1
			&& C.errno == C.EAGAIN, 'combined empty receive')!
		if kind == C.SOCK_SEQPACKET {
			require(C.send(pair[0], c'bc', 2, 0) == 2 && C.send(pair[0], c'd', 1, 0) == 1,
				'send separate records')!
			require(C.recvmsg(pair[1], &message, C.MSG_NOSIGNAL) == 1 && byte == `b`
				&& (message.msg_flags & C.MSG_TRUNC) != 0, 'truncated first record')!
			message.msg_flags = 0
			require(C.recvmsg(pair[1], &message, C.MSG_NOSIGNAL) == 1 && byte == `d`
				&& message.msg_flags == 0, 'next record boundary')!
		}
	}
}

fn receive_rights(kind i32, cloexec bool) ! {
	unsafe {
		mut pair := [i32(-1), i32(-1)]!
		mut pipe := [i32(-1), i32(-1)]!
		require(C.socketpair(C.AF_UNIX, kind, 0, &pair[0]) == 0, 'rights socketpair')!
		defer {
			C.close(pair[0])
			C.close(pair[1])
		}
		require(C.pipe(&pipe[0]) == 0, 'rights pipe')!
		defer {
			if pipe[0] >= 0 { C.close(pipe[0]) }
			C.close(pipe[1])
		}
		require(C.write(pipe[1], c'z', 1) == 1, 'rights pipe payload')!
		mut out_control := [4]u64{}
		mut in_control := [4]u64{}
		mut out_byte := u8(`r`)
		mut in_byte := u8(0)
		mut out_iov := C.iovec{ iov_base: &out_byte, iov_len: 1 }
		mut in_iov := C.iovec{ iov_base: &in_byte, iov_len: 1 }
		mut out := C.msghdr{
			msg_iov:        &out_iov
			msg_iovlen:     1
			msg_control:    &out_control[0]
			msg_controllen: C.CMSG_SPACE(sizeof(i32))
		}
		control := C.CMSG_FIRSTHDR(&out)
		require(control != nil, 'outgoing control header')!
		control.cmsg_len = C.CMSG_LEN(sizeof(i32))
		control.cmsg_level = C.SOL_SOCKET
		control.cmsg_type = C.SCM_RIGHTS
		C.memcpy(C.CMSG_DATA(control), &pipe[0], sizeof(i32))
		require(C.sendmsg(pair[0], &out, C.MSG_NOSIGNAL) == 1, 'send rights')!
		require(C.close(pipe[0]) == 0, 'close sender descriptor')!
		pipe[0] = -1
		mut input := C.msghdr{
			msg_iov:        &in_iov
			msg_iovlen:     1
			msg_control:    &in_control[0]
			msg_controllen: sizeof(in_control)
		}
		flags := C.MSG_NOSIGNAL | C.MSG_DONTWAIT | if cloexec { C.MSG_CMSG_CLOEXEC } else { 0 }
		require(C.recvmsg(pair[1], &input, flags) == 1 && in_byte == `r`
			&& input.msg_flags == 0 && input.msg_controllen == C.CMSG_SPACE(sizeof(i32)),
			'receive rights with MSG_NOSIGNAL')!
		received_control := C.CMSG_FIRSTHDR(&input)
		require(received_control != nil && received_control.cmsg_level == C.SOL_SOCKET
			&& received_control.cmsg_type == C.SCM_RIGHTS
			&& received_control.cmsg_len == C.CMSG_LEN(sizeof(i32)), 'received control header')!
		mut received_fd := i32(-1)
		C.memcpy(&received_fd, C.CMSG_DATA(received_control), sizeof(i32))
		require(received_fd >= 0, 'received descriptor')!
		defer { C.close(received_fd) }
		descriptor_flags := C.fcntl(received_fd, C.F_GETFD)
		require(descriptor_flags >= 0 && ((descriptor_flags & C.FD_CLOEXEC) != 0) == cloexec,
			'MSG_CMSG_CLOEXEC effect')!
		mut payload := u8(0)
		require(C.read(received_fd, &payload, 1) == 1 && payload == `z`,
			'rights contents after sender close')!
	}
}

fn main() {
	require(C.MSG_NOSIGNAL == 0x4000 && C.MSG_CMSG_CLOEXEC == 0x40000000,
		'Linux ABI flag constants') or {
		eprintln('UNIX-RECVMSG-FLAGS-FAIL ${err}')
		exit(1)
	}
	for kind in [i32(C.SOCK_STREAM), i32(C.SOCK_SEQPACKET), i32(C.SOCK_DGRAM)] {
		receive_flags(kind) or {
			eprintln('UNIX-RECVMSG-FLAGS-FAIL type=${kind} ${err}')
			exit(1)
		}
		for cloexec in [false, true] {
			receive_rights(kind, cloexec) or {
				eprintln('UNIX-RECVMSG-FLAGS-FAIL type=${kind} cloexec=${cloexec} ${err}')
				exit(1)
			}
		}
		println('UNIX-RECVMSG-FLAGS-PASS type=${kind} payload=true rights=true cloexec=true dontwait=true unsupported_rejected=true')
	}
	println('UNIX-RECVMSG-FLAGS-PASS all=3')
}
