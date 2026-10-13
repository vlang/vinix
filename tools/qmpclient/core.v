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
	accept_errors bool
	sequence u64
	byte_json bool
}
pub fn connect(path string) !Monitor {
	return connect_bounded(path, 0, unsafe { nil })
}
pub fn connect_bounded(path string, deadline u64, cancel fn () bool) !Monitor {
	return connect_policy(path, deadline, cancel, false)
}
// Saved performance runners treated a QMP error as a completed reply. Other
// consumers retain the default policy that raises the returned error.
pub fn connect_policy(path string, deadline u64, cancel fn () bool, accept_errors bool) !Monitor {
	return connect_body(path, deadline, cancel, accept_errors, false)
}
// iBoot validates its greeting and skips events. Existing consumers keep
// their previous greeting policy.
pub fn connect_checked(path string, deadline u64, cancel fn () bool) !Monitor {
	return connect_body(path, deadline, cancel, false, true)
}
// The pointer regression parses one JSON greeting, without requiring a QMP
// object or skipping events. Keep this consumer's original greeting policy.
pub fn connect_json(path string, deadline u64, cancel fn () bool) !Monitor {
	return connect_greeting(path,deadline,cancel,false,false,true)
}
fn connect_body(path string, deadline u64, cancel fn () bool, accept_errors bool, checked bool) !Monitor {
	return connect_greeting(path,deadline,cancel,accept_errors,checked,false)
}
fn connect_greeting(path string, deadline u64, cancel fn () bool, accept_errors bool, checked bool, parse_json bool) !Monitor {
	mut connection := owned_connection(path, deadline, cancel)!
	mut monitor := Monitor{connection: connection, deadline: deadline, cancel: cancel, accept_errors: accept_errors,byte_json:parse_json}
	mut open := false
	defer { if !open { monitor.close() } }
	if C.fcntl(connection.sock.handle, C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(connection.sock.handle, C.F_SETFL, C.O_NONBLOCK) != 0 { return os.error_posix() }
	if checked {
		for {
			greeting := monitor.line()!
			if 'event' in greeting { continue }
			value := greeting['QMP'] or { return error('invalid QMP greeting') }
			if value !is map[string]json2.Any { return error('invalid QMP greeting') }
			break
		}
	} else if parse_json {text:=monitor.read_line()!;hosttest.module_decode_utf8(text)!;json2.decode[json2.Any](json_text(text))!} else { monitor.read_line()! }
	monitor.command('qmp_capabilities', {})!
	open = true
	return monitor
}
pub fn (mut monitor Monitor) close() { if !isnil(monitor.connection) { monitor.connection.close() or {}; monitor.connection = unsafe { nil } } }
pub fn (mut monitor Monitor) set_deadline(deadline u64) { monitor.deadline = deadline }
// Cleanup after an interrupt must still be able to stop the private guest.
// The caller retains its signal status while bounding the final exchange.
pub fn (mut monitor Monitor) set_cancel(cancel fn () bool) { monitor.cancel = cancel }
fn (mut monitor Monitor) line() !map[string]json2.Any {
	text := monitor.read_line()!
	hosttest.module_decode_utf8(text)!
	return json2.decode[json2.Any](if monitor.byte_json{json_text(text)}else{text})!.as_map()
}
fn json_text(text string) string {return if text.starts_with('\xef\xbb\xbf'){text[3..]}else{text}}
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
	monitor.send(object)!
	for { reply := monitor.line()!; if 'error' in reply { if monitor.accept_errors { return }; return error(json2.encode(reply['error']!)) }; if 'return' in reply { return } }
}

// Typed callers need the returned status/data and must correlate the reply
// across asynchronous events and unrelated replies. Keep command()'s original
// wire format and saved-controller error policy unchanged.
pub fn (mut monitor Monitor) request(name string, arguments map[string]json2.Any) !json2.Any {
	monitor.sequence++
	id := 'vinix-' + monitor.sequence.str()
	mut object := {'execute': json2.Any(name), 'id': json2.Any(id)}
	if arguments.len > 0 { object['arguments'] = json2.Any(arguments) }
	monitor.send(object)!
	for {
		reply := monitor.line()!
		if 'event' in reply { continue }
		if 'error' in reply && 'id' !in reply { return error(json2.encode(reply['error']!)) }
		if (reply['id'] or { json2.Null{} }) != json2.Any(id) { continue }
		if value := reply['error'] { return error(json2.encode(value)) }
		return reply['return'] or { return error('QMP response has no result') }
	}
	return error('QMP closed')
}

fn (mut monitor Monitor) send(object map[string]json2.Any) ! {
	request := json2.encode(object) + '\n'
	mut position := 0
	for position < request.len {
		monitor.ready(true)!
		count := unsafe { C.send(monitor.connection.sock.handle, request.str + position, usize(request.len - position), 0) }
		if count < 0 { if C.errno in [C.EINTR, C.EAGAIN] { continue }; return os.error_posix() }
		if count == 0 { return error('QMP closed') }
		position += int(count)
	}
}
