// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

struct C.iovec {
	iov_base voidptr
	iov_len usize
}

struct C.msghdr {
	msg_name voidptr
	msg_namelen u32
	msg_iov &C.iovec
	msg_iovlen usize
	msg_control voidptr
	msg_controllen usize
	msg_flags i32
}

struct C.cmsghdr {
	cmsg_len usize
	cmsg_level i32
	cmsg_type i32
}

struct C.mmsghdr {
	msg_hdr C.msghdr
	msg_len u32
}

fn C.socketpair(int, int, int, &i32) int
fn C.accept4(int, &C.sockaddr, &u32, int) int
fn C.sendmmsg(int, &C.mmsghdr, u32, u32) int
fn C.recvmmsg(int, &C.mmsghdr, u32, u32, &C.timespec) int
fn C.shutdown(int, int) int
fn C.getsockname(int, &C.sockaddr, &u32) int
fn C.getpeername(int, &C.sockaddr, &u32) int
fn C.getsockopt(int, int, int, voidptr, &u32) int
fn C.vinix_overlay_setsockopt(int, int, int, voidptr, u32) int
fn C.recvfrom(int, voidptr, usize, int, &C.sockaddr, &u32) isize
fn C.vinix_overlay_sendto(int, voidptr, usize, int, voidptr, u32) isize
fn C.recvmsg(int, &C.msghdr, int) isize
fn C.vinix_overlay_sendmsg(int, voidptr, int) isize
fn C.CMSG_SPACE(usize) usize
fn C.CMSG_LEN(usize) usize
fn C.CMSG_DATA(&C.cmsghdr) voidptr
fn C.memset(voidptr, int, usize) voidptr
fn C.fcntl(int, int, ...) int

fn bad_socket_operation(result isize, site int) {
	unsafe {
		code := *C.__errno_location()
		if result != -1 || code != C.EBADF {
			C.printf(c'OVERLAY SOCKET ACCESS: site=%d result=%ld errno=%d\n', site, result, code)
			C.fflush(nil)
		}
		check(result == -1 && code == C.EBADF, site)
	}
}

// Valid buffers exercise every socket lookup path. Rejection must preserve
// options, output storage and queued data, including ancillary descriptors.
fn socket_metadata_operations(fd int, target &C.sockaddr_un) {
	unsafe {
		bad_socket_operation(C.listen(fd, 1), 440)
		bad_socket_operation(C.bind(fd, voidptr(target), u32(sizeof(C.sockaddr_un))), 441)
		bad_socket_operation(C.vinix_overlay_connect(fd, voidptr(target), u32(sizeof(C.sockaddr_un))), 442)
		bad_socket_operation(C.shutdown(fd, C.SHUT_RDWR), 443)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		C.memset(address, 0x5a, sizeof(C.sockaddr_un))
		length := &u32(C.alloca(sizeof(u32)))
		*length = u32(sizeof(C.sockaddr_un))
		bad_socket_operation(C.getsockname(fd, &C.sockaddr(address), length), 444)
		check(*length == sizeof(C.sockaddr_un) && address.sun_family == 0x5a5a, 445)
		bad_socket_operation(C.getpeername(fd, &C.sockaddr(address), length), 446)
		check(*length == sizeof(C.sockaddr_un) && address.sun_family == 0x5a5a, 447)
		value := &i32(C.alloca(sizeof(i32)))
		*value = 0x5a5a
		*length = u32(sizeof(i32))
		bad_socket_operation(C.getsockopt(fd, C.SOL_SOCKET, C.SO_TYPE, value, length), 448)
		check(*length == sizeof(i32) && *value == 0x5a5a, 449)
		*value = 1
		bad_socket_operation(C.vinix_overlay_setsockopt(fd, C.SOL_SOCKET, C.SO_KEEPALIVE, value, u32(sizeof(i32))), 450)
		byte := &char(C.alloca(1))
		*byte = char(`Q`)
		bad_socket_operation(C.vinix_overlay_sendto(fd, byte, 1, C.MSG_DONTWAIT | C.MSG_NOSIGNAL, nil, 0), 451)
		bad_socket_operation(C.recvfrom(fd, byte, 1, C.MSG_DONTWAIT, nil, nil), 452)
		check(*byte == char(`Q`), 453)
		mut vector := &C.iovec(C.alloca(sizeof(C.iovec)))
		*vector = C.iovec{ iov_base: byte, iov_len: 1 }
		control := C.alloca(C.CMSG_SPACE(sizeof(i32)))
		C.memset(control, 0, C.CMSG_SPACE(sizeof(i32)))
		mut cmsg := &C.cmsghdr(control)
		*cmsg = C.cmsghdr{ cmsg_len: C.CMSG_LEN(sizeof(i32)), cmsg_level: C.SOL_SOCKET, cmsg_type: C.SCM_RIGHTS }
		*&i32(C.CMSG_DATA(cmsg)) = i32(fd)
		mut header := &C.msghdr(C.alloca(sizeof(C.msghdr)))
		*header = C.msghdr{ msg_iov: vector, msg_iovlen: 1, msg_control: control,
			msg_controllen: C.CMSG_SPACE(sizeof(i32)), msg_flags: 0x5a5a }
		bad_socket_operation(C.vinix_overlay_sendmsg(fd, header, C.MSG_DONTWAIT | C.MSG_NOSIGNAL), 454)
		bad_socket_operation(C.recvmsg(fd, header, C.MSG_DONTWAIT), 455)
		check(*byte == char(`Q`) && header.msg_flags == 0x5a5a
			&& header.msg_controllen == C.CMSG_SPACE(sizeof(i32))
			&& *&i32(C.CMSG_DATA(cmsg)) == fd, 456)
		mut batch := &C.mmsghdr(C.alloca(sizeof(C.mmsghdr)))
		*batch = C.mmsghdr{ msg_hdr: *header, msg_len: 0x5a5a }
		bad_socket_operation(C.sendmmsg(fd, batch, 1, u32(C.MSG_DONTWAIT | C.MSG_NOSIGNAL)), 468)
		bad_socket_operation(C.recvmmsg(fd, batch, 1, u32(C.MSG_DONTWAIT), nil), 469)
		check(batch.msg_len == 0x5a5a && batch.msg_hdr.msg_flags == 0x5a5a
			&& *byte == char(`Q`), 470)
	}
}

