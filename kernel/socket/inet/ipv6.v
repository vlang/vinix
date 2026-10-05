// SPDX-License-Identifier: GPL-2.0-or-later
module inet

import errno
import proc
import lib
import socket.public as sock_pub
import usercopy

// The full socket header defines the V ABI before the endpoint declarations.
#include "vinix_net.h"

struct C.vinix_net_endpoint {
mut:
	words  [4]u32
	scope  u32
	family u16
	port   u16
}

pub struct SockaddrIn6 {
pub mut:
	sin6_family   u16
	sin6_port     u16
	sin6_flowinfo u32
	sin6_addr     [16]u8
	sin6_scope_id u32
}

fn C.vinix_socket_new_family(@type i32, protocol i32, family i32) &C.vinix_socket
fn C.vinix_socket_bind_endpoint(socket &C.vinix_socket, endpoint &C.vinix_net_endpoint) i32
fn C.vinix_socket_connect_endpoint(socket &C.vinix_socket, endpoint &C.vinix_net_endpoint) i32
fn C.vinix_socket_send_endpoint(socket &C.vinix_socket, data voidptr, length u64, endpoint &C.vinix_net_endpoint, has_address i32) i32
fn C.vinix_socket_recv_endpoint(socket &C.vinix_socket, data voidptr, length u64, endpoint &C.vinix_net_endpoint) i32
fn C.vinix_socket_name_endpoint(socket &C.vinix_socket, endpoint &C.vinix_net_endpoint, peer i32) i32
fn C.vinix_socket_membership(socket &C.vinix_socket, endpoint &C.vinix_net_endpoint, interface_address u32, join i32) i32
fn C.vinix_socket_multicast_interface(socket &C.vinix_socket, family i32, index u32, interface_address u32) i32
fn C.vinix_net_ipv6_address(index u32, slot u32, endpoint &C.vinix_net_endpoint, state &u32, valid &u32, preferred &u32) i32

// Every endpoint lives in its public caller's stack slot. lwIP copies it
// synchronously; a blocking retry never allocates another endpoint.
fn fill_endpoint(addr voidptr, addrlen u32, family int, mut endpoint C.vinix_net_endpoint) ? {
	unsafe { C.memset(endpoint, 0, sizeof(C.vinix_net_endpoint)) }
	if addr == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	if addrlen < 2 {
		errno.set(errno.einval)
		return none
	}
	supplied := unsafe { *&u16(addr) }
	if int(supplied) != family {
		errno.set(errno.eafnosupport)
		return none
	}
	endpoint.family = supplied
	if family == sock_pub.af_inet {
		if addrlen < sizeof(SockaddrIn) {
			errno.set(errno.einval)
			return none
		}
		source := unsafe { &SockaddrIn(addr) }
		endpoint.port = source.sin_port
		endpoint.words[0] = source.sin_addr
	} else {
		if addrlen < sizeof(SockaddrIn6) {
			errno.set(errno.einval)
			return none
		}
		source := unsafe { &SockaddrIn6(addr) }
		endpoint.port = source.sin6_port
		endpoint.scope = source.sin6_scope_id
		unsafe { C.memcpy(&endpoint.words[0], &source.sin6_addr[0], 16) }
	}
	refused := proc.pledge_check_inet_destination(endpoint.port)
	if refused != 0 {
		errno.set(refused)
		return none
	}
}

fn copy_endpoint_out(endpoint &C.vinix_net_endpoint, addr voidptr, addrlen &u32) {
	if addr == unsafe { nil } || addrlen == unsafe { nil } { return }
	storage := C.vinix_stack_alloc(sizeof(SockaddrIn6))
	unsafe { C.memset(storage, 0, sizeof(SockaddrIn6)) }
	if endpoint.family == sock_pub.af_inet {
		mut target := unsafe { &SockaddrIn(storage) }
		target.sin_family = endpoint.family
		target.sin_port = endpoint.port
		target.sin_addr = endpoint.words[0]
		sock_pub.copy_out_sockaddr(addr, addrlen, storage, sizeof(SockaddrIn))
	} else {
		mut target := unsafe { &SockaddrIn6(storage) }
		target.sin6_family = endpoint.family
		target.sin6_port = endpoint.port
		target.sin6_scope_id = endpoint.scope
		unsafe { C.memcpy(&target.sin6_addr[0], &endpoint.words[0], 16) }
		sock_pub.copy_out_sockaddr(addr, addrlen, storage, sizeof(SockaddrIn6))
	}
}

// Linux multicast options contain addresses and interface indices, rather
// than a scalar int. The syscall dispatch reads these before its int path.
pub fn is_structured_ip_option(level int, option int) bool {
	return (level == 0 && option >= 32 && option <= 36)
		|| level == 41
}

