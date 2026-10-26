// SPDX-License-Identifier: GPL-2.0-or-later
// Root-owned UI descriptors, carried separately from the account byte stream.
module accountuifd

import nativeaccountauth
import os
import time

#flag linux -D_GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>

$if linux {
	#include <sys/prctl.h>
}

struct C.iovec {
mut:
	iov_base voidptr
	iov_len  usize
}

struct C.msghdr {
mut:
	msg_name       voidptr
	msg_namelen    u32
	msg_iov        &C.iovec
	msg_iovlen     usize
	msg_control    voidptr
	msg_controllen usize
	msg_flags      int
}

struct C.cmsghdr {
mut:
	cmsg_len   usize
	cmsg_level int
	cmsg_type  int
}

fn C.CMSG_SPACE(usize) usize
fn C.CMSG_LEN(usize) usize
fn C.CMSG_FIRSTHDR(&C.msghdr) &C.cmsghdr
fn C.CMSG_DATA(&C.cmsghdr) &u8
fn C.sendmsg(int, &C.msghdr, int) isize
fn C.memfd_create(&u8, u32) int
fn C.ftruncate(int, u64) int
fn C.pwrite(int, voidptr, usize, i64) isize
fn C.pipe(&i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.fcntl(int, int, ...int) int
fn C.close(int) int
fn C.recv(i32, voidptr, uint , i32 ) i32
fn C.fork() int
fn C.setsid() int
fn C.setgroups(usize, voidptr) int
fn C.setresgid(u32, u32, u32) int
fn C.setresuid(u32, u32, u32) int
fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() i32
fn C.getegid() i32
fn C.prctl(int, u64, u64, u64, u64) int
fn C.sysconf(int) i64
fn C.syscall(i64, ...voidptr) i64
fn C.chdir(&u8) int
fn C.execve(&char, &&char, &&char) int
fn C._exit(int)
fn C.kill(int, int) int
fn C.waitpid(i32, &i32, i32) i32

pub struct Config {
pub:
	helper        string
	window_socket string
	uid           u32
	gid           u32
	width         u32 = 480
	height        u32 = 640
}

pub struct Tick {
pub:
	ready   bool
	ended   bool
	session u64
}

@[heap]
pub struct Controller {
	fd     int
	config Config
mut:
	session    u64
	capability []u8
	pid        int = -1
	lifetime   int = -1
	surface    int = -1
	input      int = -1
	deadline   i64
	pending    bool
	used       bool
	closed     bool
}

fn protect(fd int, inherited bool) ! {
	flags := C.fcntl(fd, C.F_GETFD)
	if flags < 0 || C.fcntl(fd, C.F_SETFD, if inherited {
		flags & ~C.FD_CLOEXEC
	} else {
		flags | C.FD_CLOEXEC
	}) != 0 {
		return error('cannot protect UI descriptor')
	}
}

// The helper and native launcher reserve 0..2 for standard streams. Transfer
// ownership to the replacement only after duplication succeeds.
fn above_stdio(fd int) !int {
	if fd >= 3 {
		protect(fd, false)!
		return fd
	}
	replacement := C.fcntl(fd, C.F_DUPFD_CLOEXEC, 3)
	if replacement < 3 { return error('cannot normalize UI descriptor') }
	C.close(fd)
	return replacement
}

// Both endpoints are close-on-exec, above the standard streams, and owned by
// the caller. Used for the independent root-created UI and lifetime channels.
pub fn socket_pair() ![2]i32 {
	mut pair := [i32(-1), i32(-1)]!
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) != 0 {
		return error('cannot create root control socket pair')
	}
	mut ok := false
	defer {
		if !ok {
			C.close(pair[0])
			C.close(pair[1])
		}
	}
	pair[0] = i32(above_stdio(pair[0])!)
	pair[1] = i32(above_stdio(pair[1])!)
	ok = true
	return pair
}

fn wait_helper(pid int, status &i32, flags int) int {
	for {
		result := C.waitpid(i32(pid), status, i32(flags))
		if result < 0 && C.errno == C.EINTR { continue }
		return result
	}
}

