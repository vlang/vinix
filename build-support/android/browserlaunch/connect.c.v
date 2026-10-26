// SPDX-License-Identifier: GPL-2.0-or-later
module browserlaunch

import net
import time

#include <sys/un.h>

fn x11_nonblocking(fd i32) ! {
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) != 0 {
		return error('cannot make X11 admission nonblocking')
	}
}

fn x11_wait(fd i32, events i16, deadline u64) ! {
	for {
		now := time.sys_mono_now()
		if now >= deadline { return error('X11 admission deadline expired') }
		remaining := i32((deadline - now + u64(time.millisecond) - 1) / u64(time.millisecond))
		mut ready := C.pollfd{ fd: fd, events: events }
		result := C.poll(&ready, 1, remaining)
		if result < 0 && C.errno == C.EINTR { continue }
		if result <= 0 { return error('X11 admission deadline expired') }
		if ready.revents & (C.POLLERR | C.POLLNVAL) != 0 {
			return error('X11 admission socket failed')
		}
		if ready.revents & events != 0 { return }
		if ready.revents & C.POLLHUP != 0 { return error('X11 admission socket closed') }
	}
}

// Unlike unix.connect_stream, failed attempts always close their descriptor.
// A competing full backlog cannot stall the supervisor's readiness/EOF loop.
fn x11_connect(path string, timeout int) !i32 {
	mut address := C.sockaddr_un{}
	if path.len == 0 || !path.starts_with('/') || path.contains('\x00')
		|| path.len >= address.sun_path.len || timeout < 1 || timeout > 30000 {
		return error('invalid X11 connection path or timeout')
	}
	$if macos {
		address.sun_len = u8(sizeof(C.sockaddr_un))
	}
	address.sun_family = C.AF_UNIX
	for index, byte in path { address.sun_path[index] = char(byte) }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error('cannot create X11 admission socket') }
	mut keep := false
	defer { if !keep { C.close(fd) } }
	cloexec(fd, true)!
	x11_nonblocking(fd)!
	deadline := time.sys_mono_now() + u64(timeout) * u64(time.millisecond)
	if C.connect(fd, voidptr(&address), u32(sizeof(C.sockaddr_un))) != 0 {
		// Linux reports a saturated Unix backlog as EAGAIN. Retrying later is
		// safe; treating it as a connected descriptor would be incorrect.
		if C.errno !in [C.EINPROGRESS, C.EALREADY, C.EINTR] {
			return error('cannot connect to X11 admission socket')
		}
		x11_wait(fd, C.POLLOUT, deadline)!
		mut status := i32(0)
		mut size := u32(sizeof(status))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &status, &size) != 0
			|| size != sizeof(status) || status != 0 {
			return error('X11 admission connection failed')
		}
	}
	keep = true
	return fd
}

// One absolute deadline covers the whole setup request and eight-byte header,
// so a silent or byte-dribbling peer cannot prolong startup indefinitely.
fn x11_exchange(fd i32, request []u8) ![]u8 {
	if request.len == 0 || request.len > 4096 { return error('invalid X11 setup request') }
	x11_nonblocking(fd)!
	$if macos {
		one := i32(1)
		if C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, u32(sizeof(one))) != 0 {
			return error('cannot suppress X11 admission SIGPIPE')
		}
	}
	deadline := time.sys_mono_now() + u64(250 * time.millisecond)
	mut sent := 0
	for sent < request.len {
		if time.sys_mono_now() >= deadline { return error('X11 admission deadline expired') }
		flags := $if linux { i32(C.MSG_NOSIGNAL) } $else { i32(0) }
		n := unsafe { C.send(fd, &request[sent], usize(request.len - sent), flags) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK] {
			x11_wait(fd, C.POLLOUT, deadline)!
			continue
		}
		if n <= 0 { return error('X11 admission write failed') }
		sent += n
	}
	mut header := []u8{len: 8}
	mut used := 0
	for used < header.len {
		if time.sys_mono_now() >= deadline { return error('X11 admission deadline expired') }
		n := unsafe { C.recv(fd, &header[used], uint(header.len - used), 0) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 && C.errno in [C.EAGAIN, C.EWOULDBLOCK] {
			x11_wait(fd, C.POLLIN, deadline)!
			continue
		}
		if n <= 0 { return error('X11 admission header ended early') }
		used += n
	}
	return header
}