pub fn (mut this InetSocket) set_structured_ip_option(level int, option int, value u64, length u32) ? {
	storage := C.vinix_stack_alloc(20)
	unsafe { C.memset(storage, 0, 20) }
	minimum := if level == 41 && (option == 20 || option == 21) {
		u32(20)
	} else if level == 41 {
		u32(4)
	} else if option == 35 || option == 36 {
		u32(8)
	} else if option == 32 {
		u32(4)
	} else {
		u32(1)
	}
	if length < minimum {
		errno.set(errno.einval)
		return none
	}
	amount := if level == 41 {
		if option == 20 || option == 21 { u64(20) } else { u64(4) }
	} else if option == 33 || option == 34 {
		if length >= 4 { u64(4) } else { u64(1) }
	} else {
		if length >= 12 {
			u64(12)
		} else if length >= 8 {
			u64(8)
		} else {
			u64(4)
		}
	}

	if !usercopy.copy_from_user(storage, value, amount) {
		errno.set(errno.efault)
		return none
	}
	if (level == 0 && (option == 33 || option == 34))
		|| (level == 41 && option != 20 && option != 21) {
		number := if length >= 4 {
			unsafe { *&i32(storage) }
		} else {
			int(unsafe { *&u8(storage) })
		}
		this.setsockopt(unsafe { nil }, level, option, number)?
		return
	}
	mut endpoint := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	unsafe { C.memset(endpoint, 0, sizeof(C.vinix_net_endpoint)) }
	endpoint.family = if level == 41 { u16(10) } else { u16(2) }
	mut interface_address := u32(0)
	if level == 41 {
		unsafe { C.memcpy(&endpoint.words[0], storage, 16) }
		endpoint.scope = unsafe { *&u32(voidptr(u64(storage) + 16)) }
	} else if option == 32 {
		// in_addr, ip_mreq, or Linux ip_mreqn.
		if length < 4 {
			errno.set(errno.einval)
			return none
		}
		interface_address = unsafe { *&u32(voidptr(u64(storage) + if length >= 8 { 4 } else { 0 })) }
		if length >= 12 { endpoint.scope = unsafe { *&u32(voidptr(u64(storage) + 8)) } }
	} else {
		endpoint.words[0] = unsafe { *&u32(storage) }
		interface_address = unsafe { *&u32(voidptr(u64(storage) + 4)) }
		if length >= 12 { endpoint.scope = unsafe { *&u32(voidptr(u64(storage) + 8)) } }
	}
	net_lock.acquire()
	result := if level == 0 && option == 32 {
		C.vinix_socket_multicast_interface(this.handle, 2, endpoint.scope, interface_address)
	} else {
		C.vinix_socket_membership(this.handle, endpoint, interface_address,
			if option == 35 || option == 20 { 1 } else { 0 })
	}
	refresh_registered_sockets()
	net_lock.release()
	if result != 0 {
		set_error(result)
		return none
	}
}

fn proc_net_if_inet6_text() string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(1024) }
	mut endpoint := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	scalar := C.vinix_stack_alloc(12)
	state := unsafe { &u32(scalar) }
	valid := unsafe { &u32(voidptr(u64(scalar) + 4)) }
	preferred := unsafe { &u32(voidptr(u64(scalar) + 8)) }
	net_lock.acquire()
	for index := u32(1); index <= 2; index++ {
		for slot := u32(0); slot < 6; slot++ {
			if C.vinix_net_ipv6_address(index, slot, endpoint, state, valid, preferred) == 0 {
				continue
			}
			address_state := unsafe { *state }
			if address_state == 0 { continue }
			bytes := unsafe { &u8(&endpoint.words[0]) }
			for byte := 0; byte < 16; byte++ { text.add_radix(u64(unsafe { bytes[byte] }), 16, 2) }
			text.add_byte(` `)
			text.add_radix(u64(index), 16, 2)
			text.add(if index == 1 { ' 80 ' } else { ' 40 ' })
			scope := if endpoint.scope != 0 {
				u64(0x20)
			} else if index == 1 {
				u64(0x10)
			} else {
				u64(0)
			}
			text.add_radix(scope, 16, 2)
			text.add_byte(` `)
			flags := if address_state & 0x08 != 0 {
				u64(0x40)
			} else if address_state == 0x40 {
				u64(0x48)
			} else if address_state == 0x10 && index != 1 {
				u64(0x20)
			} else if unsafe { *valid } == 0 {
				u64(0x80)
			} else {
				u64(0)
			}
			text.add_radix(flags, 16, 2)
			text.add(if index == 1 { ' lo\n' } else { ' eth0\n' })
		}
	}
	net_lock.release()
	return text.str()
}

fn proc_net_tcp6_text() string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(4096) }
	text.add('  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n')
	mut local := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	mut remote := unsafe { &C.vinix_net_endpoint(C.vinix_stack_alloc(sizeof(C.vinix_net_endpoint))) }
	net_lock.acquire()
	sockets_lock.acquire()
	mut row := 0
	for i := 0; i < max_sockets; i++ {
		if sockets[i] == unsafe { nil } { continue }
		socket := unsafe { &InetSocket(sockets[i]) }
		if socket.family != 10 || socket.socktype != sock_pub.sock_stream { continue }
		if C.vinix_socket_name_endpoint(socket.handle, local, 0) != 0 || local.port == 0 {
			continue
		}
		unsafe { C.memset(remote, 0, sizeof(C.vinix_net_endpoint)) }
		connected := C.vinix_socket_name_endpoint(socket.handle, remote, 1) == 0
		if !connected && !socket.listening { continue }
		text.add_unsigned(u64(row))
		text.add(': ')
		for word := 0; word < 4; word++ { text.add_radix(u64(local.words[word]), 16, 8) }
		text.add_byte(`:`)
		text.add_radix(u64((local.port >> 8) | (local.port << 8)), 16, 4)
		text.add_byte(` `)
		for word := 0; word < 4; word++ { text.add_radix(u64(remote.words[word]), 16, 8) }
		text.add_byte(`:`)
		text.add_radix(u64((remote.port >> 8) | (remote.port << 8)), 16, 4)
		text.add(if connected { ' 01 ' } else { ' 0a ' })
		text.add('00000000:00000000 00:00000000 00000000 0 0 ')
		text.add_unsigned(socket.stat.ino)
		text.add_byte(`\n`)
		row++
	}
	sockets_lock.release()
	net_lock.release()
	return text.str()
}
