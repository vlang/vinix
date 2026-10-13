// SPDX-License-Identifier: GPL-2.0-or-later
// Loopback TLS repository for real-curl transport qualification.
module main

import net.openssl
import os
import strconv
import time

#include <signal.h>

fn reply(mut connection openssl.SSLConn, status string, headers string, body string) ! {
	connection.write_string('HTTP/1.1 ' + status + '\r\nConnection: close\r\n' + headers + '\r\n')!
	if body.len > 0 { connection.write_string(body)! }
}

fn serve(mut connection openssl.SSLConn, root string, log string) ! {
	connection.set_read_timeout(5 * time.second)
	mut request := ''
	mut buffer := []u8{len: 4096}
	for !request.contains('\r\n\r\n') {
		count := connection.read(mut buffer)!
		if count == 0 || request.len + count > 16384 { return error('invalid fixture request') }
		request += buffer[..count].bytestr()
	}
	lines := request.split('\r\n')
	parts := lines[0].split(' ')
	if parts.len != 3 || parts[0] != 'GET' { return error('fixture accepts GET only') }
	mut range := ''
	for line in lines {
		if line.to_lower().starts_with('range:') { range = line.all_after(':').trim_space() }
	}
	path := parts[1].split('/')
	if path.len < 3 || path[0] != '' { return error('invalid fixture URL') }
	mode := path[1]
	relative := path[2..].join('/')
	if relative == '' || relative.contains('..') || relative.contains('%') || relative.contains('\\') {
		return error('invalid fixture repository path')
	}
	mut record := os.open_file(log, 'a', 0o600)!
	record.writeln(mode + ' ' + relative + ' ' + if range == '' { '-' } else { range })!
	record.close()
	if mode == 'forbidden' && relative.starts_with('objects/') { reply(mut connection, '403 Forbidden', 'Content-Length: 0\r\n', '')!; return }
	if mode == 'insecure-redirect' && relative.starts_with('objects/') {
		reply(mut connection, '302 Found', 'Location: http://127.0.0.1:9/refused\r\nContent-Length: 0\r\n', '')!
		return
	}
	mut body := os.read_file(root + '/' + relative) or {
		reply(mut connection, '404 Not Found', 'Content-Length: 0\r\n', '')!
		return
	}
	if mode == 'oversized' {
		reply(mut connection, '200 OK', 'Content-Length: ' + (body.len + 1).str() + '\r\n', '')!
		return
	}
	if mode == 'no-range-corrupt' && relative.starts_with('objects/') {
		body = 'x'.repeat(body.len)
	}
	if range != '' && mode !in ['no-range', 'no-range-corrupt'] {
		if !range.starts_with('bytes=') || !range.ends_with('-') { return error('unexpected range spelling') }
		offset := strconv.atoi(range[6..range.len - 1])!
		if offset < 0 || offset >= body.len {
			reply(mut connection, '416 Range Not Satisfiable', 'Content-Range: bytes */' + body.len.str() + '\r\nContent-Length: 0\r\n', '')!
			return
		}
		headers := 'Content-Range: bytes ' + offset.str() + '-' + (body.len - 1).str() + '/' + body.len.str()
			+ '\r\nContent-Length: ' + (body.len - offset).str() + '\r\n'
		if mode == 'truncated' {
			end := if offset + 1024 < body.len { offset + 1024 } else { body.len - 1 }
			reply(mut connection, '206 Partial Content', headers, body[offset..end])!
		} else { reply(mut connection, '206 Partial Content', headers, body[offset..])! }
		return
	}
	reply(mut connection, '200 OK', 'Content-Length: ' + body.len.str() + '\r\n', body)!
}

fn run() ! {
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	if os.args.len != 6 { return error('usage: https-fixture CERT KEY REPOSITORY READY LOG') }
	// Bind directly, trying another port on collision. No reservation gap and no
	// listener exposed outside loopback; the readiness file records the bound URL.
	for attempt in 0 .. 64 {
		port := 20000 + (os.getpid() + attempt) % 30000
		mut listener := openssl.new_ssl_listener('127.0.0.1:' + port.str(), openssl.SSLConnectConfig{
			cert: os.args[1], cert_key: os.args[2]
		}) or { continue }
		defer { listener.shutdown() or {} }
		os.write_file(os.args[4] + '.new', 'https://127.0.0.1:' + port.str())!
		os.rename(os.args[4] + '.new', os.args[4])!
		for {
			mut connection := listener.accept() or { continue }
			serve(mut connection, os.args[3], os.args[5]) or { eprintln(err) }
			connection.shutdown() or {}
		}
	}
	return error('cannot bind loopback HTTPS fixture')
}

fn main() { run() or { eprintln(err); exit(1) } }
