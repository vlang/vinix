// SPDX-License-Identifier: MIT
module windowfb

import os
import net as _

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>

fn C.flock(int, int) int

struct C.pollfd {
	fd      int
	events  i16
	revents i16
}

fn C.poll(&C.pollfd, usize, int) int

// C structs declared by another module may have private fields in V. Use our
// own fixed-width poll layout and cast only at the libc call boundary.
struct PollDescriptor {
mut:
	fd      i32
	events  i16
	revents i16
}

struct Address {
mut:
	prefix [2]u8
	path   [100]u8
}

fn address(path string) !Address {
	mut addr := Address{}
	if path.len == 0 || path.len >= addr.path.len { return error('invalid window socket path') }
	$if macos {
		addr.prefix[0] = u8(sizeof(Address))
		addr.prefix[1] = u8(C.AF_UNIX)
	} $else {
		addr.prefix[0] = u8(C.AF_UNIX)
		addr.prefix[1] = u8(C.AF_UNIX >> 8)
	}
	for i, byte in path { addr.path[i] = byte }
	return addr
}

pub fn runtime_directory() string {
	base := os.getenv_opt('VINIX_SESSION_RUNTIME') or { '/run' }
	defer { unsafe { base.free() } }
	uid := C.getuid().str()
	defer { unsafe { uid.free() } }
	return base + '/vinix-session.' + uid
}

pub fn socket_path() string {
	override := os.getenv('VINIX_WINDOW_SOCKET')
	if override.len > 0 { return override }
	unsafe { override.free() }
	directory := runtime_directory()
	defer { unsafe { directory.free() } }
	return '${directory}/windows'
}

fn setup_fd(fd int) ! {
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) < 0 { return error('cannot protect window descriptor') }
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0 {
		return error('cannot set nonblocking window descriptor')
	}
	$if macos {
		option := i32(1)
		if C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, unsafe { &option }, u32(sizeof(i32))) != 0 {
			return error('cannot configure window socket')
		}
	}
}

pub struct Connection {
pub mut:
	fd int = -1
mut:
	rx     [header_size + max_payload]u8
	used   int
	wanted int = header_size
	tx     [65536]u8
	sent   int
	queued int
}

pub fn adopt(fd int) !&Connection {
	setup_fd(fd) or {
		C.close(fd)
		return err
	}
	return &Connection{ fd: fd }
}

pub fn connect(path string) !&Connection {
	addr := address(path)!
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create window socket') }
	// A local Unix connect completes before switching to nonblocking I/O.
	if C.connect(fd, unsafe { voidptr(&addr) }, u32(sizeof(Address))) != 0 {
		C.close(fd)
		return error('desktop window service is unavailable')
	}
	return adopt(fd)
}

pub fn (mut c Connection) close() {
	if c.fd >= 0 {
		C.close(c.fd)
		c.fd = -1
	}
	c.used = 0
	c.queued = 0
	c.sent = 0
}

pub fn (c &Connection) wants_write() bool { return c.queued > c.sent }

// A slow peer cannot block the compositor or grow its output without bound.
pub fn (mut c Connection) send(m &Message) ! {
	if c.fd < 0 || m.length < 0 || m.length > max_payload { return error('invalid window output') }
	if c.sent > 0 {
		unsafe { C.memmove(&c.tx[0], &c.tx[c.sent], usize(c.queued - c.sent)) }
		c.queued -= c.sent
		c.sent = 0
	}
	if header_size + m.length > c.tx.len - c.queued { return error('window event queue is full') }
	p := unsafe { &c.tx[c.queued] }
	put_u32(p, 0, magic)
	put_u32(p, 4, u32(m.kind))
	put_u32(p, 8, u32(m.x))
	put_u32(p, 12, u32(m.y))
	put_u32(p, 16, u32(m.value))
	put_u32(p, 20, u32(m.length))
	unsafe { C.memcpy(p + header_size, &m.payload[0], usize(m.length)) }
	c.queued += header_size + m.length
	c.flush()!
}

