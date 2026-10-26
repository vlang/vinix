// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import accountipc
import nativeaccountauth
import sync
import time

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

struct ClientPoll {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.socket(i32, i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.poll(voidptr, uint , i32 ) i32
fn C.close(i32) i32

// The producer makes a fresh connection for each request. No account identity
// or credential-bearing option is written before checking the root peer.
@[heap]
pub struct Client {
mut:
	mutex      sync.Mutex
	fd         int = -1
	connecting bool
	verified   bool
	closed     bool
	terminal   bool
	id         u64
	operation  nativeaccountauth.Operation
	request    []u8
	used       int
	started    i64
	stream     &accountipc.Stream = unsafe { nil }
	current    accountipc.Event
}

pub fn submit(request nativeaccountauth.Request, endpoint string) !&Client {
	frame := nativeaccountauth.encode_request(request)!
	mut frame_owned := true
	defer { if frame_owned { unsafe { frame.free() } } }
	if endpoint.len < 2 || endpoint.len > 103 || !endpoint.starts_with('/') || endpoint.contains('\x00') {
		return error('invalid account broker endpoint')
	}
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create account broker socket') }
	mut ok := false
	defer { if !ok { C.close(fd) } }
	flags := C.fcntl(fd, C.F_GETFD)
	status := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || status < 0 || C.fcntl(fd, C.F_SETFD, flags | C.FD_CLOEXEC) != 0
		|| C.fcntl(fd, C.F_SETFL, status | C.O_NONBLOCK) != 0 {
		return error('cannot protect account broker socket')
	}
	$if macos {
		one := i32(1)
		if C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, u32(sizeof(i32))) != 0 {
			return error('cannot suppress account SIGPIPE')
		}
	}
	mut address := C.sockaddr_un{}
	address.sun_family = C.AF_UNIX
	unsafe { C.memcpy(&address.sun_path[0], endpoint.str, uint(endpoint.len)) }
	$if macos {
		address.sun_len = u8(sizeof(C.sockaddr_un))
	}
	connected := C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) == 0
	if !connected && C.errno !in [C.EINPROGRESS, C.EAGAIN, C.EWOULDBLOCK] {
		return error('account broker unavailable')
	}
	ok = true
	frame_owned = false
	return &Client{ fd: int(fd), connecting: !connected, id: request.id,
		operation: request.operation, request: frame, started: time.sys_mono_now() }
}

fn (mut c Client) fail() {
	if c.closed { return }
	c.closed = true
	if c.stream != unsafe { nil } {
		c.stream.close()
	} else if c.fd >= 0 {
		C.close(i32(c.fd))
	}
	c.fd = -1
	unsafe { c.request.free() }
	c.request = []u8{}
}

fn (mut c Client) pump_request() !bool {
	if c.stream != unsafe { nil } { return true }
	if time.sys_mono_now() - c.started > 5 * time.second {
		return error('account broker request deadline expired')
	}
	if c.connecting {
		mut ready := ClientPoll{ fd: i32(c.fd), events: i16(C.POLLOUT) }
		status := C.poll(voidptr(&ready), 1, 0)
		if status < 0 && C.errno == C.EINTR { return false }
		if status < 0 { return error('account broker connect poll failed') }
		if status == 0 { return false }
		mut failure := i32(0)
		mut size := u32(sizeof(i32))
		if C.getsockopt(i32(c.fd), C.SOL_SOCKET, C.SO_ERROR, &failure, &size) != 0 || size != sizeof(i32) || failure != 0 {
			return error('account broker connection failed')
		}
		c.connecting = false
	}
	if !c.verified {
		peer := nativeaccountauth.peer_credentials(c.fd)!
		if peer.uid != 0 || peer.gid != 0 { return error('account broker peer is not root') }
		c.verified = true
	}
	for _ in 0 .. 16 {
		if c.used == c.request.len {
			if C.shutdown(i32(c.fd), C.SHUT_WR) != 0 {
				return error('cannot finish account request')
			}
			c.stream = accountipc.open_stream(c.fd)!
			unsafe { c.request.free() }
			c.request = []u8{}
			return true
		}
		mut flags := i32(C.MSG_DONTWAIT)
		$if linux {
			flags |= C.MSG_NOSIGNAL
		}
		n := unsafe { C.send(i32(c.fd), &c.request[c.used], uint(c.request.len - c.used), flags) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK] { return false }
		if n <= 0 { return error('account broker request disconnected') }
		c.used += int(n)
	}
	return false
}

// Callers serialize read plus copying borrowed getters before invoking Java.
// timeout=0 never waits for the server or blocks Android's main Looper.
pub fn (mut c Client) read(timeout int) !bool {
	c.mutex.lock()
	defer { c.mutex.unlock() }
	if c.terminal { return false }
	if c.closed || timeout < 0 || timeout > 1000 { return error('account client unavailable') }
	if !c.pump_request() or {
		c.fail()
		return err
	} {
		return false
	}
	packet := c.stream.read(timeout) or {
		c.fail()
		return err
	}
	if !packet.available { return false }
	defer { unsafe { packet.body.free() } }
	event := accountipc.decode_event(packet.header, packet.body, false) or {
		c.fail()
		return err
	}
	if event.id != c.id || event.kind !in [.result, .failure, .accounts, .interaction, .continued, .authenticators]
		|| (event.kind == .authenticators && c.operation != .get_authenticator_types)
		|| (c.operation == .get_authenticator_types && event.kind !in [.authenticators, .failure]) {
		accountipc.dispose_event(event)
		c.fail()
		return error('account broker returned an unrelated event')
	}
	accountipc.dispose_event(c.current)
	c.current = event
	if accountipc.terminal(event.kind) {
		c.terminal = true
		c.fail()
	}
	return true
}

pub fn (mut c Client) close() {
	c.mutex.lock()
	defer { c.mutex.unlock() }
	c.fail()
	if c.stream != unsafe { nil } {
		unsafe { free(c.stream) }
		c.stream = unsafe { nil }
	}
	accountipc.dispose_event(c.current)
	c.current = accountipc.Event{}
}
