// SPDX-License-Identifier: GPL-2.0-or-later
module qualcore

import crypto.rand
import encoding.base64
import devcore
import io
import json2
import net
import os
import sourcecommand
import time

#include <signal.h>
#include <fcntl.h>
fn C.kill(i32, i32) i32
fn C.open(&char, int, ...) int
fn C.write(int, voidptr, usize) isize
fn C.close(int) int

fn write_private_http(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot create private HTTP fixture file') }
	defer { C.close(fd) }
	mut offset := 0
	for offset < text.len {
		written := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if written <= 0 { return error('private HTTP file write failed') }
		offset += int(written)
	}
}

// The same pinned qualifier executable supplies the small CGI application.
// The server must authenticate it before it may create the private artifact.
pub fn http_cgi() ! {
	if os.getenv('GATEWAY_INTERFACE') != 'CGI/1.1' || os.getenv('REMOTE_USER') != 'developer'
		|| os.getenv('REQUEST_METHOD') != 'POST' || os.getenv('CONTENT_LENGTH') != '2'
		|| os.getuid() != os.geteuid() || os.getgid() != os.getegid() {
		return error('CGI request/account failed validation')
	}
	mut input := []u8{len: 2}
	mut received := 0
	for received < 2 {
		n := os.stdin().read(mut input[received..])!
		if n == 0 { return error('CGI request body is incomplete') }
		received += n
	}
	if input != [u8(`4`), `2`] { return error('unexpected CGI body') }
	work := os.dir(os.dir(os.dir(os.executable())))
	write_private_http(work + '/project.data', '42')!
	print('Content-Type: application/json\r\n\r\n{"answer":42}')
}

struct HttpResponse {
	status int
	length int
	body string
}

fn response(text string) !HttpResponse {
	separator := text.index('\r\n\r\n') or { return error('incomplete HTTP response headers') }
	lines := text[..separator].split('\r\n')
	status := lines[0].split(' ')
	if status.len < 2 || status[0] !in ['HTTP/1.0', 'HTTP/1.1'] || status[1].len != 3
		|| !status[1].bytes().all(it >= `0` && it <= `9`) { return error('invalid HTTP status') }
	mut length := -1
	for line in lines[1..] {
		if line.to_lower().starts_with('content-length:') { length = line.all_after(':').trim_space().int() }
	}
	return HttpResponse{status[1].int(), length, text[separator + 4..]}
}

fn request(address string, method string, path string, authorization string, body string, deadline u64) !HttpResponse {
	mut connection := net.dial_tcp(address)!
	defer { connection.close() or {} }
	connection.set_read_timeout(2 * time.second)
	connection.set_write_timeout(2 * time.second)
	mut text := method + ' ' + path + ' HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n'
	if authorization != '' { text += 'Authorization: Basic ' + authorization + '\r\n' }
	if body != '' { text += 'Content-Length: ' + body.len.str() + '\r\n' }
	text += '\r\n' + body
	mut written := 0
	for written < text.len {
		if time.sys_mono_now() >= deadline { return error('HTTP workload deadline expired') }
		count := connection.write_string(text[written..])!
		if count <= 0 { return error('incomplete HTTP request write') }
		written += count
	}
	mut received := []u8{}
	mut buffer := []u8{len: 4096}
	for {
		if time.sys_mono_now() >= deadline { return error('HTTP workload deadline expired') }
		count := connection.read(mut buffer) or {
			if err is io.Eof { break }
			return error('HTTP response read failed')
		}
		if count == 0 { break }
		if received.len + count > 65536 { return error('HTTP response exceeds 64 KiB') }
		received << buffer[..count]
	}
	return response(received.bytestr())!
}

pub struct HttpProof {
pub:
	schema int = 1
	uid int
	unauthenticated int = 401
	wrong_password int = 401
	get int = 200
	head int = 200
	missing int = 404
	private_config int = 404
	traversal int = 400
	cgi int = 200
	repeated_requests int = 16
	group_retired bool = true
}

struct HttpSession {
	address string
	work string
	authorization string
	deadline u64
}

fn expect_http(actual HttpResponse, status int, body string, check_body bool) ! {
	if actual.status != status || (check_body && actual.body != body) {
		return error('HTTP check failed: status ' + actual.status.str() + ' expected ' + status.str()
			+ ', body bytes ' + actual.body.len.str() + ' expected ' + body.len.str())
	}
}

