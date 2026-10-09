// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

fn C.socket(int, int, int) int
fn C.socketpair(int, int, int, &i32) int
fn C.bind(int, voidptr, u32) int
fn C.connect(int, voidptr, u32) int
fn C.listen(int, int) int
fn C.accept(int, voidptr, &u32) int
fn C.getsockname(int, voidptr, &u32) int
fn C.getpeername(int, voidptr, &u32) int
fn C.shutdown(int, int) int
fn C.send(int, voidptr, usize, int) isize
fn C.recv(int, voidptr, usize, int) isize
fn C.sendto(int, voidptr, usize, int, voidptr, u32) isize
fn C.recvfrom(int, voidptr, usize, int, voidptr, &u32) isize
fn C.getsockopt(int, int, int, voidptr, &u32) int
fn C.setsockopt(int, int, int, voidptr, u32) int
fn C.inet_pton(int, &char, voidptr) int
fn C.inet_ntop(int, voidptr, &char, u32) &char
fn C.inet_addr(&char) u32
fn C.htons(u16) u16
fn C.ntohs(u16) u16
fn C.htonl(u32) u32
fn C.ntohl(u32) u32

fn socket_result(result isize) isize {
	if result < 0 { darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() })) }
	return result
}

fn socket_native_family(family int) int {
	return match family {
		0 { int(C.AF_UNSPEC) }
		1 { int(C.AF_UNIX) }
		2 { int(C.AF_INET) }
		30 { int(C.AF_INET6) }
		else { -1 }
	}
}

fn darwin_socket(family int, kind int, protocol int) int {
	native := socket_native_family(family)
	if native < 0 { darwin_set_errno(47); return -1 }
	// Darwin has no Linux SOCK_NONBLOCK / SOCK_CLOEXEC type bits.
	if kind < 1 || kind > 5 { darwin_set_errno(44); return -1 }
	return int(socket_result(C.socket(native, kind, protocol)))
}

fn darwin_socketpair(family int, kind int, protocol int, pair &i32) int {
	native := socket_native_family(family)
	if native < 0 { darwin_set_errno(47); return -1 }
	if kind < 1 || kind > 5 { darwin_set_errno(44); return -1 }
	return int(socket_result(C.socketpair(native, kind, protocol, pair)))
}

// Fixed stack storage keeps native address conversion independent of the
// caller's buffer length. IPv4/IPv6 ports and addresses stay in network order;
// flow info and scope IDs have identical offsets on both ARM64 ABIs.
fn socket_address_in(address voidptr, length u32, native voidptr) bool {
	if address == unsafe { nil } { darwin_set_errno(14); return false }
	if length < 2 || length > 106 { darwin_set_errno(22); return false }
	family := int(unsafe { (&u8(address))[1] })
	if (family == 2 && length != 16) || (family == 30 && length != 28) {
		darwin_set_errno(22); return false
	}
	if family !in [1, 2, 30] { darwin_set_errno(47); return false }
	unsafe { C.memcpy(native, address, length) }
	$if linux {
		unsafe { *(&u16(native)) = u16(socket_native_family(family)) }
	}
	return true
}

fn socket_address_out(native voidptr, size u32, output voidptr, length &u32) {
	mut actual := size
	$if linux {
		family := int(unsafe { *(&u16(native)) })
		darwin := match family { C.AF_INET { 2 } C.AF_INET6 { 30 } C.AF_UNIX { 1 } else { 0 } }
		// Darwin reports a zero-filled generic sockaddr for unnamed UNIX peers.
		if family == C.AF_UNIX && size == 2 { actual = 16 }
		unsafe { (&u8(native))[0] = u8(actual); (&u8(native))[1] = u8(darwin) }
	}
	capacity := unsafe { *length }
	copied := if capacity < actual { capacity } else { actual }
	if copied != 0 { unsafe { C.memcpy(output, native, copied) } }
	unsafe { *length = actual }
}

fn darwin_bind(fd int, address voidptr, length u32) int {
	mut storage := [32]u64{}
	native := unsafe { voidptr(&storage[0]) }
	if !socket_address_in(address, length, native) { return -1 }
	return int(socket_result(C.bind(fd, native, length)))
}

fn darwin_connect(fd int, address voidptr, length u32) int {
	mut storage := [32]u64{}
	native := unsafe { voidptr(&storage[0]) }
	if !socket_address_in(address, length, native) { return -1 }
	return int(socket_result(C.connect(fd, native, length)))
}

fn darwin_listen(fd int, backlog int) int { return int(socket_result(C.listen(fd, backlog))) }
fn darwin_shutdown(fd int, how int) int { return int(socket_result(C.shutdown(fd, how))) }