pub fn (mut c Connection) flush() ! {
	for c.sent < c.queued {
		flags := $if macos { 0 } $else { C.MSG_NOSIGNAL }
		n := unsafe { C.send(c.fd, &c.tx[c.sent], usize(c.queued - c.sent), flags) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK]! { return }
		if n <= 0 { return error('window peer disconnected') }
		c.sent += int(n)
	}
	c.sent = 0
	c.queued = 0
}

// false means incomplete/EAGAIN, including a split header or payload.
pub fn (mut c Connection) receive(m &Message) !bool {
	if c.fd < 0 { return error('window connection is closed') }
	for {
		if c.used < c.wanted {
			n := unsafe { C.recv(c.fd, &c.rx[c.used], usize(c.wanted - c.used), 0) }
			if n < 0 && C.errno == C.EINTR { continue }
			if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK]! { return false }
			if n <= 0 { return error('window peer disconnected') }
			c.used += int(n)
			if c.used < c.wanted { continue }
		}
		header := decode_header(&c.rx[0])!
		c.wanted = header_size + header.length
		if c.used < c.wanted { continue }
		unsafe {
			*m = header
			C.memcpy(&m.payload[0], &c.rx[header_size], usize(m.length))
		}
		c.used = 0
		c.wanted = header_size
		return true
	}
}

// The event fd can also be placed directly in poll/select/epoll by the caller.
pub fn (mut c Connection) wait(timeout_ms int) !bool {
	if c.fd < 0 { return error('window connection is closed') }
	mut p := PollDescriptor{ fd: i32(c.fd), events: i16(C.POLLIN | if c.wants_write() {
		C.POLLOUT
	} else {
		0
	}) }
	result := unsafe { C.poll(&C.pollfd(&p), 1, timeout_ms) }
	if result < 0 && C.errno == C.EINTR { return false }
	if result < 0 { return error('window poll failed') }
	if p.revents & C.POLLOUT != 0 { c.flush()! }
	return p.revents & (C.POLLIN | C.POLLHUP | C.POLLERR | C.POLLNVAL) != 0
}

pub struct Listener {
pub mut:
	fd int = -1
mut:
	lock_fd int = -1
	path    string
}

pub fn listen(path string) !Listener {
	addr := address(path)!
	lock_path := path + '.lock'
	defer { unsafe { lock_path.free() } }
	lock_fd := C.open(&char(lock_path.str), C.O_RDWR | C.O_CREAT | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if lock_fd < 0 { return error('cannot lock window socket') }
	if C.flock(lock_fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		C.close(lock_fd)
		return error('window service is already running')
	}
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 {
		C.close(lock_fd)
		return error('cannot create window listener')
	}
	setup_fd(fd) or {
		C.close(fd)
		C.close(lock_fd)
		return err
	}
	C.unlink(&char(path.str))
	if C.bind(fd, unsafe { voidptr(&addr) }, u32(sizeof(Address))) != 0 || C.listen(fd, max_clients) != 0 {
		C.close(fd)
		C.close(lock_fd)
		return error('cannot bind window listener')
	}
	os.chmod(path, 0o600) or {
		C.close(fd)
		C.close(lock_fd)
		C.unlink(&char(path.str))
		return err
	}
	return Listener{ fd: fd, lock_fd: lock_fd, path: path.clone() }
}

pub fn (mut l Listener) accept() ?&Connection {
	fd := C.accept(l.fd, unsafe { nil }, unsafe { nil })
	if fd < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR]! { return none }
	if fd < 0 { return none }
	return adopt(fd) or {
		unsafe { err.free() }
		return none
	}
}

pub fn (mut l Listener) close() {
	if l.fd >= 0 {
		C.close(l.fd)
		C.unlink(&char(l.path.str))
		l.fd = -1
	}
	if l.lock_fd >= 0 {
		C.close(l.lock_fd)
		l.lock_fd = -1
	}
	unsafe { l.path.free() }
	l.path = ''
}