fn check_http_server(pid int, opaque voidptr) ! {
	context := unsafe { &HttpSession(opaque) }
	for {
		if sourcecommand.child_exited(pid)! { return error('HTTP server exited before readiness: ' + sourcecommand.child_exit(pid)!.return_code.str()) }
		if time.sys_mono_now() >= context.deadline { return error('HTTP server readiness deadline expired') }
		if actual := request(context.address, 'POST', '/cgi-bin/api', '', '42', context.deadline) {
			expect_http(actual, 401, '', false)!
			break
		}
		time.sleep(10 * time.millisecond)
	}
	expect_http(request(context.address, 'POST', '/cgi-bin/api', base64.encode_str('developer:wrong'), '42', context.deadline)!, 401, '', false)!
	if os.exists(context.work + '/project.data') { return error('unauthenticated CGI created an artifact') }
	expect_http(request(context.address, 'GET', '/index.html', context.authorization, '', context.deadline)!, 200, '42', true)!
	head := request(context.address, 'HEAD', '/index.html', context.authorization, '', context.deadline)!
	expect_http(head, 200, '', true)!
	if head.length != 2 { return error('HTTP HEAD length changed') }
	expect_http(request(context.address, 'GET', '/missing', context.authorization, '', context.deadline)!, 404, '', false)!
	expect_http(request(context.address, 'GET', '/server.conf', context.authorization, '', context.deadline)!, 404, '', false)!
	expect_http(request(context.address, 'GET', '/%2e%2e/server.conf', context.authorization, '', context.deadline)!, 400, '', false)!
	expect_http(request(context.address, 'POST', '/cgi-bin/api', context.authorization, '42', context.deadline)!, 200, '{"answer":42}', true)!
	data := os.stat(context.work + '/project.data')!
	if os.read_file(context.work + '/project.data')! != '42' || data.mode & 0o777 != 0o600 || data.uid != u32(os.getuid()) {
		return error('CGI artifact content or privacy failed validation')
	}
	for _ in 0 .. 16 {
		if sourcecommand.child_exited(pid)! { return error('HTTP server exited during requests') }
		expect_http(request(context.address, 'GET', '/index.html', context.authorization, '', context.deadline)!, 200, '42', true)!
	}
	// The leader remains unreaped, preserving its group identity until the
	// command owner retires every connection/CGI descendant and reaps it.
	if C.kill(-pid, C.SIGTERM) != 0 { return error('cannot stop owned HTTP server group') }
	for !sourcecommand.child_exited(pid)! {
		if time.sys_mono_now() >= context.deadline { return error('HTTP server retirement deadline expired') }
		time.sleep(10 * time.millisecond)
	}
}

fn (mut runner Runner) http_project() ! {
	busybox := tool('busybox')!
	os.mkdir(runner.work + '/www', mode: 0o700)!
	os.mkdir(runner.work + '/www/cgi-bin', mode: 0o700)!
	runner.write('www/index.html', '42')!
	helper := runner.work + '/www/cgi-bin/api'
	os.cp(os.executable(), helper)!
	os.chmod(helper, 0o755)!
	if devcore.file_hash(helper)! != devcore.file_hash(os.executable())! { return error('CGI helper pin changed during copy') }
	password := rand.bytes(32)!.hex()
	write_private_http(runner.work + '/server.conf', '/:developer:' + password + '\n')!
	st := os.stat(runner.work + '/server.conf')!
	if st.uid != u32(os.getuid()) || st.mode & 0o777 != 0o600 { return error('HTTP configuration is not private to the account') }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	address := '127.0.0.1:' + listener.addr()!.port()!.str()
	listener.close()!
	context := HttpSession{address, runner.work, base64.encode_str('developer:' + password),
		time.sys_mono_now() + u64(runner.timeout_seconds) * u64(time.second)}
	argv := [busybox, 'httpd', '-f', '-p', address, '-h', runner.work + '/www', '-c', runner.work + '/server.conf']
	log := runner.work + '/command-0.log'
	hash := devcore.file_hash(busybox)!
	result := sourcecommand.run_logged_owned(argv, runner.env, unsafe { nil }, log, false, runner.work,
		check_http_server, unsafe { &context }, 1) or {
		runner.commands << CommandReceipt{argv, hash, -1, log, {}}
		return err
	}
	runner.commands << CommandReceipt{argv, hash, result.status, log, {}}
	if result.status != -C.SIGTERM { return error('HTTP server did not retire through the owned group') }
	if os.stat(log)!.size > 1024 * 1024 || os.read_file(log)!.contains(password) || os.read_file(log)!.contains(context.authorization) {
		return error('HTTP log bounds or credential isolation failed')
	}
	runner.write('server.json', json2.encode(HttpProof{uid: os.getuid()}) + '\n')!
}