fn socket_name(fd int, output voidptr, length &u32, operation int) int {
	if (output == unsafe { nil } && operation != 2) || (output != unsafe { nil } && length == unsafe { nil }) {
		darwin_set_errno(14); return -1
	}
	mut storage := [32]u64{}
	mut size := u32(sizeof(storage))
	native := unsafe { voidptr(&storage[0]) }
	result := match operation {
		0 { C.getsockname(fd, native, unsafe { &size }) }
		1 { C.getpeername(fd, native, unsafe { &size }) }
		else { C.accept(fd, if output == unsafe { nil } { unsafe { nil } } else { native }, unsafe { &size }) }
	}
	if result < 0 { return int(socket_result(result)) }
	if output != unsafe { nil } { socket_address_out(native, size, output, length) }
	return result
}

fn darwin_getsockname(fd int, address voidptr, length &u32) int { return socket_name(fd, address, length, 0) }
fn darwin_getpeername(fd int, address voidptr, length &u32) int { return socket_name(fd, address, length, 1) }
fn darwin_accept(fd int, address voidptr, length &u32) int { return socket_name(fd, address, length, 2) }

fn socket_native_flags(flags int) int {
	if flags & ~(1 | 2 | 4 | 8 | 0x40 | 0x80 | 0x80000) != 0 { darwin_set_errno(45); return -1 }
	mut native := 0
	for pair in [[1, int(C.MSG_OOB)]!, [2, int(C.MSG_PEEK)]!, [4, int(C.MSG_DONTROUTE)]!,
		[8, int(C.MSG_EOR)]!, [0x40, int(C.MSG_WAITALL)]!, [0x80, int(C.MSG_DONTWAIT)]!, [0x80000, int(C.MSG_NOSIGNAL)]!]! {
		if flags & pair[0] != 0 { native |= pair[1] }
	}
	return native
}

fn darwin_send(fd int, buffer voidptr, count usize, flags int) isize {
	native := socket_native_flags(flags)
	if native < 0 { return -1 }
	return socket_result(C.send(fd, buffer, count, native))
}

fn darwin_recv(fd int, buffer voidptr, count usize, flags int) isize {
	native := socket_native_flags(flags)
	if native < 0 { return -1 }
	return socket_result(C.recv(fd, buffer, count, native))
}

fn darwin_sendto(fd int, buffer voidptr, count usize, flags int, address voidptr, length u32) isize {
	flag := socket_native_flags(flags)
	if flag < 0 { return -1 }
	mut storage := [32]u64{}
	native := unsafe { voidptr(&storage[0]) }
	if address != unsafe { nil } && !socket_address_in(address, length, native) { return -1 }
	return socket_result(C.sendto(fd, buffer, count, flag, if address == unsafe { nil } { unsafe { nil } } else { native }, length))
}

fn darwin_recvfrom(fd int, buffer voidptr, count usize, flags int, address voidptr, length &u32) isize {
	flag := socket_native_flags(flags)
	if flag < 0 { return -1 }
	if address != unsafe { nil } && length == unsafe { nil } { darwin_set_errno(14); return -1 }
	mut storage := [32]u64{}
	mut size := u32(sizeof(storage))
	native := unsafe { voidptr(&storage[0]) }
	result := socket_result(C.recvfrom(fd, buffer, count, flag, if address == unsafe { nil } { unsafe { nil } } else { native }, unsafe { &size }))
	if result >= 0 && address != unsafe { nil } { socket_address_out(native, size, address, length) }
	return result
}

// Whitelist options whose values have matching representations, plus timeval
// and SO_ERROR conversions below. Apple service/QoS and SIGPIPE options need
// additional semantics and deliberately fail rather than claim success.
fn socket_linger_seconds_option() int {
	$if macos { return 0x1080 }
	return int(C.SO_LINGER)
}

fn socket_option(level int, option int) (int, int) {
	if level == 0xffff {
		native := match option {
			1 { int(C.SO_DEBUG) } 2 { int(C.SO_ACCEPTCONN) }
			4 { int(C.SO_REUSEADDR) } 8 { int(C.SO_KEEPALIVE) }
			0x10 { int(C.SO_DONTROUTE) } 0x20 { int(C.SO_BROADCAST) }
			0x1080 { socket_linger_seconds_option() } 0x100 { int(C.SO_OOBINLINE) }
			0x200 { int(C.SO_REUSEPORT) }
			0x1001 { int(C.SO_SNDBUF) } 0x1002 { int(C.SO_RCVBUF) }
			0x1003 { int(C.SO_SNDLOWAT) } 0x1004 { int(C.SO_RCVLOWAT) }
			0x1005 { int(C.SO_SNDTIMEO) } 0x1006 { int(C.SO_RCVTIMEO) }
			0x1007 { int(C.SO_ERROR) } 0x1008 { int(C.SO_TYPE) }
			else { -1 }
		}
		return int(C.SOL_SOCKET), native
	}
	if level == 6 && option == 1 { return int(C.IPPROTO_TCP), int(C.TCP_NODELAY) }
	if level == 0 && option == 3 { return int(C.IPPROTO_IP), int(C.IP_TOS) }
	if level == 0 && option == 4 { return int(C.IPPROTO_IP), int(C.IP_TTL) }
	return -1, -1
}