// Passing O_PATH via a real socket is permitted. Close the sending descriptor
// before delivery; the queued Handle keeps its metadata and flags alive.
fn pass_socket_metadata(fd int) int {
	unsafe {
		pair := &i32(C.alloca(2 * sizeof(i32)))
		check(C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, pair) == 0, 457)
		byte := &char(C.alloca(1))
		*byte = char(`R`)
		mut vector := &C.iovec(C.alloca(sizeof(C.iovec)))
		*vector = C.iovec{ iov_base: byte, iov_len: 1 }
		control := C.alloca(C.CMSG_SPACE(sizeof(i32)))
		C.memset(control, 0, C.CMSG_SPACE(sizeof(i32)))
		mut cmsg := &C.cmsghdr(control)
		*cmsg = C.cmsghdr{ cmsg_len: C.CMSG_LEN(sizeof(i32)), cmsg_level: C.SOL_SOCKET, cmsg_type: C.SCM_RIGHTS }
		*&i32(C.CMSG_DATA(cmsg)) = i32(fd)
		mut header := &C.msghdr(C.alloca(sizeof(C.msghdr)))
		*header = C.msghdr{ msg_iov: vector, msg_iovlen: 1, msg_control: control,
			msg_controllen: C.CMSG_SPACE(sizeof(i32)) }
		check(C.vinix_overlay_sendmsg(pair[0], header, C.MSG_NOSIGNAL) == 1 && C.close(fd) == 0, 458)
		*byte = char(0)
		C.memset(control, 0, C.CMSG_SPACE(sizeof(i32)))
		check(C.recvmsg(pair[1], header, C.MSG_CMSG_CLOEXEC) == 1 && *byte == char(`R`)
			&& header.msg_controllen == C.CMSG_SPACE(sizeof(i32))
			&& cmsg.cmsg_level == C.SOL_SOCKET && cmsg.cmsg_type == C.SCM_RIGHTS, 459)
		received := *&i32(C.CMSG_DATA(cmsg))
		check(received >= 0 && C.fcntl(received, C.F_GETFL) & C.O_PATH != 0
			&& C.fcntl(received, C.F_GETFD) & C.FD_CLOEXEC != 0, 460)
		mut st := C.stat{}
		check(C.fstat(received, &st) == 0 && st.st_uid == 1000
			&& st.st_mode & C.S_IFMT == C.S_IFSOCK, 461)
		bad_socket_operation(C.listen(received, 1), 462)
		check(C.close(pair[0]) == 0 && C.close(pair[1]) == 0, 463)
		return int(received)
	}
}
