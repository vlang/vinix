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

fn C.socket(domain int, kind int, protocol int) int
fn C.connect(fd int, address voidptr, length u32) int

struct C.sockaddr_un {
mut:
	sun_family u16
	sun_path   [108]char
}

pub const default_socket = '/run/vinix/auth.sock'

// Send `request` and return the reply. The request is wiped either way.
pub fn transact(socket_path string, mut request authproto.Frame) !authproto.Frame {
	defer { request.wipe() }
	if socket_path.len >= 100 {
		return error('socket path too long')
	}
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 {
		return error('cannot create a socket')
	}
	defer { C.close(fd) }
	mut address := C.sockaddr_un{}
	address.sun_family = u16(C.AF_UNIX)
	unsafe { vmemcpy(&address.sun_path[0], socket_path.str, socket_path.len) }
	if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		return error('the authentication service is not running')
	}
	authproto.write_frame(fd, request)!
	return authproto.read_frame(fd) or {
		return error('the authentication service is busy or refused the request')
	}
}

pub fn ask(socket_path string, code u16, fields ...[]u8) !authproto.Frame {
	mut request := authproto.Frame{
		code:   code
		fields: fields
	}
	return transact(socket_path, mut request)
}