// Takes ownership of the dedicated root-created control endpoint on success.
pub fn create(fd int, config Config) !&Controller {
	if C.getuid() != 0 || C.geteuid() != 0 || fd < 3 {
		return error('UI provisioning requires root')
	}
	if !os.is_abs_path(config.helper) || !os.is_abs_path(config.window_socket)
		|| config.helper.contains('\x00') || config.window_socket.contains('\x00')
		|| config.window_socket.len > 100 || config.width < 64 || config.width > 4096
		|| config.height < 64 || config.height > 4096 {
		return error('invalid administrator UI configuration')
	}
	// Service identity is separately authenticated by the broker. A pair made
	// while root is only authority for this dedicated UI-control endpoint.
	peer := nativeaccountauth.peer_credentials(fd)!
	if peer.uid != 0 || peer.gid != 0 {
		return error('UI control endpoint must have a root-created peer')
	}
	protect(fd, false)!
	return &Controller{
		fd:     fd
		config: Config{
			helper:        config.helper.clone()
			window_socket: config.window_socket.clone()
			uid:           config.uid
			gid:           config.gid
			width:         config.width
			height:        config.height
		}
	}
}

fn put16(mut bytes []u8, offset int, value u16) {
	bytes[offset] = u8(value >> 8)
	bytes[offset + 1] = u8(value)
}

fn put32(mut bytes []u8, offset int, value u32) {
	for index in 0 .. 4 { bytes[offset + index] = u8(value >> (24 - index * 8)) }
}

fn put64(mut bytes []u8, offset int, value u64) {
	for index in 0 .. 8 { bytes[offset + index] = u8(value >> (56 - index * 8)) }
}

fn frame(session u64, capability []u8, width u32, height u32) ![]u8 {
	if session == 0 || capability.len != 32 || capability.all(it == 0)
		|| width < 64 || width > 4096 || height < 64 || height > 4096 {
		return error('invalid UI session capability or geometry')
	}
	mut bytes := []u8{len: 64}
	bytes[0] = `W`
	bytes[1] = `S`
	bytes[2] = `U`
	bytes[3] = `I`
	put16(mut bytes, 4, 1)
	put64(mut bytes, 8, session)
	for index, byte in capability { bytes[16 + index] = byte }
	put32(mut bytes, 48, width)
	put32(mut bytes, 52, height)
	put32(mut bytes, 56, width * 4)
	return bytes
}

fn send_descriptors(fd int, bytes []u8, surface int, input int) ! {
	if bytes.len != 64 || surface < 0 || input < 0 || surface == input {
		return error('invalid UI descriptor frame')
	}
	mut iov := C.iovec{ iov_base: bytes.data, iov_len: usize(bytes.len) }
	mut control := [8]u64{}
	mut message := C.msghdr{
		msg_iov:        &iov
		msg_iovlen:     1
		msg_control:    unsafe { &control[0] }
		msg_controllen: C.CMSG_SPACE(2 * sizeof(i32))
	}
	mut header := C.CMSG_FIRSTHDR(&message)
	if header == unsafe { nil } || message.msg_controllen > sizeof(control) {
		return error('unsupported UI ancillary ABI')
	}
	header.cmsg_len = C.CMSG_LEN(2 * sizeof(i32))
	header.cmsg_level = C.SOL_SOCKET
	header.cmsg_type = C.SCM_RIGHTS
	descriptors := [i32(surface), i32(input)]!
	unsafe { C.memcpy(C.CMSG_DATA(header), &descriptors[0], 2 * sizeof(i32)) }
	mut flags := int(C.MSG_DONTWAIT)
	$if linux {
		flags |= C.MSG_NOSIGNAL
	}
	$if macos {
		one := 1
		if C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, u32(sizeof(int))) != 0 {
			return error('cannot protect UI send')
		}
	}
	for {
		sent := C.sendmsg(fd, &message, flags)
		if sent < 0 && C.errno == C.EINTR { continue }
		// Short ancillary writes cannot safely be retried. This channel is single use.
		if sent != bytes.len { return error('cannot deliver complete UI descriptor frame') }
		return
	}
}

