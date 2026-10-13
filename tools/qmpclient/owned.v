// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import net
import net.unix
import os
import time

// The SDK's connect_stream leaves its socket open when connect fails. Retain
// this descriptor until connection succeeds and the monitor takes ownership.
fn owned_connection(path string, deadline u64, cancel fn () bool) !&unix.StreamConn {
	limit := $if macos { 104 } $else { 108 }
	if path.len >= limit || path.contains('\x00') { return error('invalid Unix socket path') }
	if cancel != unsafe { nil } && cancel() { return error('QMP interrupted') }
	addresses := net.resolve_addrs(path, .unix, .tcp)!
	address := addresses[0]
	mut fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return os.error_posix() }
	mut transferred := false
	defer { if !transferred { C.close(fd) } }
	if fd < 3 {
		moved := C.fcntl(fd, C.F_DUPFD_CLOEXEC, 3)
		if moved < 0 { return os.error_posix() }
		C.close(fd)
		fd = moved
	}
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) != 0 {
		return os.error_posix()
	}
	if C.connect(fd, voidptr(&address), address.len()) != 0 {
		if C.errno !in [C.EINPROGRESS, C.EAGAIN, C.EWOULDBLOCK, C.EINTR] { return os.error_posix() }
		mut descriptor := C.pollfd{ fd: fd, events: i16(C.POLLOUT) }
		for {
			if cancel != unsafe { nil } && cancel() { return error('QMP interrupted') }
			if deadline != 0 && u64(time.sys_mono_now()) >= deadline {
				return error('QMP deadline expired')
			}
			count := C.poll(&descriptor, 1, 50)
			if count < 0 {
				if C.errno == C.EINTR { continue }
				return os.error_posix()
			}
			if count == 0 { continue }
			mut status := i32(0)
			mut length := u32(sizeof(i32))
			if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &status, &length) != 0 {
				return os.error_posix()
			}
			if status != 0 { return error_with_code(os.get_error_msg(int(status)), int(status)) }
			break
		}
	}
	mut connection := &unix.StreamConn{ sock: *unix.stream_socket_from_handle(int(fd))! }
	transferred = true
	return connection
}
