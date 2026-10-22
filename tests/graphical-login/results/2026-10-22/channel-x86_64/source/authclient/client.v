// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The caller's side of the authentication service: connect, send one
// request, read one reply.
module authclient

import authproto

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <sys/time.h>

fn C.socket(domain int, kind int, protocol int) int
fn C.connect(fd int, address voidptr, length u32) int
fn C.getsockopt(int, int, int, voidptr, &u32) int
fn C.setsockopt(int, int, int, voidptr, u32) int
$if !linux { fn C.getpeereid(int, &u32, &u32) int }

struct RootCredentials { mut: pid i32 uid u32 gid u32 }
struct ServiceTimeout { seconds i64 microseconds i64 }

pub fn require_root_peer(fd int) ! {
	$if linux {
		mut credentials := RootCredentials{}
		mut length := u32(sizeof(RootCredentials))
		if C.getsockopt(fd, 1, 17, &credentials, &length) != 0 || length != sizeof(RootCredentials) || credentials.uid != 0 {
			return error('the authentication service peer is not root')
		}
	} $else {
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(fd, &uid, &gid) != 0 || uid != 0 { return error('the authentication service peer is not root') }
	}
}

struct C.sockaddr_un {
mut:
	sun_family u16
	sun_path   [108]char
}

pub const default_socket = '/run/vinix/auth.sock'

// Send `request` and return the reply. The request is wiped either way.
pub fn transact(socket_path string, mut request authproto.Frame) !authproto.Frame {
	return transact_checked(socket_path, mut request, false)
}

fn transact_checked(socket_path string, mut request authproto.Frame, root_peer bool) !authproto.Frame {
	return transact_bounded(socket_path, mut request, root_peer, 150)
}

fn transact_bounded(socket_path string, mut request authproto.Frame, root_peer bool, seconds i64) !authproto.Frame {
	defer { request.wipe() }
	if socket_path.len >= 100 {
		return error('socket path too long')
	}
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 {
		return error('cannot create a socket')
	}
	defer { C.close(fd) }
	if root_peer {
		// The service allows 150 seconds for a real password KDF. Connecting
		// and sending are short local operations; a stalled peer cannot hold
		// the privileged manager indefinitely.
		write_timeout := ServiceTimeout{seconds: 2}
		read_timeout := ServiceTimeout{seconds: seconds}
		if C.setsockopt(fd, C.SOL_SOCKET, C.SO_SNDTIMEO, &write_timeout, u32(sizeof(write_timeout))) != 0
			|| C.setsockopt(fd, C.SOL_SOCKET, C.SO_RCVTIMEO, &read_timeout, u32(sizeof(read_timeout))) != 0 {
			return error('cannot bound the authentication service connection')
		}
	}
	mut address := C.sockaddr_un{}
	address.sun_family = u16(C.AF_UNIX)
	unsafe { vmemcpy(&address.sun_path[0], socket_path.str, socket_path.len) }
	if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		return error('the authentication service is not running')
	}
	if root_peer { require_root_peer(fd)! }
	authproto.write_frame(fd, request)!
	return authproto.read_frame(fd) or {
		discard_frame_error(err)
		return error('the authentication service is busy or refused the request')
	}
}

// Keep the interface as a value parameter. Calling its mutable free method on
// the implicit `or` error makes V heap-promote that wrapper under manualfree.
// The diagnostic remains generic; retire both the owned message and error.
fn discard_frame_error(err IError) {
	message := err.msg()
	unsafe { message.free(); err.free() }
}

pub fn ask(socket_path string, code u16, fields ...[]u8) !authproto.Frame {
	mut request := authproto.Frame{
		code:   code
		fields: fields
	}
	return transact(socket_path, mut request)
}

// Privileged clients verify the service's kernel identity before sending any
// password. The unguarded API remains available for explicit non-root fixtures.
pub fn ask_root(socket_path string, code u16, fields ...[]u8) !authproto.Frame {
	mut request := authproto.Frame{ code: code, fields: fields }
	return transact_checked(socket_path, mut request, true)
}

// A startup probe has no password and a separate short deadline. Root peer
// credentials alone are insufficient: the expected service must answer too.
pub fn root_service_ready(socket_path string) bool {
	mut request := authproto.Frame{code: authproto.op_info}
	mut answer := transact_bounded(socket_path, mut request, true, 2) or { discard_frame_error(err); return false }
	defer { answer.close() }
	return answer.code == authproto.status_ok
}

// Distinguish a stale socket from a live, unhealthy service. Bootstrap must
// never start a second authd which would unlink a live service's address.
pub fn root_service_listening(socket_path string) !bool {
	if socket_path.len == 0 || socket_path.len >= 100 { return error('invalid authentication socket path') }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create readiness socket') }
	defer { C.close(fd) }
	timeout := ServiceTimeout{seconds: 2}
	if C.setsockopt(fd, C.SOL_SOCKET, C.SO_SNDTIMEO, &timeout, u32(sizeof(timeout))) != 0 { return error('cannot bound readiness connection') }
	mut address := C.sockaddr_un{sun_family: u16(C.AF_UNIX)}
	unsafe { vmemcpy(&address.sun_path[0], socket_path.str, socket_path.len) }
	if C.connect(fd, &address, u32(sizeof(address))) != 0 {
		if C.errno == C.ENOENT || C.errno == C.ECONNREFUSED { return false }
		return error('authentication service readiness connection failed')
	}
	require_root_peer(fd)!
	return true
}
