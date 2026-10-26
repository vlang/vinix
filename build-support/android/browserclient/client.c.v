// SPDX-License-Identifier: GPL-2.0-or-later
module browserclient

import browseripc
import nativeaccountauth
import sync
import time

#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

struct C.pollfd {
pub mut:
	fd      i32
	events  i16
	revents i16
}

fn C.fcntl(i32, i32, ...i32) i32
fn C.poll(&C.pollfd, uint , i32 ) i32
fn C.getuid() u32

const queue_limit = 64
const queue_bytes_limit = 32 * 1024 * 1024
const frame_timeout = 10000

pub struct Event {
pub:
	available bool
	header    browseripc.Header
	payload   []u8
}

// All I/O is serialized. JNI cookie calls may run on another thread; only the
// Android main Looper consumes unsolicited events and invokes Java callbacks.
@[heap]
pub struct Client {
mut:
	mutex           sync.Mutex
	fd              int
	state           browseripc.State
	request         u64
	closed          bool
	disposed        bool
	header_bytes    []u8 = []u8{len: browseripc.header_size}
	header_used     int
	header          browseripc.Header
	reading_payload bool
	payload         []u8
	payload_used    int
	frame_started   i64
	queue           []Event
	queue_bytes     int
	current         Event
}

pub fn open(fd int) !&Client {
	peer := nativeaccountauth.peer_credentials(fd)!
	if peer.uid != C.getuid() { return error('browser peer identity mismatch') }
	$if macos {
		one := 1
		if C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, sizeof(int)) != 0 {
			return error('cannot protect browser socket writes')
		}
	}
	flags := C.fcntl(i32(fd), C.F_GETFD)
	status := C.fcntl(i32(fd), C.F_GETFL)
	if flags < 0 || status < 0 || C.fcntl(i32(fd), C.F_SETFD, flags | C.FD_CLOEXEC) != 0
		|| C.fcntl(i32(fd), C.F_SETFL, status | C.O_NONBLOCK) != 0 {
		return error('cannot protect browser descriptor')
	}
	return &Client{ fd: fd }
}

fn ready(fd int, events i16, timeout int) !bool {
	mut watched := C.pollfd{ fd: fd, events: events }
	deadline := time.sys_mono_now() / 1000000 + timeout
	for {
		remaining := deadline - time.sys_mono_now() / 1000000
		result := C.poll(&watched, 1, if remaining > 0 { int(remaining) } else { 0 })
		if result < 0 {
			if C.errno == C.EINTR { continue }
			return error('browser descriptor poll failed')
		}
		if result == 0 { return false }
		// A readable EOF is consumed by recv, including POLLIN|POLLHUP.
		if watched.revents & events != 0 { return true }
		return error('browser channel disconnected')
	}
	return false
}

fn write_all(fd int, bytes []u8) ! {
	deadline := time.sys_mono_now() / 1000000 + 5000
	mut used := 0
	for used < bytes.len {
		remaining := deadline - time.sys_mono_now() / 1000000
		if remaining <= 0 || !ready(fd, i16(C.POLLOUT), int(remaining))! {
			return error('browser command write timeout')
		}
		mut flags := 0
		$if linux {
			flags = C.MSG_NOSIGNAL
		}
		n := unsafe { C.send(fd, &u8(bytes.data) + used, usize(bytes.len - used), flags) }
		if n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
		if n <= 0 { return error('browser command write failed') }
		used += int(n)
	}
}

fn (mut c Client) fail() {
	if c.closed { return }
	c.closed = true
	c.state.close()
	C.close(c.fd)
	c.fd = -1
	unsafe { c.payload.free() }
	c.payload = []u8{}
	for event in c.queue {
		unsafe { event.payload.free() }
	}
	c.queue.clear()
	c.queue_bytes = 0
}

pub fn (mut c Client) submit(op browseripc.Op, view u64, generation u64, navigation u64, payload []u8) !u64 {
	c.mutex.lock()
	defer { c.mutex.unlock() }
	if c.closed || c.request == ~u64(0) { return error('browser channel closed') }
	h := browseripc.Header{
		op:           op
		request:      c.request + 1
		view:         view
		generation:   generation
		navigation:   navigation
		payload_size: u32(payload.len)
	}
	bytes := browseripc.encode_header(h, .client_to_engine)!
	defer { unsafe { bytes.free() } }
	c.state.submit(h, payload)!
	c.request = h.request
	write_all(c.fd, bytes) or {
		c.fail()
		return err
	}
	write_all(c.fd, payload) or {
		c.fail()
		return err
	}
	return h.request
}

