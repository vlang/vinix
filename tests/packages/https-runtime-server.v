// SPDX-License-Identifier: GPL-2.0-or-later
// Local TLS repository reached through QEMU user networking by real guest curl.
module main

import net.openssl
import os
import strconv
import strings
import time

#include <signal.h>

fn reply(mut connection openssl.SSLConn, status string, headers string, body string, declared int) ! {
	number := declared.str()
	defer { unsafe { number.free() } }
	mut builder := &strings.Builder(strings.new_builder(128 + headers.len))
	defer { unsafe {
		builder.free()
		free(builder)
	}
	 }
	builder.write_string('HTTP/1.1 ')
	builder.write_string(status)
	builder.write_string('\r\nConnection: close\r\n')
	builder.write_string(headers)
	builder.write_string('Content-Length: ')
	builder.write_string(number)
	builder.write_string('\r\n\r\n')
	response := builder.str()
	defer { unsafe { response.free() } }
	connection.write_string(response)!
	if body.len > 0 { connection.write_string(body)! }
}

fn retire_strings(values []string) {
	unsafe {
		for value in values { value.free() }
		(&array(&values)).free()
	}
}

fn serve(mut connection openssl.SSLConn, root string, log string) ! {
	connection.set_read_timeout(5 * time.second)
	mut request := ''
	mut buffer := []u8{len: 4096}
	defer { unsafe {
		request.free()
		buffer.free()
	}
	 }
	for !request.contains('\r\n\r\n') {
		count := connection.read(mut buffer)!
		if count == 0 || request.len + count > 16384 { return error('invalid fixture request') }
		fragment := buffer[..count].bytestr()
		next := request + fragment
		unsafe {
			request.free()
			fragment.free()
		}
		request = next
	}
	lines := request.split('\r\n')
	defer { retire_strings(lines) }
	parts := lines[0].split(' ')
	defer { retire_strings(parts) }
	if parts.len != 3 || parts[0] != 'GET' { return error('fixture accepts GET only') }
	mut range := ''
	defer { unsafe { range.free() } }
	for line in lines {
		lower := line.to_lower()
		defer { unsafe { lower.free() } }
		if lower.starts_with('range:') {
			value := line.all_after(':')
			unsafe { range.free() }
			range = value.trim_space()
			unsafe { value.free() }
		}
	}
	path := parts[1].split('/')
	defer { retire_strings(path) }
	if path.len < 4 || path[0] != '' { return error('invalid fixture URL') }
	label := path[1]
	mode := path[2]
	relative := path[3..].join('/')
	defer { unsafe { relative.free() } }
	if relative == '' || relative.contains('..') || relative.contains('%') || relative.contains('\\') {
		return error('invalid fixture repository path')
	}
	mut record := os.open_file(log, 'a', 0o600)!
	defer { record.close() }
	entry := label + ' ' + mode + ' ' + relative + ' ' + if range == '' { '-' } else { range }
	defer { unsafe { entry.free() } }
	record.writeln(entry)!
	if mode == 'delayed' { time.sleep(250 * time.millisecond) }
	if mode == 'forbidden' && relative.starts_with('objects/') {
		reply(mut connection, '403 Forbidden', '', '', 0)!
		return
	}
	if mode == 'insecure-redirect' && relative.starts_with('objects/') {
		reply(mut connection, '302 Found', 'Location: http://127.0.0.1:9/refused\r\n', '', 0)!
		return
	}
	file := root + '/' + relative
	defer { unsafe { file.free() } }
	mut body := os.read_file(file) or {
		unsafe { err.free() }
		reply(mut connection, '404 Not Found', '', '', 0)!
		return
	}
	defer { unsafe { body.free() } }
	if label == 'refresh-signature' && mode != 'setup' && relative == 'index.sig' {
		unsafe { body.free() }
		body = '00'.repeat(64)
	}
	if mode == 'oversized' {
		reply(mut connection, '200 OK', '', '', body.len + 1)!
		return
	}
	if mode == 'no-range-corrupt' && relative.starts_with('objects/') {
		length := body.len
		unsafe { body.free() }
		body = 'x'.repeat(length)
	}
	if range != '' && mode !in ['no-range', 'no-range-corrupt'] {
		if !range.starts_with('bytes=') || !range.ends_with('-') {
			return error('unexpected range spelling')
		}
		position := range[6..range.len - 1]
		defer { unsafe { position.free() } }
		offset := strconv.atoi(position)!
		length := body.len.str()
		defer { unsafe { length.free() } }
		if offset < 0 || offset >= body.len {
			headers := 'Content-Range: bytes */' + length + '\r\n'
			defer { unsafe { headers.free() } }
			reply(mut connection, '416 Range Not Satisfiable', headers, '', 0)!
			return
		}
		first := offset.str()
		last := (body.len - 1).str()
		defer { unsafe {
			first.free()
			last.free()
		}
		 }
		headers := 'Content-Range: bytes ' + first + '-' + last + '/' + length + '\r\n'
		defer { unsafe { headers.free() } }
		if mode == 'truncated' && offset == 512 {
			end := if offset + 1024 < body.len { offset + 1024 } else { body.len - 1 }
			fragment := body[offset..end]
			defer { unsafe { fragment.free() } }
			reply(mut connection, '206 Partial Content', headers, fragment, body.len - offset)!
		} else {
			fragment := body[offset..]
			defer { unsafe { fragment.free() } }
			reply(mut connection, '206 Partial Content', headers, fragment, body.len - offset)!
		}
		return
	}
	reply(mut connection, '200 OK', '', body, body.len)!
}

fn run() ! {
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	if os.args.len != 6 { return error('usage: https-fixture CERT KEY REPOSITORY READY LOG') }
	// Bind directly, trying another port on collision. No reservation gap and no
	// listener exposed outside loopback; the readiness file records the bound URL.
	for attempt in 0 .. 64 {
		port := 20000 + (os.getpid() + attempt) % 30000
		mut listener := openssl.new_ssl_listener('127.0.0.1:' + port.str(), openssl.SSLConnectConfig{
			cert:     os.args[1]
			cert_key: os.args[2]
		}) or { continue }
		defer { listener.shutdown() or {} }
		os.write_file(os.args[4] + '.new', 'https://127.0.0.1:' + port.str())!
		os.rename(os.args[4] + '.new', os.args[4])!
		for {
			mut connection := listener.accept_without_handshake() or {
				unsafe { err.free() }
				continue
			}
			connection.set_read_timeout(5 * time.second)
			connection.accept_handshake() or {
				unsafe { err.free() }
				connection.shutdown() or { unsafe { err.free() } }
				unsafe { free(connection) }
				continue
			}
			serve(mut connection, os.args[3], os.args[5]) or {
				message := err.msg()
				eprintln(message)
				unsafe {
					message.free()
					err.free()
				}
			}
			connection.shutdown() or { unsafe { err.free() } }
			unsafe { free(connection) }
		}
	}
	return error('cannot bind loopback HTTPS fixture')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
