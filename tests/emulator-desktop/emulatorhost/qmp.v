// SPDX-License-Identifier: GPL-2.0-or-later
module emulatorhost

import json2
import hosttest
import os
import policyhost
import time

#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
struct C.sockaddr_un {
mut:
	sun_len u8
	sun_family u16
	sun_path [108]char
}
fn C.socket(i32, i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
struct C.pollfd {
mut:
	fd i32
	events i16
	revents i16
}
fn C.poll(&C.pollfd, usize, i32) i32
fn C.send(i32, voidptr, usize, i32) i32
fn C.recv(i32, voidptr, usize, i32) i32

// Preserve integer tokens of any length; replies never round through f64.
pub struct QmpNumber {
pub mut:
	text string
}
fn (mut number QmpNumber) from_json_number(raw string) ! { number.text = raw }
pub fn (number QmpNumber) to_json() string { return number.text }
pub type QmpValue = []QmpValue | QmpNumber | bool | map[string]QmpValue | string | json2.Null

pub struct Qmp {
mut:
	fd i32 = -1
	buffer []u8
}

fn qmp_ready(fd i32, events i16, deadline u64) ! {
	for time.sys_mono_now() < deadline {
		policyhost.command_checkpoint()!
		mut descriptor := C.pollfd{fd: fd, events: events}
		result := C.poll(&descriptor, 1, 25)
		if result > 0 { return }
		if result < 0 && C.errno != C.EINTR { return error(os.get_error_msg(C.errno)) }
	}
	return error('QMP socket timed out')
}

pub fn qmp_connect(path string) !Qmp {
	if path.contains('\x00') { return error('embedded null byte') }
	maximum := $if macos { 103 } $else { 107 }
	if path.len > maximum { return error('QMP socket path too long') }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return error(os.get_error_msg(C.errno)) }
	mut q := Qmp{fd: fd}
	q.connect(path) or { q.close(); return err }
	q.line() or { q.close(); return err }
	q.call('qmp_capabilities', {}) or { q.close(); return err }
	return q
}

fn (mut q Qmp) connect(path string) ! {
	if C.fcntl(q.fd, C.F_SETFL, C.O_NONBLOCK) < 0 || C.fcntl(q.fd, C.F_SETFD, C.FD_CLOEXEC) < 0 {
		return error(os.get_error_msg(C.errno))
	}
	mut address := C.sockaddr_un{sun_family: u16(C.AF_UNIX)}
	$if macos { address.sun_len = u8(sizeof(C.sockaddr_un)) }
	unsafe { vmemcpy(&address.sun_path[0], path.str, path.len) }
	if C.connect(q.fd, &address, u32(sizeof(C.sockaddr_un))) == 0 { return }
	if C.errno != C.EINPROGRESS { return error(os.get_error_msg(C.errno)) }
	qmp_ready(q.fd, i16(C.POLLOUT), time.sys_mono_now() + u64(10 * time.second))!
	mut number := i32(0)
	mut length := u32(sizeof(i32))
	if C.getsockopt(q.fd, C.SOL_SOCKET, C.SO_ERROR, &number, &length) != 0 { return error(os.get_error_msg(C.errno)) }
	if number != 0 { return error(os.get_error_msg(number)) }
}

fn (mut q Qmp) line() !QmpValue {
	if q.fd < 0 { return error('QMP socket is closed') }
	for {
		end := q.buffer.index(u8(10))
		if end >= 0 {
			text := q.buffer[..end + 1].bytestr()
			q.buffer = q.buffer[end + 1..].clone()
			hosttest.module_decode_utf8(text)!
			return json2.decode[QmpValue](text, strict: true)!
		}
		qmp_ready(q.fd, i16(C.POLLIN), time.sys_mono_now() + u64(10 * time.second))!
		mut bytes := [8192]u8{}
		count := C.recv(q.fd, &bytes[0], bytes.len, 0)
		if count == 0 { return error('QMP socket closed without a reply') }
		if count < 0 {
			if C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
			return error(os.get_error_msg(C.errno))
		}
		q.buffer << bytes[..count]
	}
	return error('unreachable QMP read')
}

pub fn (mut q Qmp) call(command string, arguments map[string]json2.Any) !QmpValue {
	if q.fd < 0 { return error('QMP socket is closed') }
	text := json2.encode({'execute': json2.Any(command), 'arguments': json2.Any(arguments)}) + '\n'
	mut sent := 0
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for sent < text.len {
		qmp_ready(q.fd, i16(C.POLLOUT), deadline)!
		count := unsafe { C.send(q.fd, text.str + sent, usize(text.len - sent), 0) }
		if count < 0 && C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
		if count <= 0 { return error('Cannot send QMP command') }
		sent += int(count)
	}
	for {
		reply := q.line()!
		if reply is map[string]QmpValue {
			if 'error' in reply { return error('QMP error: ' + json2.encode(reply)) }
			if value := reply['return'] { return value }
		} else { return error('QMP reply must be an object') }
	}
	return error('unreachable QMP reply')
}

// Python's round uses ties to even. Keep it for pointer coordinates and court
// crop rows, including the half-way coordinates in generated input fixtures.
pub fn rounded(value f64) int {
	whole := int(value)
	fraction := value - whole
	if fraction > 0.5 || fraction == 0.5 && whole % 2 != 0 { return whole + 1 }
	if fraction < -0.5 || fraction == -0.5 && whole % 2 != 0 { return whole - 1 }
	return whole
}
pub fn pointer_events(x int, y int, press bool, release bool) []json2.Any {
	mut events := []json2.Any{}
	if !release {
		for axis, value in {'x': rounded(f64(x) * 32767 / 2048), 'y': rounded(f64(y) * 32767 / 1536)} {
			events << json2.Any({'type': json2.Any('abs'), 'data': json2.Any({'axis': json2.Any(axis), 'value': json2.Any(value)})})
		}
	}
	if press || release { events << json2.Any({'type': json2.Any('btn'), 'data': json2.Any({'button': json2.Any('left'), 'down': json2.Any(!release)})}) }
	return events
}
fn (mut q Qmp) input(x int, y int, press bool, release bool) ! {
	q.call('input-send-event', {'events': json2.Any(pointer_events(x, y, press, release))})!
}
pub fn (mut q Qmp) move(x int, y int) ! { q.input(x, y, false, false)! }
pub fn (mut q Qmp) hold(x int, y int, seconds f64) ! {
	q.input(x, y, true, false)!
	pause(seconds)!
	q.input(0, 0, false, true)!
}
pub fn (mut q Qmp) click(x int, y int) ! { q.hold(x, y, 0.15)!; pause(0.5)! }
pub fn (mut q Qmp) drag(x int, y int, end_x int, end_y int, seconds f64) ! {
	pause(0.25)!
	q.input(x, y, true, false)!
	pause(0.25)!
	q.move(end_x, end_y)!
	pause(seconds)!
	q.input(0, 0, false, true)!
	pause(0.25)!
}
pub fn (mut q Qmp) close() {
	if q.fd >= 0 { C.close(q.fd); q.fd = -1 }
	q.buffer.clear()
}
