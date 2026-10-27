// SPDX-License-Identifier: GPL-2.0-or-later
// Credential-free fixture delivery to QEMU usernet; never a general file server.
module main

import crypto.sha256
import json2
import net
import os
import time

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.read(int, voidptr, uint) int
fn C.write(int, voidptr, uint) int
fn C.fstat(int, &C.stat) int

const runner_path = '/Users/alex/.local/state/vinix/android/service-query-run-arm64-r1'
const runner_pin = '8ef76b9e4c9f1eb0cc84780eaa0b618a3a70f317cd4f0e87824ddcdffcae8727'
const fixture_root = '/Users/alex/.local/state/vinix/android/service-query-fixture-2026-10-27-r1'
const client_pin = '890de9d4ff410aaf5cd87a52b630ccfa7280fd3c0b2b38eee57159d525b1565d'
const disabled_pin = 'e5075f571f3b8334dded40accb08257ccfdf83e8526a7b61e502d586daa66048'
const direct_boot_runner = '/Users/alex/.local/state/vinix/android/direct-boot-run-2026-10-27-r1/run'
const direct_boot_runner_pin = '8caab5559b73dbe1ffc9645006e899fd82dfbe5cfac810df4f189db9eb152a60'
const direct_boot_fixture = '/Users/alex/.local/state/vinix/android/direct-boot-fixture-2026-10-27-r1'
const direct_boot_client_pin = 'a77c25679d47032a8bac73a8ec7751dae271f7828973a8f9b722f004a0ad0c02'
const direct_boot_disabled_pin = '91e209b043a1f65379ecf16107263d513681bb56bbf25bbce11022d0824f9af5'
const file_limit = 32 * 1024 * 1024
const request_limit = 12
const seconds_limit = 600
const scope = 'Credential-free generic ART fixture transfer only; no Google account sign-in evidence.'

struct Asset {
	url string
	path string
	sha256 string
	bytes u64
}

struct Event {
	request int
	status int
	url string
	error string
}

struct Outcome {
	success bool
	reason string
	events []Event
	completed []string
}