// Receive a single complete frame without ever blocking on a partial read.
// Allocation follows header validation; a stalled partial frame expires.
fn (mut c Client) receive(timeout int) !Event {
	deadline := time.sys_mono_now() / 1000000 + timeout
	for {
		now := time.sys_mono_now() / 1000000
		if c.frame_started != 0 && now - c.frame_started >= frame_timeout {
			return error('browser frame timed out')
		}
		mut remaining := if deadline > now { int(deadline - now) } else { 0 }
		if c.frame_started != 0 && remaining > frame_timeout - int(now - c.frame_started) {
			remaining = frame_timeout - int(now - c.frame_started)
		}
		if !ready(c.fd, i16(C.POLLIN), remaining)! {
			if c.frame_started != 0 && time.sys_mono_now() / 1000000 - c.frame_started >= frame_timeout {
				return error('browser frame timed out')
			}
			return Event{}
		}
		if c.frame_started == 0 { c.frame_started = now }
		if !c.reading_payload {
			n := unsafe {
				C.recv(c.fd, &u8(c.header_bytes.data) + c.header_used,
					usize(browseripc.header_size - c.header_used), 0)
			}
			if n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
			if n <= 0 { return error('browser header disconnected') }
			c.header_used += int(n)
			if c.header_used < browseripc.header_size { continue }
			c.header = browseripc.decode_header(c.header_bytes, .engine_to_client)!
			c.payload = []u8{len: int(c.header.payload_size)}
			c.reading_payload = true
		}
		if c.payload_used < c.payload.len {
			n := unsafe {
				C.recv(c.fd, &u8(c.payload.data) + c.payload_used,
					usize(c.payload.len - c.payload_used), 0)
			}
			if n < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
			if n <= 0 { return error('browser payload disconnected') }
			c.payload_used += int(n)
			if c.payload_used < c.payload.len { continue }
		}
		event := Event{ available: true, header: c.header, payload: c.payload }
		c.payload = []u8{}
		c.header_used = 0
		c.payload_used = 0
		c.reading_payload = false
		c.frame_started = 0
		accepted := c.state.receive(event.header, event.payload) or {
			unsafe { event.payload.free() }
			return err
		}
		if accepted { return event }
		unsafe { event.payload.free() }
		if time.sys_mono_now() / 1000000 >= deadline { return Event{} }
	}
	return Event{}
}

// request=0 delivers queued callbacks in engine order. A synchronous cookie
// operation waits for its own completion and leaves other callbacks queued.
fn completion(event Event, request u64) bool {
	// Policy IDs are allocated by the helper and may numerically equal a
	// client request ID. They are callbacks, never command completions.
	return event.header.request == request && event.header.op in [.ack, .cookie_result, .failure]
}

pub fn (mut c Client) read(request u64, timeout int) !Event {
	c.mutex.lock()
	defer { c.mutex.unlock() }
	if c.closed { return error('browser channel closed') }
	if timeout < 0 || timeout > 30000 { return error('invalid browser read timeout') }
	for i, event in c.queue {
		if request == 0 || completion(event, request) {
			c.queue.delete(i)
			c.queue_bytes -= event.payload.len
			return event
		}
	}
	deadline := time.sys_mono_now() / 1000000 + timeout
	for _ in 0 .. queue_limit {
		remaining := deadline - time.sys_mono_now() / 1000000
		event := c.receive(if remaining > 0 { int(remaining) } else { 0 }) or {
			c.fail()
			return err
		}
		if !event.available {
			if request != 0 {
				c.fail()
				return error('browser completion timed out')
			}
			return Event{}
		}
		if request == 0 || completion(event, request) { return event }
		if c.queue.len >= queue_limit || c.queue_bytes + event.payload.len > queue_bytes_limit {
			unsafe { event.payload.free() }
			c.fail()
			return error('browser callback queue limit')
		}
		c.queue << event
		c.queue_bytes += event.payload.len
		if time.sys_mono_now() / 1000000 >= deadline {
			if request != 0 {
				c.fail()
				return error('browser completion timed out')
			}
			return Event{}
		}
	}
	if request != 0 {
		c.fail()
		return error('browser callback batch limit')
	}
	return Event{}
}

pub fn (mut c Client) close() {
	c.mutex.lock()
	defer { c.mutex.unlock() }
	if c.disposed { return }
	c.fail()
	c.disposed = true
	c.state.dispose()
	unsafe {
		c.current.payload.free()
		c.header_bytes.free()
		c.queue.free()
	}
	c.current = Event{}
	c.header_bytes = []u8{}
	c.queue = []Event{}
}
