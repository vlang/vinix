// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
import nativeaccountauth
import desktop.sessionruntime
import desktop.windowfb

struct WindowAddress {
mut:
	prefix [2]u8
	path   [100]u8
}

fn window_address(path string) !WindowAddress {
	mut address := WindowAddress{}
	if path.len == 0 || path.len >= address.path.len || path.contains('\x00')
		|| !sessionruntime.socket_directory(path, 'windows') {
		return error('invalid account UI desktop endpoint')
	}
	$if macos {
		address.prefix[0] = u8(sizeof(WindowAddress))
		address.prefix[1] = u8(C.AF_UNIX)
	} $else {
		address.prefix[0] = u8(C.AF_UNIX)
		address.prefix[1] = u8(C.AF_UNIX >> 8)
	}
	for i, byte in path { address.path[i] = byte }
	return address
}

fn connect_window(path string, lifetime int, deadline i64) !&windowfb.Connection {
	address := window_address(path)!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create account UI window socket') }
	mut connected := false
	defer { if !connected { C.close(fd) } }
	protect_fd(fd, true)!
	for {
		if !lifetime_alive(lifetime)! { return error('account UI request expired') }
		if time.sys_mono_now() >= deadline {
			return error('account UI window connection timed out')
		}
		result := C.connect(fd, unsafe { voidptr(&address) }, u32(sizeof(WindowAddress)))
		if result == 0 || C.errno == C.EISCONN { break }
		if C.errno == C.EINTR { continue }
		if C.errno !in [C.EINPROGRESS, C.EALREADY, C.EAGAIN, C.EWOULDBLOCK]! {
			return error('account UI desktop is unavailable')
		}
		backlogged := C.errno in [C.EAGAIN, C.EWOULDBLOCK]!
		mut p := BridgePoll{
			fd:     i32(if backlogged { lifetime } else { int(fd) })
			events: i16(if backlogged { C.POLLIN } else { C.POLLOUT })
		}
		if unsafe { C.poll(&C.pollfd(&p), 1, 16) } < 0 && C.errno != C.EINTR {
			return error('account UI window connect poll failed')
		}
		// A failed nonblocking Unix connect can report writable while its
		// backlog stays full. Retry connect, rather than treating POLLOUT alone
		// as a successful connection or resetting the deadline.
	}
	peer := nativeaccountauth.peer_credentials(fd)!
	if peer.uid != C.getuid() { return error('account UI desktop has the wrong owner') }
	connected = true // adopt owns fd on both success and failure.
	return windowfb.adopt(fd)
}

fn send_ready(fd int) ! {
	byte := u8(1)
	flags := $if macos { C.MSG_DONTWAIT } $else { C.MSG_DONTWAIT | C.MSG_NOSIGNAL }
	for {
		n := C.send(fd, &byte, 1, flags)
		if n < 0 && C.errno == C.EINTR { continue }
		if n != 1 { return error('account UI broker did not accept readiness') }
		return
	}
}
