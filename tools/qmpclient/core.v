// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import json2
import hosttest
import net.unix
import os
import time

#include <poll.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
struct C.pollfd { mut: fd i32 events i16 revents i16 }
fn C.poll(&C.pollfd, usize, i32) i32
pub struct Monitor {
mut:
	connection &unix.StreamConn = unsafe { nil }
	deadline u64
	cancel fn () bool = unsafe { nil }
}
pub fn connect(path string) !Monitor {
	return connect_bounded(path, 0, unsafe { nil })
}
pub fn connect_bounded(path string, deadline u64, cancel fn () bool) !Monitor {
	mut connection := unix.connect_stream(path)!
	mut monitor := Monitor{connection: connection, deadline: deadline, cancel: cancel}
	mut open := false
	defer { if !open { monitor.close() } }
	if C.fcntl(connection.sock.handle, C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(connection.sock.handle, C.F_SETFL, C.O_NONBLOCK) != 0 { return os.error_posix() }
	monitor.read_line()!
	monitor.command('qmp_capabilities', {})!
	open = true
	return monitor
}
pub fn (mut monitor Monitor) close() { if !isnil(monitor.connection) { monitor.connection.close() or {}; monitor.connection = unsafe { nil } } }
fn (mut monitor Monitor) line() !map[string]json2.Any {
	text := monitor.read_line()!
	hosttest.module_decode_utf8(text)!
	return json2.decode[json2.Any](text)!.as_map()
}
fn (monitor &Monitor) ready(writing bool) ! {
	mut descriptor := C.pollfd{fd: monitor.connection.sock.handle, events: i16(if writing { C.POLLOUT } else { C.POLLIN })}
	for {
		if monitor.cancel != unsafe { nil } && monitor.cancel() { return error('QMP interrupted') }
		if monitor.deadline != 0 && time.sys_mono_now() >= monitor.deadline { return error('QMP deadline expired') }
		count := C.poll(&descriptor, 1, 50)
		if count > 0 { return }
		if count < 0 && C.errno != C.EINTR { return os.error_posix() }
	}
}
fn (mut monitor Monitor) read_line() !string {
	mut data := []u8{}
	mut byte := u8(0)
	for {
		monitor.ready(false)!
		count := C.recv(monitor.connection.sock.handle, &byte, 1, 0)
		if count < 0 { if C.errno in [C.EINTR, C.EAGAIN] { continue }; return os.error_posix() }
		if count == 0 { return error('QMP closed') }
		if byte == `\n` { return data.bytestr() }
		if data.len >= 64 * 1024 * 1024 { return error('QMP reply too large') }
		data << byte
	}
	return error('QMP closed')
}
pub fn (mut monitor Monitor) command(name string, arguments map[string]json2.Any) ! {
	mut object := {'execute': json2.Any(name)}
	if arguments.len > 0 { object['arguments'] = json2.Any(arguments) }
	request := json2.encode(object) + '\n'
	mut position := 0
	for position < request.len {
		monitor.ready(true)!
		count := unsafe { C.send(monitor.connection.sock.handle, request.str + position, usize(request.len - position), 0) }
		if count < 0 { if C.errno in [C.EINTR, C.EAGAIN] { continue }; return os.error_posix() }
		if count == 0 { return error('QMP closed') }
		position += int(count)
	}
	for { reply := monitor.line()!; if 'error' in reply { return error(json2.encode(reply['error']!)) }; if 'return' in reply { return } }
}