fn valid_digest(pin string) bool {
	return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn external(root string) ! {
	parent := os.dir(root)
	name := os.file_name(root)
	if !root.starts_with('/') || root.contains_any('\x00\r\n\\') || name in ['', '.', '..']
		|| os.real_path(parent) != parent || parent + '/' + name != root {
		return error('canonical absolute external output required')
	}
	mut ancestor := parent
	for {
		if os.exists(ancestor + '/.git') { return error('output must be outside Git checkouts') }
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
}

fn create(path string) !int {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('fresh private output file required: ' + path) }
	return fd
}

fn write_fd(fd int, data []u8) ! {
	mut offset := 0
	for offset < data.len {
		n := unsafe { C.write(fd, &u8(data.data) + offset, uint(data.len - offset)) }
		if n <= 0 { return error('file write failed') }
		offset += int(n)
	}
}

fn write_json(path string, value string) ! {
	fd := create(path)!
	defer { C.close(fd) }
	write_fd(fd, (value + '\n').bytes())!
}

fn open_bounded(path string) !(int, u64) {
	if os.real_path(path) != path { return error('canonical regular input required') }
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open input') }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG
		|| st.st_size <= 0 || st.st_size > file_limit {
		C.close(fd)
		return error('nonempty regular input at most 32 MiB required')
	}
	return fd, u64(st.st_size)
}

// Snapshot only three bounded inputs. Verify bytes while copying; serving never
// resolves a request path to a filesystem path or opens another input.
fn snapshot(input Asset, output string) !Asset {
	if !valid_digest(input.sha256) { return error('pinned fixture digest required') }
	fd, size := open_bounded(input.path)!
	defer { C.close(fd) }
	out := create(output)!
	defer { C.close(out) }
	mut hash := sha256.new()
	mut count := u64(0)
	mut buffer := []u8{len: 65536}
	for {
		n := C.read(fd, buffer.data, uint(buffer.len))
		if n < 0 { return error('input read failed') }
		if n == 0 { break }
		count += u64(n)
		if count > size { return error('input grew during snapshot') }
		hash.write(buffer[..int(n)])!
		write_fd(out, buffer[..int(n)])!
	}
	if count != size || hash.sum([]u8{}).hex() != input.sha256 {
		return error('input size or SHA256 differs')
	}
	os.chmod(output, 0o400)!
	return Asset{url: input.url, path: output, sha256: input.sha256, bytes: count}
}

fn parse_request(header string) !(string, int) {
	if header.len > 8192 || !header.ends_with('\r\n\r\n')
		|| header.contains('\x00') || header.bytes().any(it < 32 && it !in [u8(`\r`), `\n`, `\t`]) {
		return error('invalid bounded HTTP headers')
	}
	lines := header[..header.len - 4].split('\r\n')
	parts := lines[0].split(' ')
	if parts.len != 3 || parts[2] !in ['HTTP/1.0', 'HTTP/1.1'] { return error('invalid request line') }
	if parts[0] != 'GET' { return parts[1], 405 }
	for line in lines[1..] {
		index := line.index(':') or { return error('invalid header') }
		if index == 0 { return error('empty header name') }
		name := line[..index].to_lower()
		if name == 'transfer-encoding' || (name == 'content-length' && line[index + 1..].trim_space() != '0') {
			return error('request body is not allowed')
		}
	}
	return parts[1], 200
}

fn read_request(mut connection net.TcpConn) !string {
	mut header := []u8{cap: 8192}
	mut buffer := []u8{len: 1024}
	for header.len < 8192 {
		n := connection.read(mut buffer[..int_min(buffer.len, 8192 - header.len)])!
		if n <= 0 { return error('incomplete request') }
		header << buffer[..n]
		if end := header.bytestr().index('\r\n\r\n') {
			if end + 4 != header.len { return error('request body or pipelining rejected') }
			return header.bytestr()
		}
	}
	return error('request headers exceed 8 KiB')
}

fn status(mut connection net.TcpConn, code int) ! {
	label := if code == 405 { 'Method Not Allowed' } else if code == 404 { 'Not Found' } else { 'Bad Request' }
	connection.write_string('HTTP/1.1 ' + code.str() + ' ' + label + '\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')!
}

fn send_asset(mut connection net.TcpConn, asset Asset, deadline time.Time) ! {
	fd, size := open_bounded(asset.path)!
	defer { C.close(fd) }
	if size != asset.bytes { return error('snapshot size changed') }
	connection.write_string('HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: '
		+ size.str() + '\r\nX-Content-SHA256: ' + asset.sha256 + '\r\nConnection: close\r\n\r\n')!
	mut hash := sha256.new()
	mut count := u64(0)
	mut buffer := []u8{len: 65536}
	for {
		if time.now() >= deadline { return error('absolute transfer deadline expired') }
		n := C.read(fd, buffer.data, uint(buffer.len))
		if n < 0 { return error('snapshot read failed') }
		if n == 0 { break }
		count += u64(n)
		if count > size { return error('snapshot grew') }
		hash.write(buffer[..int(n)])!
		if connection.write(buffer[..int(n)])! != int(n) { return error('short HTTP body write') }
	}
	if count != size || hash.sum([]u8{}).hex() != asset.sha256 { return error('snapshot SHA256 changed') }
}

fn serve_loop(mut listener net.TcpListener, assets []Asset, limit int, deadline time.Time) Outcome {
	mut events := []Event{}
	mut complete := []string{}
	listener.set_accept_deadline(deadline)
	for number in 1 .. limit + 1 {
		mut connection := listener.accept() or {
			return Outcome{reason: 'accept failed or deadline expired: ' + err.msg(), events: events, completed: complete}
		}
		read_deadline := time.now().add(5 * time.second)
		connection.set_read_deadline(if read_deadline < deadline { read_deadline } else { deadline })
		connection.set_write_deadline(deadline)
		mut code := 400
		mut url := ''
		mut message := ''
		header := read_request(mut connection) or { message = err.msg(); '' }
		if header != '' {
			url, code = parse_request(header) or { message = err.msg(); '', 400 }
		}
		mut found := -1
		if code == 200 {
			for index, asset in assets { if url == asset.url { found = index; break } }
			if found < 0 { code = 404 }
		}
		if code == 200 {
			send_asset(mut connection, assets[found], deadline) or { message = err.msg() }
			if message == '' && url !in complete { complete << url }
		} else {
			status(mut connection, code) or { message = err.msg() }
		}
		connection.close() or { message += ' close: ' + err.msg() }
		events << Event{number, code, url, message}
		if complete.len == assets.len { return Outcome{success: true, events: events, completed: complete} }
		if time.now() >= deadline { return Outcome{reason: 'absolute deadline expired', events: events, completed: complete} }
	}
	return Outcome{reason: 'request limit exhausted', events: events, completed: complete}
}

fn pinned_assets() []Asset {
	return [Asset{url: '/service-query-run', path: runner_path, sha256: runner_pin},
		Asset{url: '/client.apk', path: fixture_root + '/client/probe.apk', sha256: client_pin},
		Asset{url: '/disabled.apk', path: fixture_root + '/disabled/probe.apk', sha256: disabled_pin}]
}

fn direct_boot_assets() []Asset {
	return [Asset{url: '/direct-boot-run', path: direct_boot_runner, sha256: direct_boot_runner_pin},
		Asset{url: '/client.apk', path: direct_boot_fixture + '/client/probe.apk', sha256: direct_boot_client_pin},
		Asset{url: '/disabled.apk', path: direct_boot_fixture + '/disabled/probe.apk', sha256: direct_boot_disabled_pin}]
}

fn serve(root string, port string, is_direct_boot bool) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := if is_direct_boot { direct_boot_assets() } else { pinned_assets() }
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any(if is_direct_boot { 'vinix-direct-boot-http-v1' } else { 'vinix-service-query-http-v1' })
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println('SERVICE-QUERY-HTTP PASS three pinned files transferred')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	is_direct_boot := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--direct-boot'
	if !is_direct_boot && (os.args.len != 4 || os.args[1] != 'serve') {
		eprintln('usage: service-query-transfer serve [--direct-boot] FRESH_EXTERNAL_DIR PORT | --self-test FRESH_EXTERNAL_DIR')
		exit(2)
	}
	offset := if is_direct_boot { 1 } else { 0 }
	serve(os.args[2 + offset], os.args[3 + offset], is_direct_boot) or { eprintln(err); exit(1) }
}

