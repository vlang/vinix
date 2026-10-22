// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import crypto.rand
import json2
import os
import time

struct Guest {
mut:
	monitor   Monitor
	buffer    []u8 = []u8{len: 4096}
	position  int
	used      int
	remaining int = 1024 * 1024
}

// One synchronized, read-only exchange. The caller serializes access to the
// transport; virtio-serial can retain data from an earlier host connection.
// Return JSON text so guest counters never round through json2.Any's f64.
pub fn guest_query(path string, command string, deadline u64, cancel fn () bool) !string {
	if command !in ['guest-ping', 'guest-info', 'guest-get-osinfo', 'guest-network-get-interfaces'] {
		return error('guest command is not an allowed read-only query')
	}
	if deadline == 0 || deadline <= time.sys_mono_now() { return error('guest query requires a future deadline') }
	connection := owned_connection(path, deadline, cancel)!
	mut guest := Guest{monitor: Monitor{connection: connection, deadline: deadline, cancel: cancel}}
	defer { guest.monitor.close() }
	$if macos {
		one := i32(1)
		if C.setsockopt(connection.sock.handle, C.SOL_SOCKET, C.SO_NOSIGPIPE, &one, u32(sizeof(one))) != 0 {
			return os.error_posix()
		}
	}
	nonce := rand.int_u64(u64(0x7fffffffffffffff))!.str()
	sync_id := 'vinix-guest-sync-' + nonce
	guest.send('\xff{"execute":"guest-sync-delimited","arguments":{"id":' + nonce + '},"id":' + json2.encode(sync_id) + '}\n')!
	mut synchronized := false
	for !synchronized {
		line := guest.sync_line()!
		reply := guest_object(line) or { continue }
		if value := reply['return'] {
			if value is WireNumber && value.token == nonce { synchronized = true }
		}
	}
	id := 'vinix-guest-' + nonce
	guest.send('{"execute":' + json2.encode(command) + ',"id":' + json2.encode(id) + '}\n')!
	for {
		reply := guest_object(guest.line()!)!
		if 'event' in reply { continue }
		if value := reply['error'] {
			if 'id' !in reply { return error('guest agent: ' + wire_encode(value)) }
		}
		response_id := reply['id'] or { return error('guest response has no transaction ID') }
		matches := match response_id { string { response_id == id } else { false } }
		if !matches { continue }
		if value := reply['error'] { return error('guest agent: ' + wire_encode(value)) }
		value := reply['return'] or { return error('guest response has no result') }
		return wire_encode(value)
	}
	return error('guest agent closed')
}

fn (mut guest Guest) send(text string) ! {
	flags := $if macos { 0 } $else { C.MSG_NOSIGNAL }
	mut position := 0
	for position < text.len {
		guest.monitor.ready(true)!
		count := unsafe { C.send(guest.monitor.connection.sock.handle, text.str + position, usize(text.len - position), flags) }
		if count < 0 {
			if C.errno in [C.EAGAIN, C.EINTR] { continue }
			return os.error_posix()
		}
		if count == 0 { return error('guest agent closed') }
		position += int(count)
	}
}

fn (mut guest Guest) byte() !u8 {
	for guest.position == guest.used {
		guest.monitor.ready(false)!
		count := C.recv(guest.monitor.connection.sock.handle, guest.buffer.data, usize(guest.buffer.len), 0)
		if count < 0 {
			if C.errno in [C.EAGAIN, C.EINTR] { continue }
			return os.error_posix()
		}
		if count == 0 { return error('guest agent closed') }
		guest.remaining -= int(count)
		if guest.remaining < 0 { return error('guest response exceeds 1 MiB exchange limit') }
		guest.position = 0
		guest.used = int(count)
	}
	value := guest.buffer[guest.position]
	guest.position++
	return value
}

// Ignore stale output until a sentinel, resetting even across a partial JSON
// fragment. A wrong nonce starts another scan; only our nonce establishes sync.
fn (mut guest Guest) sync_line() !string {
	mut seen := false
	mut line := []u8{}
	for {
		value := guest.byte()!
		if value == 0xff { seen = true; line.clear(); continue }
		if !seen { continue }
		if value == `\n` { return line.bytestr() }
		line << value
	}
	return error('guest agent closed')
}

fn (mut guest Guest) line() !string {
	mut line := []u8{}
	for {
		value := guest.byte()!
		if value == 0xff { return error('unexpected guest synchronization sentinel') }
		if value == `\n` { return line.bytestr() }
		line << value
	}
	return error('guest agent closed')
}

fn guest_object(text string) !map[string]WireValue {
	// Bound parser recursion independently of the byte and wall-clock limits.
	mut quoted := false
	mut escaped := false
	mut depth := 0
	for value in text {
		if quoted {
			if escaped { escaped = false }
			else if value == `\\` { escaped = true }
			else if value == `"` { quoted = false }
		} else if value == `"` { quoted = true }
		else if value in [`{`, `[`] {
			depth++
			if depth > 64 { return error('guest response exceeds JSON nesting limit') }
		} else if value in [`}`, `]`] { depth-- }
	}
	value := wire_decode(text)!
	if value !is map[string]WireValue { return error('guest response must be a JSON object') }
	return value
}
