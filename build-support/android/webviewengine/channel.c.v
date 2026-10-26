// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browseripc
import nativeaccountauth
import os

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <sys/file.h>

struct C.pollfd {
pub mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(&C.pollfd, uint , i32 ) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.fcntl(i32, i32, ...i32) i32
fn C.flock(i32, i32) i32
fn C.umask(u32) u32

struct Packet {
	header  []u8
	payload []u8
mut:
	position int
}

// There is no socket pathname or claimed package identifier. A launcher must
// create this connected socketpair while provisioning one exclusive Unix UID
// per principal, then hand each endpoint to exactly one process.
fn control(fd int) ! {
	if fd < 3 { return error('invalid control descriptor') }
	peer := nativeaccountauth.peer_credentials(fd)!
	if peer.uid != u32(os.getuid()) || peer.gid != u32(os.getgid()) {
		return error('control peer belongs to another principal')
	}
	flags := C.fcntl(i32(fd), C.F_GETFD)
	status := C.fcntl(i32(fd), C.F_GETFL)
	if flags < 0 || status < 0 || C.fcntl(i32(fd), C.F_SETFD, flags | C.FD_CLOEXEC) < 0
		|| C.fcntl(i32(fd), C.F_SETFL, status | C.O_NONBLOCK) < 0 {
		return error('cannot confine control descriptor')
	}
}

fn profile(path string) !string {
	if !path.starts_with('/') || path.contains_any('\x00\n\r') || os.real_path(path) != path {
		return error('profile must be a canonical absolute directory')
	}
	info := os.lstat(path)!
	if info.mode & 0o170000 != 0o040000 || info.mode & 0o7777 != 0o700
		|| info.uid != u32(os.getuid()) {
		return error('profile must be a private directory owned by the engine principal')
	}
	// Every ancestor must protect this directory from rename/replacement. A
	// root-owned sticky /tmp is safe; arbitrary writable ancestors are not.
	mut ancestor := os.dir(path)
	for {
		parent := os.lstat(ancestor)!
		if parent.mode & 0o170000 != 0o040000 || parent.uid !in [u32(0), u32(os.getuid())]
			|| (parent.mode & 0o022 != 0 && !(parent.uid == 0 && parent.mode & 0o1000 != 0)) {
			return error('profile has an unprotected ancestor')
		}
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
	for name in ['data', 'cache'] {
		child := path + '/' + name
		if !os.exists(child) {
			os.mkdir(child)!
			os.chmod(child, 0o700)!
		}
		stat := os.lstat(child)!
		if stat.mode & 0o170000 != 0o040000 || stat.mode & 0o7777 != 0o700
			|| stat.uid != info.uid {
			return error('profile child is not private')
		}
	}
	return path
}

fn private_file(path string) ! {
	if !os.exists(path) && !os.is_link(path) { return }
	stat := os.lstat(path)!
	if stat.mode & 0o170000 != 0o100000 || stat.mode & 0o7777 != 0o600
		|| stat.uid != u32(os.getuid()) || stat.nlink != 1 {
		return error('profile file is not private')
	}
}

// Keep the inode and lock for this process lifetime; unlinking a lock file
// would allow a second engine to lock another inode for the same cookie jar.
fn lock_profile(path string) !int {
	name := path + '/engine.lock'
	private_file(name)!
	fd := C.open(name.str, C.O_CREAT | C.O_RDWR | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot open private profile lock') }
	private_file(name) or {
		C.close(fd)
		return err
	}
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		C.close(fd)
		return error('profile already has an engine')
	}
	return int(fd)
}

fn (mut e Engine) enqueue(h browseripc.Header, payload []u8) {
	if e.closed { return }
	allowed := e.state.receive(h, payload) or {
		e.closed = true
		return
	}
	if !allowed { return }
	header := browseripc.encode_header(h, .engine_to_client) or {
		e.closed = true
		return
	}
	// Drop fresh images under back pressure; preserve ordered completions and
	// policy replies. Bounded output cannot stall GLib or grow without limit.
	if e.queued + header.len + payload.len > 2 * browseripc.max_payload {
		if h.op == .pixels { return }
		e.closed = true
		return
	}
	e.queued += header.len + payload.len
	e.output << Packet{ header: header, payload: payload }
}

fn (mut e Engine) flush() {
	for e.output.len > 0 && !e.closed {
		mut packet := &e.output[0]
		bytes := if packet.position < packet.header.len { packet.header } else { packet.payload }
		offset := if packet.position < packet.header.len {
			packet.position
		} else {
			packet.position - packet.header.len
		}
		if offset == bytes.len {
			e.output.delete(0)
			continue
		}
		n := C.write(i32(e.fd), unsafe { &bytes[offset] }, usize(bytes.len - offset))
		if n < 0 {
			if C.errno == C.EINTR { continue }
			if C.errno == C.EAGAIN || C.errno == C.EWOULDBLOCK { return }
			e.closed = true
			return
		}
		if n == 0 {
			e.closed = true
			return
		}
		packet.position += int(n)
		e.queued -= int(n)
	}
}

fn (mut e Engine) read() {
	// A committed-text query and its insertion form one ordered input action.
	// Do not process another focus/navigation command before its callback.
	if e.closed || e.text_jobs.len > 0 || e.input_pending || e.jobs.len > 0 || e.restore != unsafe { nil } {
		return
	}
	// Bound work per main-context turn, including a stream of tiny messages.
	for _ in 0 .. 16 {
		if e.header_position < browseripc.header_size {
			n := C.read(i32(e.fd), unsafe { &e.header[e.header_position] }, usize(browseripc.header_size - e.header_position))
			if n <= 0 {
				if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR] { return }
				e.closed = true
				return
			}
			e.header_position += int(n)
			if e.header_position != browseripc.header_size { return }
			e.incoming = browseripc.decode_header(e.header, .client_to_engine) or {
				e.closed = true
				return
			}
			e.payload = []u8{len: int(e.incoming.payload_size)}
			e.payload_position = 0
		}
		if e.payload_position < e.payload.len {
			n := C.read(i32(e.fd), unsafe { &e.payload[e.payload_position] }, usize(e.payload.len - e.payload_position))
			if n <= 0 {
				if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR] { return }
				e.closed = true
				return
			}
			e.payload_position += int(n)
			if e.payload_position != e.payload.len { return }
		}
		e.state.submit(e.incoming, e.payload) or {
			e.closed = true
			return
		}
		e.handle(e.incoming, e.payload)
		e.header_position = 0
		if e.closed || e.text_jobs.len > 0 || e.input_pending || e.jobs.len > 0 { return }
	}
}