fn sealed_surface(width u32, height u32) !int {
	$if linux {
		mut fd := C.memfd_create(c'account-ui-surface', 1 | 2)
		if fd < 0 { return error('cannot create UI surface memfd') }
		mut ok := false
		defer { if !ok { C.close(fd) } }
		fd = above_stdio(fd)!
		size := u64(48) + u64(width) * u64(height) * 8
		if C.ftruncate(fd, size) != 0 { return error('cannot size UI surface') }
		header := [u32(0x31534656), u32(1), u32(48), width, height, width * 4, u32(1), u32(0),
			u32(0xffffffff), u32(0), width * height * 4, u32(0)]!
		if C.pwrite(fd, &header[0], sizeof(header), 0) != sizeof(header)
			|| C.fcntl(fd, 1033, 6) != 0 || C.fcntl(fd, 1034) & 6 != 6 {
			return error('cannot initialize and seal UI surface size')
		}
		ok = true
		return fd
	} $else {
		return error('UI surface provisioning requires Linux memfd seals')
	}
}

// Single-use attachment: the VM retains its surface mapping to process exit.
pub fn (mut c Controller) begin(session u64, capability []u8) ! {
	if c.closed || c.used || c.session != 0 {
		return error('authenticator UI attachment is unavailable')
	}
	bytes := frame(session, capability, c.config.width, c.config.height)!
	unsafe { bytes.free() }
	surface := sealed_surface(c.config.width, c.config.height)!
	mut surface_owned := true
	defer { if surface_owned { C.close(surface) } }
	mut pipe := [i32(-1), i32(-1)]!
	if C.pipe(&pipe[0]) != 0 { return error('cannot create UI input pipe') }
	mut read_owned, write_owned := true, true
	defer {
		if read_owned { C.close(pipe[0]) }
		if write_owned { C.close(pipe[1]) }
	}
	pipe[0] = i32(above_stdio(pipe[0])!)
	pipe[1] = i32(above_stdio(pipe[1])!)
	life := socket_pair()!
	mut root_owned, child_owned := true, true
	defer {
		if root_owned { C.close(life[0]) }
		if child_owned { C.close(life[1]) }
	}
	for fd in [surface, pipe[0], pipe[1], life[0], life[1]] { protect(fd, false)! }
	pid := c.start_helper(surface, pipe[1], life[1])!
	C.close(pipe[1])
	write_owned = false
	C.close(life[1])
	child_owned = false
	c.pid = pid
	c.lifetime = life[0]
	root_owned = false
	c.surface = surface
	surface_owned = false
	c.input = pipe[0]
	read_owned = false
	c.session = session
	c.capability = capability.clone()
	c.deadline = time.sys_mono_now() + 5 * time.second
	c.pending = true
	c.used = true
}

fn (c &Controller) start_helper(surface int, input int, lifetime int) !int {
	args := [c.config.helper, '--surface-fd', surface.str(), '--input-fd', input.str(), '--lifetime-fd',
		lifetime.str(), '--window-socket', c.config.window_socket]
	mut argv := []&char{cap: args.len + 1}
	defer {
		unsafe {
			argv.free()
			args[2].free()
			args[4].free()
			args[6].free()
			args.free()
		}
	}
	for arg in args { argv << &char(arg.str) }
	argv << unsafe { &char(nil) }
	environment := [c'PATH=/usr/bin:/bin', c'HOME=/', c'LANG=C', unsafe { &char(nil) }]!
	limit := C.sysconf(C._SC_OPEN_MAX)
	if limit < 0 || limit > 1048576 { return error('cannot bound UI helper descriptor cleanup') }
	pid := C.fork()
	if pid < 0 { return error('cannot fork UI helper') }
	if pid == 0 {
		// Only libc calls and stack values after fork. Closing opposite endpoints
		// here ensures lifetime and input EOF are observable by their recipients.
		mut covered := false
		$if linux {
			covered = C.syscall(436, voidptr(3), voidptr(0xffffffff), voidptr(4)) == 0
		}
		if !covered {
			for fd := 3; i64(fd) < limit; fd++ {
				if fd != surface && fd != input && fd != lifetime { C.close(fd) }
			}
		}
		if C.fcntl(surface, C.F_SETFD, 0) != 0 || C.fcntl(input, C.F_SETFD, 0) != 0
			|| C.fcntl(lifetime, C.F_SETFD, 0) != 0 || C.setsid() < 0 || C.chdir(c'/') != 0 {
			C._exit(125)
		}
		$if linux {
			if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(c.config.gid, c.config.gid, c.config.gid) != 0
				|| C.setresuid(c.config.uid, c.config.uid, c.config.uid) != 0
				|| C.getuid() != c.config.uid || C.geteuid() != c.config.uid
				|| C.getgid() != c.config.gid || C.getegid() != c.config.gid
				|| C.prctl(38, 1, 0, 0, 0) != 0 {
				C._exit(125)
			}
		} $else {
			C._exit(125)
		}
		C.execve(&char(c.config.helper.str), argv.data, &&char(&environment[0]))
		C._exit(126)
	}
	return pid
}

