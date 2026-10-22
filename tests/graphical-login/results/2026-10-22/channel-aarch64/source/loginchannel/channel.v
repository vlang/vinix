// SPDX-License-Identifier: GPL-2.0-or-later
// The login screen and compositor borrow only the manager's inherited channel.
module loginchannel

import authclient
import authproto

#include <sys/socket.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/time.h>

fn C.getsockname(int, voidptr, &u32) int
fn C.getsockopt(int, int, int, voidptr, &u32) int
fn C.setsockopt(int, int, int, voidptr, u32) int
fn C.fcntl(fd int, cmd int, arg ...voidptr) int
fn C.poll(fds &C.pollfd, count usize, timeout int) int
fn C.getenv(&char) &char
fn C.strcmp(&char, &char) int

struct C.pollfd {
mut:
	fd      int
	events  i16
	revents i16
}

struct Timeout {
	seconds      i64
	microseconds i64
}

pub const op_login = u16(64)
pub const op_power = u16(65)
pub const op_switch = u16(66)
pub const op_logout = u16(67)
pub const max_name = 48
pub const max_password = 128

// No socket path, descriptor argument or caller-supplied identity is accepted.
// CLOEXEC prevents applications started by the compositor inheriting this
// authority. This process borrows descriptor 3 and never closes another owner.
pub fn inherited() ! {
	// libc owns this value; borrowing avoids an allocated environment copy on
	// every request and reply. The capability is the descriptor, not this flag.
	entry := unsafe { C.getenv(c'VINIX_SESSION_FD') }
	if entry == unsafe { nil } || unsafe { C.strcmp(entry, c'3') } != 0 {
		return error('no session manager channel')
	}
	mut kind := i32(0)
	mut length := u32(sizeof(i32))
	if C.getsockopt(3, C.SOL_SOCKET, C.SO_TYPE, &kind, &length) != 0 || length != sizeof(i32) || kind != C.SOCK_STREAM {
		return error('the session manager channel is not a stream socket')
	}
	mut address := [128]u8{}
	length = u32(address.len)
	if C.getsockname(3, voidptr(&address[0]), &length) != 0 || length < 2 {
		return error('the session manager channel has no local address')
	}
	family := $if macos { u16(address[1]) } $else { u16(address[0]) | (u16(address[1]) << 8) }
	if family != C.AF_UNIX { return error('the session manager channel is not local') }
	authclient.require_root_peer(3)!
	flags := C.fcntl(3, C.F_GETFD)
	if flags < 0 || C.fcntl(3, C.F_SETFD, unsafe { voidptr(flags | C.FD_CLOEXEC) }) != 0 {
		return error('cannot protect the session manager channel from child programs')
	}
	// Once a reply starts arriving, a partial frame cannot freeze the screen.
	limit := Timeout{ seconds: 2 }
	if C.setsockopt(3, C.SOL_SOCKET, C.SO_RCVTIMEO, &limit, u32(sizeof(Timeout))) != 0
		|| C.setsockopt(3, C.SOL_SOCKET, C.SO_SNDTIMEO, &limit, u32(sizeof(Timeout))) != 0 {
		return error('cannot bound the session manager channel')
	}
}

pub fn ready() bool {
	mut wait := C.pollfd{ fd: 3, events: C.POLLIN }
	return C.poll(&wait, 1, 0) > 0
}

// Only the compositor's fixed exec-in-place replacement keeps this capability.
// Every unrelated child inherits FD_CLOEXEC and cannot control the login.
pub fn prepare_replacement() ! {
	inherited()!
	flags := C.fcntl(3, C.F_GETFD)
	if flags < 0 || C.fcntl(3, C.F_SETFD, unsafe { voidptr(flags & ~C.FD_CLOEXEC) }) < 0 {
		return error('cannot preserve the manager channel for the replacement compositor')
	}
}

// A successful send means only that the manager received a request. The
// separate reply remains mandatory, and is never inferred from a UI action.
pub fn login(name []u8, password []u8) ! {
	mut borrowed := authproto.Frame{ fields: [password] }
	defer {
		borrowed.wipe()
		unsafe { borrowed.fields.free() }
	}
	if name.len == 0 || name.len > max_name || password.len == 0 || password.len > max_password {
		return error('enter a login name and password')
	}
	inherited()!
	write_login(3, name, password)!
}

fn write_login(fd int, name []u8, password []u8) ! {
	mut frame := authproto.Frame{ code: op_login, fields: [name, password] }
	defer { unsafe { frame.fields.free() } }
	authproto.write_frame(fd, frame)!
}

pub fn reply() !authproto.Frame {
	inherited()!
	return authproto.read_frame(3)
}

pub fn command(code u16) ! {
	if code != op_switch && code != op_logout { return error('invalid session action') }
	inherited()!
	authproto.write_frame(3, authproto.Frame{ code: code })!
	mut answer := authproto.read_frame(3)!
	defer { answer.close() }
	if answer.code != authproto.status_ok || answer.fields.len != 0 {
		return error('the session manager refused the action')
	}
}

pub fn power(action string) ! {
	if action != 'off' && action != 'restart' { return error('invalid power action') }
	inherited()!
	mut request := authproto.text_frame(op_power, action)
	defer { request.close() }
	authproto.write_frame(3, request)!
	mut answer := authproto.read_frame(3)!
	defer { answer.close() }
	if answer.code != authproto.status_ok || answer.fields.len != 0 {
		return error('the session manager refused the power action')
	}
}