fn get(address string, request string) !string {
	mut connection := net.dial_tcp(address)!
	defer { connection.close() or {} }
	connection.set_read_deadline(time.now().add(2 * time.second))
	connection.set_write_deadline(time.now().add(2 * time.second))
	connection.write_string(request)!
	mut result := []u8{}
	mut buffer := []u8{len: 65536}
	for {
		n := connection.read(mut buffer) or { break }
		if n == 0 { break }
		if result.len + n > 256 * 1024 { return error('test response exceeds bound') }
		result << buffer[..n]
	}
	return result.bytestr()
}

fn self_test(root string) ! {
	$if !net_nonblocking_sockets ? { return error('self-test requires nonblocking sockets') }
	external(root)!
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh self-test output required') }
	assert pinned_assets().len == 3 && direct_boot_assets().len == 3
	assert pinned_assets()[0].url == '/service-query-run' && direct_boot_assets()[0].url == '/direct-boot-run'
	for index, asset in direct_boot_assets() {
		assert valid_digest(asset.sha256) && asset.sha256 != pinned_assets()[index].sha256
		assert asset.path != pinned_assets()[index].path
	}
	for bad in ['POST /client.apk HTTP/1.1\r\n\r\n', 'HEAD /client.apk HTTP/1.0\r\n\r\n'] {
		_, code := parse_request(bad)!
		assert code == 405
	}
	for bad in ['GET / HTTP/2\r\n\r\n', 'GET / HTTP/1.1\r\nContent-Length: 1\r\n\r\n',
		'GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n', 'x'.repeat(8193)] {
		if _, _ := parse_request(bad) { return error('unsafe request accepted') }
	}
	body := 'binary\x00\xff\n'.repeat(20000)
	input := root + '/input'
	os.write_file(input, body)!
	asset := snapshot(Asset{url: '/one', path: input, sha256: sha256.hexhash(body)}, root + '/snapshot')!
	if _ := snapshot(Asset{path: input, sha256: '0'.repeat(64)}, root + '/wrong-pin') { return error('wrong input pin accepted') }
	os.symlink(input, root + '/link')!
	if _, _ := open_bounded(root + '/link') { return error('symlink input accepted') }
	os.write_file(root + '/empty', '')!
	if _, _ := open_bounded(root + '/empty') { return error('empty input accepted') }
	if _ := snapshot(Asset{path: input, sha256: sha256.hexhash(body)}, root + '/snapshot') { return error('existing output accepted') }
	assert os.lstat(root + '/snapshot')!.mode & 0o777 == 0o400
	assets := [asset, Asset{...asset, url: '/two'}, Asset{...asset, url: '/three'}]
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	address := listener.addr()!.str()
	worker := spawn serve_loop(mut listener, assets, 7, time.now().add(5 * time.second))
	for request in ['POST /one HTTP/1.1\r\n\r\n', 'GET /../input HTTP/1.1\r\n\r\n',
		'GET /%2e%2e/input HTTP/1.1\r\n\r\n', 'GET /one?query HTTP/1.1\r\n\r\n'] {
		response := get(address, request)!
		assert !response.starts_with('HTTP/1.1 200')
		assert response.ends_with('\r\n\r\n')
	}
	for name in ['/one', '/two', '/three'] {
		response := get(address, 'GET ' + name + ' HTTP/1.0\r\n\r\n')!
		assert response.starts_with('HTTP/1.1 200 OK\r\n')
		assert response.all_after('\r\n\r\n') == body
	}
	result := worker.wait()
	listener.close()!
	assert result.success && result.events.len == 7 && result.completed.len == 3
	mut limited := net.listen_tcp(.ip, '127.0.0.1:0')!
	limited_address := limited.addr()!.str()
	limited_worker := spawn serve_loop(mut limited, assets, 1, time.now().add(time.second))
	get(limited_address, 'GET /missing HTTP/1.0\r\n\r\n')!
	limited_result := limited_worker.wait()
	limited.close()!
	assert !limited_result.success && limited_result.reason == 'request limit exhausted'
	mut idle := net.listen_tcp(.ip, '127.0.0.1:0')!
	watch := time.new_stopwatch()
	idle_result := serve_loop(mut idle, assets, 1, time.now().add(50 * time.millisecond))
	idle.close()!
	assert !idle_result.success && watch.elapsed() < time.second
	write_json(root + '/self-test.json', json2.encode(result, prettify: true))!
	println('SERVICE-QUERY-HTTP SELF-TEST PASS pinned snapshots exact binary multi-buffer GET-only traversal request-limit absolute accept deadline')
}
