// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import cachecli
import hosttest
import json2
import net.unix as _
import os
import time

#include <poll.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
struct C.sockaddr_un {
mut:
	sun_len    u8
	sun_family u16
	sun_path   [108]char
}

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(&C.pollfd, usize, i32) i32

pub struct Monitor {
mut:
	descriptor   int = -1
	deadline     u64
	idle_timeout u64
	cancel       fn (voidptr) bool = unsafe { nil }
	context      voidptr
}

pub fn connect_monitor(path string, timeout f64) !Monitor {
	return connect_cancelled(path, timeout, unsafe { nil }, unsafe { nil })
}

fn connect_cancelled(path string, timeout f64, cancel fn (voidptr) bool, context voidptr) !Monitor {
	if path.len >= 104 || path.contains('\x00') {
		return error('invalid or too long QMP socket path')
	}
	mut address := C.sockaddr_un{}
	address.sun_family = C.AF_UNIX
	$if macos {
		address.sun_len = u8(sizeof(C.sockaddr_un))
	}
	unsafe { C.memcpy(&address.sun_path[0], path.str, usize(path.len)) }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return os.error_posix() }
	mut monitor := Monitor{
		descriptor:   fd
		deadline:     if timeout > 0 {
			time.sys_mono_now() + u64(timeout * f64(time.second))
		} else {
			u64(0)
		}
		idle_timeout: if timeout > 0 { u64(timeout * f64(time.second)) } else { u64(0) }
		cancel:       cancel
		context:      context
	}
	mut ready := false
	defer { if !ready { monitor.close() } }
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) != 0 {
		return os.error_posix()
	}
	$if macos {
		mut enabled := 1
		if C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &enabled, sizeof(int)) != 0 {
			return os.error_posix()
		}
	}
	if C.connect(fd, unsafe { voidptr(&address) }, u32(sizeof(C.sockaddr_un))) != 0 {
		if C.errno !in [C.EINPROGRESS, C.EAGAIN, C.EWOULDBLOCK] { return os.error_posix() }
		monitor.ready(true)!
		mut cause := i32(0)
		mut length := u32(sizeof(i32))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &cause, &length) != 0 {
			return os.error_posix()
		}
		if cause != 0 {
			return error_with_code(unsafe { C.strerror(cause).vstring().clone() }, cause)
		}
	}
	monitor.read_line()!
	monitor.command('qmp_capabilities', {})!
	ready = true
	return monitor
}

pub fn (mut monitor Monitor) close() {
	if monitor.descriptor >= 0 {
		fd := monitor.descriptor
		monitor.descriptor = -1
		C.close(fd)
	}
}

fn (monitor &Monitor) ready(writing bool) ! {
	if monitor.descriptor < 0 { return error('QMP connection is retired') }
	mut descriptor := C.pollfd{
		fd:     monitor.descriptor
		events: i16(if writing {
			C.POLLOUT
		} else {
			C.POLLIN
		})
	}
	for {
		if cachecli.cancelled() || (monitor.cancel != unsafe { nil } && monitor.cancel(monitor.context)) {
			return error('QMP interrupted')
		}
		if monitor.deadline != 0 && time.sys_mono_now() >= monitor.deadline {
			return error('QMP timed out')
		}
		count := C.poll(&descriptor, 1, 50)
		if count > 0 { return }
		if count < 0 && C.errno != C.EINTR { return os.error_posix() }
	}
}

fn (mut monitor Monitor) read_line() !string {
	mut bytes := []u8{}
	mut byte := u8(0)
	for {
		monitor.ready(false)!
		count := C.recv(monitor.descriptor, &byte, 1, 0)
		if count < 0 {
			if C.errno in [C.EINTR, C.EAGAIN] { continue }
			return os.error_posix()
		}
		if count == 0 { return error('QMP disconnected') }
		if monitor.idle_timeout != 0 {
			monitor.deadline = time.sys_mono_now() + monitor.idle_timeout
		}
		if byte == `\n` {
			hosttest.module_decode_utf8(bytes.bytestr())!
			return bytes.bytestr()
		}
		if bytes.len >= 64 * 1024 * 1024 { return error('QMP reply too large') }
		bytes << byte
	}
	return error('QMP disconnected')
}

pub fn (mut monitor Monitor) command(name string, arguments map[string]ah.Value) !ah.Value {
	mut object := {
		'execute': ah.Value(name)
	}
	if arguments.len > 0 { object['arguments'] = ah.Value(arguments) }
	request := ah.encode(ah.Value(object)) + '\n'
	mut position := 0
	for position < request.len {
		monitor.ready(true)!
		mut flags := 0
		$if linux {
			flags = C.MSG_NOSIGNAL
		}
		count := unsafe { C.send(monitor.descriptor, request.str + position, usize(request.len - position), flags) }
		if count < 0 {
			if C.errno in [C.EINTR, C.EAGAIN] { continue }
			return os.error_posix()
		}
		if count == 0 { return error('QMP disconnected') }
		position += int(count)
		if monitor.idle_timeout != 0 {
			monitor.deadline = time.sys_mono_now() + monitor.idle_timeout
		}
	}
	for {
		value := json2.decode[ah.Value](monitor.read_line()!, strict: true)!
		if value !is map[string]ah.Value { return error('QMP reply is not an object') }
		reply := value.object()
		if 'error' in reply { return error(ah.encode(reply['error']!)) }
		if 'return' in reply { return reply['return']! }
	}
	return error('QMP disconnected')
}

pub fn qmp(path string, name string, arguments map[string]ah.Value) !ah.Value {
	mut monitor := connect_monitor(path, 20)!
	defer { monitor.close() }
	return monitor.command(name, arguments)
}