// Nonblocking readiness leaves other account requests and callbacks moving.
pub fn (mut c Controller) tick() !Tick {
	if c.closed || c.pid <= 0 { return Tick{} }
	mut status := i32(0)
	reaped := wait_helper(c.pid, &status, C.WNOHANG)
	if reaped == c.pid {
		c.pid = -1
		return Tick{ ended: c.session != 0, session: c.session }
	}
	if reaped < 0 { return error('cannot observe UI helper') }
	if c.session == 0 {
		if time.sys_mono_now() >= c.deadline { C.kill(c.pid, C.SIGKILL) }
		return Tick{}
	}
	if !c.pending {
		mut extra := u8(0)
		n := C.recv(c.lifetime, &extra, 1, C.MSG_PEEK | C.MSG_DONTWAIT)
		if n == 0 { return Tick{ ended: true, session: c.session } }
		if n > 0 || C.errno !in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR]! {
			return error('invalid UI helper lifetime output')
		}
		return Tick{}
	}
	if time.sys_mono_now() >= c.deadline { return error('UI helper readiness deadline expired') }
	mut byte := u8(0)
	count := C.recv(c.lifetime, &byte, 1, C.MSG_DONTWAIT)
	if count < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR]! { return Tick{} }
	if count != 1 || byte != 1 { return error('invalid UI helper readiness') }
	bytes := frame(c.session, c.capability, c.config.width, c.config.height)!
	defer { unsafe { bytes.free() } }
	send_descriptors(c.fd, bytes, c.surface, c.input)!
	C.close(c.surface)
	c.surface = -1
	C.close(c.input)
	c.input = -1
	c.pending = false
	return Tick{ ready: true, session: c.session }
}

pub fn (c &Controller) active_session() u64 { return c.session }

pub fn (mut c Controller) end(session u64) {
	if session == 0 || session != c.session { return }
	if c.lifetime >= 0 {
		C.close(c.lifetime)
		c.lifetime = -1
	}
	if c.surface >= 0 {
		C.close(c.surface)
		c.surface = -1
	}
	if c.input >= 0 {
		C.close(c.input)
		c.input = -1
	}
	unsafe { c.capability.free() }
	c.capability = []u8{}
	c.session = 0
	c.pending = false
	c.deadline = time.sys_mono_now() + 3 * time.second
	// Helper closes its input writer after lifetime EOF; service input then gets
	// FIFO EOF and destroys UI activities while its headless service stays alive.
}

pub fn (mut c Controller) close() {
	if c.closed { return }
	c.end(c.session)
	c.closed = true
	C.close(c.fd)
	if c.pid > 0 {
		mut status := i32(0)
		if wait_helper(c.pid, &status, C.WNOHANG) == 0 {
			C.kill(c.pid, C.SIGKILL)
			wait_helper(c.pid, &status, 0)
		}
		c.pid = -1
	}
	unsafe {
		c.config.helper.free()
		c.config.window_socket.free()
	}
}