fn darwin_setsockopt(fd int, level int, option int, value voidptr, size u32) int {
	native_level, native_option := socket_option(level, option)
	if native_option < 0 { darwin_set_errno(42); return -1 }
	if value == unsafe { nil } { darwin_set_errno(14); return -1 }
	if level == 0xffff && option in [0x1005, 0x1006] {
		if size != 16 { darwin_set_errno(22); return -1 }
		mut time := [2]i64{}
		time[0] = unsafe { *(&i64(value)) }
		time[1] = i64(unsafe { *(&i32(u64(value) + 8)) })
		return int(socket_result(C.setsockopt(fd, native_level, native_option, unsafe { &time[0] }, 16)))
	}
	return int(socket_result(C.setsockopt(fd, native_level, native_option, value, size)))
}

fn darwin_getsockopt(fd int, level int, option int, value voidptr, length &u32) int {
	native_level, native_option := socket_option(level, option)
	if native_option < 0 { darwin_set_errno(42); return -1 }
	if value == unsafe { nil } || length == unsafe { nil } { darwin_set_errno(14); return -1 }
	mut storage := [4]i64{}
	mut size := u32(sizeof(storage))
	result := socket_result(C.getsockopt(fd, native_level, native_option, unsafe { &storage[0] }, unsafe { &size }))
	if result < 0 { return int(result) }
	if level == 0xffff && option == 0x1007 { write32(u64(unsafe { &storage[0] }), u32(darwin_native_error(int(storage[0])))) }
	if level == 0xffff && option in [0x1005, 0x1006] {
		$if linux { storage[1] = i64(u32(storage[1])) }
	}
	capacity := unsafe { *length }
	copied := if capacity < size { capacity } else { size }
	unsafe { C.memcpy(value, &storage[0], copied); *length = copied }
	return 0
}

fn darwin_inet_pton(family int, text &char, output voidptr) int {
	if family !in [2, 30] { darwin_set_errno(47); return -1 }
	return int(socket_result(C.inet_pton(socket_native_family(family), text, output)))
}

fn darwin_inet_ntop(family int, address voidptr, output &char, size u32) &char {
	if family !in [2, 30] { darwin_set_errno(47); return unsafe { nil } }
	result := C.inet_ntop(socket_native_family(family), address, output, size)
	if result == unsafe { nil } { socket_result(-1) }
	return result
}

fn darwin_htons(value u16) u16 { return C.htons(value) }
fn darwin_ntohs(value u16) u16 { return C.ntohs(value) }
fn darwin_htonl(value u32) u32 { return C.htonl(value) }
fn darwin_ntohl(value u32) u32 { return C.ntohl(value) }

fn sockets_symbol(symbol string) ?u64 {
	return match symbol {
		'_socket' { u64(unsafe { voidptr(darwin_socket) }) }
		'_socketpair' { u64(unsafe { voidptr(darwin_socketpair) }) }
		'_bind' { u64(unsafe { voidptr(darwin_bind) }) }
		'_connect' { u64(unsafe { voidptr(darwin_connect) }) }
		'_listen' { u64(unsafe { voidptr(darwin_listen) }) }
		'_accept' { u64(unsafe { voidptr(darwin_accept) }) }
		'_getsockname' { u64(unsafe { voidptr(darwin_getsockname) }) }
		'_getpeername' { u64(unsafe { voidptr(darwin_getpeername) }) }
		'_shutdown' { u64(unsafe { voidptr(darwin_shutdown) }) }
		'_send' { u64(unsafe { voidptr(darwin_send) }) }
		'_recv' { u64(unsafe { voidptr(darwin_recv) }) }
		'_sendto' { u64(unsafe { voidptr(darwin_sendto) }) }
		'_recvfrom' { u64(unsafe { voidptr(darwin_recvfrom) }) }
		'_setsockopt' { u64(unsafe { voidptr(darwin_setsockopt) }) }
		'_getsockopt' { u64(unsafe { voidptr(darwin_getsockopt) }) }
		'_inet_pton' { u64(unsafe { voidptr(darwin_inet_pton) }) }
		'_inet_ntop' { u64(unsafe { voidptr(darwin_inet_ntop) }) }
		'_inet_addr' { u64(unsafe { voidptr(C.inet_addr) }) }
		'_htons' { u64(unsafe { voidptr(darwin_htons) }) }
		'_ntohs' { u64(unsafe { voidptr(darwin_ntohs) }) }
		'_htonl' { u64(unsafe { voidptr(darwin_htonl) }) }
		'_ntohl' { u64(unsafe { voidptr(darwin_ntohl) }) }
		else { return none }
	}
}
