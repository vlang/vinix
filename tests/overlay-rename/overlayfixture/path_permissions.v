// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <native-abi.h>

fn C.umask(u32) u32

fn refused_socket_target(result isize, site int) {
	unsafe {
		code := *C.__errno_location()
		if result != -1 || code != C.EACCES {
			C.printf(c'OVERLAY SOCKET PERMISSION: site=%d result=%ld errno=%d\n', site, result, code)
			C.fflush(nil)
		}
		check(result == -1 && code == C.EACCES, site)
	}
}

fn socket_private_connections(client int, listener int, address &C.sockaddr_un) {
	unsafe {
		for mode in [u32(0), u32(0o400), u32(0o100)]! {
			check(C.chmod(&address.sun_path[0], mode) == 0, 485)
			refused_socket_target(C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))), 486)
		}
		length := &u32(C.alloca(sizeof(u32)))
		*length = u32(sizeof(C.sockaddr_un))
		mut peer := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		check(C.getpeername(client, &C.sockaddr(peer), length) == -1
			&& *C.__errno_location() == C.ENOTCONN, 487)
		flags := C.fcntl(listener, C.F_GETFL)
		check(flags >= 0 && C.fcntl(listener, C.F_SETFL, i32(flags | C.O_NONBLOCK)) == 0, 488)
		check(C.accept(listener, nil, nil) == -1 && *C.__errno_location() == C.EAGAIN
			&& C.fcntl(listener, C.F_SETFL, i32(flags)) == 0, 489)
	}
}

fn socket_record_permissions(base &char) {
	unsafe {
		mut path := [108]char{}
		check(C.snprintf(&path[0], 108, c'%s/socket-record', base) > 0, 490)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		socket_address(&path[0], address)
		listener := C.socket(C.AF_UNIX, C.SOCK_SEQPACKET, 0)
		client := C.socket(C.AF_UNIX, C.SOCK_SEQPACKET, 0)
		check(listener >= 0 && client >= 0
			&& C.bind(listener, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0
			&& C.listen(listener, 1) == 0 && C.chmod(&path[0], 0o400) == 0, 491)
		refused_socket_target(C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))), 492)
		check(C.chmod(&path[0], 0o200) == 0
			&& C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0, 493)
		accepted := C.accept(listener, nil, nil)
		mut byte := char(0)
		check(accepted >= 0 && C.chmod(&path[0], 0) == 0
			&& C.write(client, c'R', 1) == 1 && C.read(accepted, &byte, 1) == 1
			&& byte == char(`R`), 494)
		check(C.unlink(&path[0]) == 0 && C.close(accepted) == 0
			&& C.close(client) == 0 && C.close(listener) == 0, 495)
	}
}

fn receive_permission_byte(server int, expected char, site int) {
	unsafe {
		mut byte := char(0)
		check(C.recvfrom(server, &byte, 1, C.MSG_DONTWAIT, nil, nil) == 1 && byte == expected, site)
	}
}

fn socket_datagram_permissions(base &char) {
	unsafe {
		mut path := [108]char{}
		check(C.snprintf(&path[0], 108, c'%s/socket-datagram', base) > 0, 496)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		socket_address(&path[0], address)
		server := C.socket(C.AF_UNIX, C.SOCK_DGRAM, 0)
		client := C.socket(C.AF_UNIX, C.SOCK_DGRAM, 0)
		check(server >= 0 && client >= 0
			&& C.bind(server, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0, 497)
		byte := &char(C.alloca(1))
		*byte = char(`D`)
		mut vector := &C.iovec(C.alloca(sizeof(C.iovec)))
		*vector = C.iovec{ iov_base: byte, iov_len: 1 }
		mut header := &C.msghdr(C.alloca(sizeof(C.msghdr)))
		*header = C.msghdr{ msg_name: address, msg_namelen: u32(sizeof(C.sockaddr_un)),
			msg_iov: vector, msg_iovlen: 1 }
		mut batch := &C.mmsghdr(C.alloca(sizeof(C.mmsghdr)))
		*batch = C.mmsghdr{ msg_hdr: *header, msg_len: 0x5a5a }
		for mode in [u32(0), u32(0o400), u32(0o100)]! {
			check(C.chmod(&path[0], mode) == 0, 498)
			refused_socket_target(C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))), 499)
			refused_socket_target(C.vinix_overlay_sendto(client, byte, 1, C.MSG_DONTWAIT,
				address, u32(sizeof(C.sockaddr_un))), 500)
			refused_socket_target(C.vinix_overlay_sendmsg(client, header, C.MSG_DONTWAIT), 501)
			refused_socket_target(C.sendmmsg(client, batch, 1, u32(C.MSG_DONTWAIT)), 502)
			check(batch.msg_len == 0x5a5a, 503)
			refused_socket_target(C.vinix_overlay_sendto(client, nil, 0, C.MSG_DONTWAIT,
				address, u32(sizeof(C.sockaddr_un))), 504)
			check(C.recvfrom(server, byte, 1, C.MSG_DONTWAIT, nil, nil) == -1
				&& *C.__errno_location() == C.EAGAIN && *byte == char(`D`), 505)
		}
		check(C.chmod(&path[0], 0o200) == 0
			&& C.vinix_overlay_sendto(client, byte, 1, C.MSG_DONTWAIT, address, u32(sizeof(C.sockaddr_un))) == 1, 506)
		receive_permission_byte(server, char(`D`), 507)
		check(C.vinix_overlay_sendmsg(client, header, C.MSG_DONTWAIT) == 1, 508)
		receive_permission_byte(server, char(`D`), 509)
		check(C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0
			&& C.chmod(&path[0], 0) == 0, 510)
		// A failed reconnect must retain the previous target. Existing connected
		// sends continue after chmod; only another pathname lookup is refused.
		refused_socket_target(C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))), 511)
		refused_socket_target(C.vinix_overlay_sendto(client, byte, 1, C.MSG_DONTWAIT,
			address, u32(sizeof(C.sockaddr_un))), 512)
		check(C.write(client, c'C', 1) == 1, 513)
		receive_permission_byte(server, char(`C`), 514)
		check(C.unlink(&path[0]) == 0 && C.close(client) == 0 && C.close(server) == 0, 515)
	}
}

fn socket_abstract_permissions() {
	unsafe {
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		*address = C.sockaddr_un{}
		address.sun_family = u16(C.AF_UNIX)
		check(C.snprintf(&address.sun_path[1], 107, c'vinix-permission') > 0, 516)
		server := C.socket(C.AF_UNIX, C.SOCK_DGRAM, 0)
		client := C.socket(C.AF_UNIX, C.SOCK_DGRAM, 0)
		check(server >= 0 && client >= 0, 517)
		old_mask := C.umask(0o777)
		bound := C.bind(server, voidptr(address), u32(sizeof(C.sockaddr_un)))
		C.umask(old_mask)
		check(bound == 0 && C.vinix_overlay_connect(client, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0
			&& C.write(client, c'A', 1) == 1, 518)
		receive_permission_byte(server, char(`A`), 519)
		check(C.close(client) == 0 && C.close(server) == 0, 520)
	}
}
