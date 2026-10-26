// SPDX-License-Identifier: GPL-2.0-or-later
module accountipc

import nativeaccountauth
import time

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

struct Poll {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(voidptr, uint , i32 ) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.close(i32) i32

pub struct Packet {
pub:
	available bool
	header    Header
	body      []u8
}

// One owner serializes this connection. It takes ownership of fd only after
// successful construction. The caller establishes root or registry authority
// before construction; this helper only enforces the connected Unix boundary.
@[heap]
pub struct Stream {
mut:
	fd            int
	closed        bool
	header        []u8 = []u8{len: header_size}
	header_used   int
	current       Header
	body          []u8
	body_used     int
	started       i64
	queue         [][]u8
	queue_size    int
	write_used    int
	write_started i64
}

pub fn open_stream(fd int) !&Stream {
	nativeaccountauth.peer_credentials(fd)!
	flags := C.fcntl(i32(fd), C.F_GETFD)
	status := C.fcntl(i32(fd), C.F_GETFL)
	if flags < 0 || status < 0 || C.fcntl(i32(fd), C.F_SETFD, flags | C.FD_CLOEXEC) != 0
		|| C.fcntl(i32(fd), C.F_SETFL, status | C.O_NONBLOCK) != 0 {
		return error('cannot protect account stream')
	}
	$if macos {
		one := i32(1)
		if C.setsockopt(i32(fd), C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, u32(sizeof(i32))) != 0 {
			return error('cannot suppress account stream SIGPIPE')
		}
	}
	return &Stream{ fd: fd }
}

pub fn (mut s Stream) enqueue(bytes []u8) ! {
	if s.closed || bytes.len < header_size || bytes.len > header_size + max_payload || s.queue.len >= 64
		|| s.queue_size + bytes.len > 4 * 1024 * 1024 {
		return error('account output queue unavailable')
	}
	header := decode_header(bytes[..header_size])!
	if bytes.len != header_size + header.length { return error('invalid queued account frame') }
	if s.queue.len == 0 { s.write_started = time.sys_mono_now() }
	s.queue << bytes.clone()
	s.queue_size += bytes.len
}

pub fn (mut s Stream) flush() ! {
	mut calls := 0
	for s.queue.len > 0 && calls < 16 {
		if time.sys_mono_now() - s.write_started > 10 * time.second {
			return error('account output deadline expired')
		}
		bytes := s.queue[0]
		mut flags := i32(C.MSG_DONTWAIT)
		$if linux {
			flags |= C.MSG_NOSIGNAL
		}
		n := unsafe { C.send(i32(s.fd), &bytes[s.write_used], uint(bytes.len - s.write_used), flags) }
		calls++
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK] { return }
		if n <= 0 { return error('account output disconnected') }
		s.write_used += int(n)
		if s.write_used == bytes.len {
			s.queue_size -= bytes.len
			unsafe { bytes.free() }
			s.queue.delete(0)
			s.write_used = 0
			s.write_started = time.sys_mono_now()
		}
	}
}

pub fn (s &Stream) pending_output() bool { return s.queue.len > 0 }

fn (mut s Stream) pump_read() !Packet {
	for _ in 0 .. 16 {
		if s.started != 0 && time.sys_mono_now() - s.started > 10 * time.second {
			return error('account input deadline expired')
		}
		reading_header := s.header_used < header_size
		mut buffer := if reading_header {
			&s.header[s.header_used]
		} else if s.body_used < s.body.len {
			&s.body[s.body_used]
		} else {
			unsafe { nil }
		}
		if buffer == unsafe { nil } {
			packet := Packet{true, s.current, s.body}
			s.body = []u8{}
			s.body_used = 0
			s.header_used = 0
			s.started = 0
			return packet
		}
		length := if reading_header {
			header_size - s.header_used
		} else {
			s.body.len - s.body_used
		}
		n := unsafe { C.recv(i32(s.fd), buffer, uint(length), C.MSG_DONTWAIT) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK] { return Packet{} }
		if n <= 0 { return error('account input disconnected') }
		if s.started == 0 { s.started = time.sys_mono_now() }
		if reading_header {
			s.header_used += int(n)
			if s.header_used == header_size {
				s.current = decode_header(s.header)!
				s.body = []u8{len: s.current.length}
			}
		} else {
			s.body_used += int(n)
		}
	}
	return Packet{}
}

// timeout=0 performs only bounded nonblocking work, for Android's main Looper.
// A partial frame's monotonic deadline spans repeated calls and EINTR.
pub fn (mut s Stream) read(timeout int) !Packet {
	if s.closed || timeout < 0 || timeout > 1000 { return error('account stream unavailable') }
	s.flush() or {
		s.close()
		return err
	}
	packet := s.pump_read() or {
		s.close()
		return err
	}
	if packet.available || timeout == 0 { return packet }
	mut ready := Poll{
		fd:     i32(s.fd)
		events: i16(C.POLLIN | if s.queue.len > 0 {
			C.POLLOUT
		} else {
			0
		})
	}
	status := C.poll(voidptr(&ready), 1, i32(timeout))
	if status < 0 && C.errno != C.EINTR {
		s.close()
		return error('account stream poll failed')
	}
	s.flush() or {
		s.close()
		return err
	}
	return s.pump_read() or {
		s.close()
		return err
	}
}

pub fn (mut s Stream) close() {
	if s.closed { return }
	s.closed = true
	C.close(i32(s.fd))
	s.fd = -1
	unsafe {
		s.header.free()
		s.body.free()
	}
	for bytes in s.queue {
		unsafe { bytes.free() }
	}
	unsafe { s.queue.free() }
	s.queue = [][]u8{}
	s.queue_size = 0
}
