// SPDX-License-Identifier: GPL-2.0-or-later
module nativequery

import cachecli
import json2
import os
import sourcecommand
import time

#include <poll.h>
struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(&C.pollfd, usize, i32) i32

pub struct Controller {
pub:
	executable  string
	eof_message string            = 'native host controller ended without a response'
	started     fn (int, voidptr) = unsafe { nil }
}

pub type Callback = fn (string, map[string]Value, voidptr) !Value

fn input_pipe() ![2]i32 {
	mut descriptors := [i32(-1), -1]!
	if C.pipe(&descriptors[0]) != 0 { return os.error_posix() }
	mut ready := false
	defer { if !ready {
		for fd in descriptors { if fd >= 0 { C.close(fd) } }
	} }
	for i in 0 .. 2 {
		if descriptors[i] < 3 {
			moved := C.fcntl(descriptors[i], C.F_DUPFD_CLOEXEC, 3)
			if moved < 0 { return os.error_posix() }
			C.close(descriptors[i])
			descriptors[i] = moved
		} else if C.fcntl(descriptors[i], C.F_SETFD, C.FD_CLOEXEC) != 0 {
			return os.error_posix()
		}
	}
	if C.fcntl(descriptors[1], C.F_SETFL, C.O_NONBLOCK) != 0 { return os.error_posix() }
	ready = true
	return descriptors
}

fn send(fd i32, row map[string]Value) ! {
	bytes := (encode(Value(row)) + '\n').bytes()
	mut offset := 0
	for offset < bytes.len {
		cachecli.checkpoint()!
		count := unsafe { C.write(fd, &u8(bytes.data) + offset, usize(bytes.len - offset)) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			if C.errno in [C.EAGAIN, C.EWOULDBLOCK] {
				mut descriptor := C.pollfd{ fd: fd, events: i16(C.POLLOUT) }
				C.poll(&descriptor, 1, 50)
				continue
			}
			return os.error_posix()
		}
		if count == 0 { return error('native query input closed') }
		offset += int(count)
	}
}

fn receive(fd i32, eof string) !map[string]Value {
	mut bytes := []u8{}
	mut byte := u8(0)
	for {
		cachecli.checkpoint()!
		mut descriptor := C.pollfd{ fd: fd, events: i16(C.POLLIN) }
		result := C.poll(&descriptor, 1, 50)
		if result < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if result == 0 { continue }
		count := C.read(fd, &byte, 1)
		if count < 0 {
			if C.errno in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { continue }
			return os.error_posix()
		}
		if count == 0 {
			if bytes.len > 0 { return json2.decode[map[string]Value](bytes.bytestr())! }
			return error(eof)
		}
		if byte == `\n` { return json2.decode[map[string]Value](bytes.bytestr())! }
		bytes << byte
	}
	return error(eof)
}

pub fn (controller Controller) call(request map[string]Value, callback Callback, context voidptr) !Value {
	mut pipes := input_pipe()!
	defer { for fd in pipes { if fd >= 0 { C.close(fd) } }
	 }
	mut child := sourcecommand.spawn_reader_input([controller.executable], os.environ(), pipes[0])!
	defer {
		C.close(pipes[1])
		pipes[1] = -1
		deadline := time.sys_mono_now() + 5 * time.second
		for time.sys_mono_now() < deadline {
			if (child.poll() or { sourcecommand.ChildExit{ exited: true } }).exited { break }
			time.sleep(10 * time.millisecond)
		}
		child.close() or {}
	}
	C.close(pipes[0])
	pipes[0] = -1
	if controller.started != unsafe { nil } { controller.started(child.pid, context) }
	send(pipes[1], request)!
	mut saved := []IError{}
	for {
		row := receive(child.descriptor, controller.eof_message)!
		if 'callback' !in row {
			if detail := row['error'] {
				error_row := detail.as_map()
				if index := error_row['binding_error'] {
					number := binding_index(index)!
					if number < 0 || number >= saved.len {
						return error('invalid native callback error index')
					}
					return saved[number]
				}
				return error((error_row['message'] or { Value('native host controller failed') }).str())
			}
			return row['value']!
		}
		mut response := map[string]Value{}
		value := callback(row['callback']!.str(), row['arguments']!.as_map(), context) or {
			saved << err
			response['error'] = Value({
				'binding_error': Value(saved.len - 1)
				'message':       Value(err.msg())
			})
			json2.Null{}
		}
		if 'error' !in response { response['value'] = value }
		send(pipes[1], response)!
	}
	return json2.Null{}
}
