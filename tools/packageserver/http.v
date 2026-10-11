// SPDX-License-Identifier: GPL-2.0-or-later
module packageserver

import hostclipboard
import net
import os
import strconv
import time

#include <poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <sys/socket.h>
struct C.pollfd { mut: fd i32 events i16 revents i16 }
fn C.poll(&C.pollfd, usize, i32) i32
fn C.rename(&char, &char) i32
fn C.fsync(i32) i32
fn C.mkdtemp(&char) &char

@[heap]
pub struct Server {
pub:
	config Config
	port int
pub mut:
	clipboard_reader fn (&Server) !string = default_clipboard
	clipboard_context string
mut:
	listener &net.TcpListener = unsafe { nil }
	stopped i32
}

fn default_clipboard(_server &Server) !string { return hostclipboard.read(cancelled)! }

pub fn start(config Config) !&Server {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:${config.port}', net.ListenOptions{})!
	mut keep := false
	defer { if !keep { listener.close() or {} } }
	if C.fcntl(listener.sock.handle, C.F_SETFD, C.FD_CLOEXEC) != 0 { return os.error_posix() }
	listener.set_accept_timeout(100 * time.millisecond)
	port := int(listener.addr()!.port()!)
	if config.ready != '' { os.write_file(config.ready, '${port}\n')! }
	keep = true
	eprintln('qemu-package-store: listening on 127.0.0.1:${port}, storing ' + config.store)
	return &Server{config: config, port: port, listener: listener}
}

pub fn (mut server Server) stop() { unsafe { C.__atomic_store_n(&server.stopped, 1, C.__ATOMIC_RELAXED) } }
fn (server &Server) stopping() bool { return cancelled() || unsafe { C.__atomic_load_n(&server.stopped, C.__ATOMIC_RELAXED) } != 0 }

struct Worker { mut: done i32 }
struct Running {
	task thread
	owner &Worker
}

pub fn (mut server Server) serve() ! {
	mut workers := []Running{}
	defer {
		server.stop()
		server.listener.close() or { eprintln(err) }
		for worker in workers { worker.task.wait() }
	}
	for !server.stopping() {
		for index := workers.len - 1; index >= 0; index-- {
			if unsafe { C.__atomic_load_n(&workers[index].owner.done, C.__ATOMIC_RELAXED) } != 0 {
				workers[index].task.wait(); workers.delete(index)
			}
		}
		mut connection := server.listener.accept() or { if server.stopping() { break }; if err.code() == net.err_timed_out_code { continue }; return err }
		if C.fcntl(connection.handle, C.F_SETFD, C.FD_CLOEXEC) != 0 || C.fcntl(connection.handle, C.F_SETFL, C.O_NONBLOCK) != 0 {
			connection.close() or {}; continue
		}
		owner := &Worker{}
		task := spawn serve_request(server, mut connection, owner)
		workers << Running{task, owner}
	}
}

struct Request {
	server &Server
	fd int
mut:
	pending []u8
	position int
}

fn (request &Request) ready(writing bool) ! {
	mut descriptor := C.pollfd{fd: request.fd, events: i16(if writing { C.POLLOUT } else { C.POLLIN })}
	for {
		if request.server.stopping() { return error('package service interrupted') }
		result := C.poll(&descriptor, 1, 100)
		if result > 0 { return }
		if result < 0 && C.errno != C.EINTR { return os.error_posix() }
	}
}

fn (mut request Request) read(mut buffer []u8) !int {
	if request.position < request.pending.len {
		count := int_min(buffer.len, request.pending.len - request.position)
		copy(mut buffer, request.pending[request.position..request.position + count])
		request.position += count
		return count
	}
	for {
		request.ready(false)!
		count := C.recv(request.fd, buffer.data, usize(buffer.len), 0)
		if count < 0 { if C.errno in [C.EINTR, C.EAGAIN] { continue }; return os.error_posix() }
		return int(count)
	}
	return 0
}

fn (mut request Request) line() !string {
	mut text := []u8{}
	for {
		if request.position >= request.pending.len {
			request.pending = []u8{}
			request.position = 0
			mut buffer := []u8{len: 4096}
			count := request.read(mut buffer)!
			if count == 0 { return error('short HTTP request') }
			request.pending = buffer[..count].clone()
		}
		byte := request.pending[request.position]; request.position++
		if byte == `\n` { return text.bytestr().trim_right('\r') }
		if text.len >= 65536 { return error('HTTP line too long') }
		text << byte
	}
	return ''
}

fn (request &Request) send(data []u8) ! {
	mut position := 0
	for position < data.len {
		request.ready(true)!
		count := unsafe { C.send(request.fd, &data[position], usize(data.len - position), 0) }
		if count < 0 { if C.errno in [C.EINTR, C.EAGAIN] { continue }; return os.error_posix() }
		if count == 0 { return error('cannot send HTTP response') }
		position += int(count)
	}
}

fn (request &Request) headers(status int, size u64, mime string, no_store bool) ! {
	reason := match status { 200 { 'OK' } 204 { 'No Content' } 400 { 'Bad Request' } 404 { 'Not Found' } 413 { 'Request Entity Too Large' } 501 { 'Not Implemented' } else { 'Service Unavailable' } }
	mut text := 'HTTP/1.0 ${status} ${reason}\r\nServer: VinixPackageStore/1\r\n'
	if status != 204 { text += 'Content-Length: ${size}\r\nContent-Type: ${mime}\r\n' }
	if no_store { text += 'Cache-Control: no-store\r\n' }
	request.send((text + '\r\n').bytes())!
}

fn (request &Request) response(status int, body string, mime string, no_store bool) ! {
	request.headers(status, u64(body.len), mime, no_store)!
	if body != '' { request.send(body.bytes())! }
}

fn (request &Request) failure(status int, text string) ! {
	body := '<!DOCTYPE HTML><html><body><h1>Error ${status}</h1><p>' + text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;') + '</p></body></html>\n'
	request.response(status, body, 'text/html; charset=utf-8', false)!
}

fn serve_request(server &Server, mut connection net.TcpConn, owner &Worker) {
	defer { unsafe { C.__atomic_store_n(&owner.done, 1, C.__ATOMIC_RELAXED) } }
	defer { connection.close() or {} }
	mut request := Request{server: server, fd: connection.handle}
	request.dispatch() or {
		if !server.stopping() { eprintln('qemu-package-store: [${err.code()}] ' + err.msg()) }
	}
}

fn (mut request Request) dispatch() ! {
	first := request.line()!.fields()
	if first.len != 3 || !first[2].starts_with('HTTP/1.') { request.failure(400, 'invalid HTTP request')!; return }
	mut headers := map[string]string{}
	for _ in 0 .. 100 {
		line := request.line()!
		if line == '' { break }
		if !line.contains(':') { request.failure(400, 'invalid HTTP header')!; return }
		name := line.all_before(':').to_lower()
		if name !in headers { headers[name] = line.all_after(':').trim_space() }
	}
	if first[0] == 'PUT' {
		if first[1] != '/packages' { request.failure(404, 'Not Found')!; return }
		length := strconv.parse_int(headers['content-length'], 10, 64) or { -1 }
		if length <= 0 || length > request.server.config.maximum { request.failure(413, 'invalid overlay size')!; return }
		request.save(length) or { request.failure(400, err.msg())!; return }
		request.response(204, '', '', false)!; return
	}
	if first[0] != 'GET' { request.failure(501, 'Unsupported method')!; return }
	if first[1] == '/health' { request.response(204, '', '', false)!; return }
	if first[1] == '/clipboard' && request.server.config.clipboard {
		content := request.server.clipboard_reader(request.server) or { request.failure(503, err.msg())!; return }
		request.response(200, content, 'text/plain; charset=utf-8', true)!; return
	}
	if request.server.config.source != '' {
		if first[1] == '/vinix-source.tar' {
			work := temporary()!
			defer { os.rmdir_all(work) or { eprintln(err) } }
			archive := work + '/source.tar'
			snapshot(request.server.config, archive, work) or { request.failure(503, err.msg())!; return }
			request.send_file(archive, 'application/x-tar')!; return
		}
		parts := first[1].trim_left('/').split('/')
		apps := {'vinix-files': 'files-live', 'vinix-activity': 'activity-live', 'vinix-settings': 'settings-live'}
		if parts.len == 2 && parts[0] in apps && parts[1] in ['binary', 'version'] {
			path := request.server.config.source + '/build-aarch64-desktop-apps/' + apps[parts[0]] + '/' + if parts[1] == 'version' { 'version' } else { parts[0] }
			if !os.exists(path) { request.failure(404, 'Not Found')!; return }
			request.send_file(path, 'application/octet-stream')!; return
		}
	}
	request.failure(404, 'Not Found')!
}

fn (request &Request) send_file(path string, mime string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	if C.fcntl(file.fd, C.F_SETFD, C.FD_CLOEXEC) != 0 { return os.error_posix() }
	request.headers(200, os.file_size(path), mime, true)!
	mut buffer := []u8{len: 1024 * 1024}
	for {
		if request.server.stopping() { return error('package service interrupted') }
		count := file.read(mut buffer)!
		if count == 0 { break }
		request.send(buffer[..count])!
	}
}

fn (mut request Request) save(length i64) ! {
	destination := request.server.config.store
	parent := os.dir(destination)
	os.mkdir_all(parent)!
	mut name := (parent + '/.' + os.file_name(destination) + '.XXXXXX\x00').bytes()
	fd := C.mkstemp(name.data)
	if fd < 0 { return os.error_posix() }
	mut open := true
	defer { if open { C.close(fd) } }
	path := name.bytestr().all_before('\x00')
	mut published := false
	defer { if !published { os.rm(path) or {} } }
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 { return os.error_posix() }
	mut remaining := length
	mut buffer := []u8{len: 1024 * 1024}
	for remaining > 0 {
		mut portion := unsafe { buffer[..int_min(int(remaining), buffer.len)] }
		count := request.read(mut portion)!
		if count == 0 { return error('short request body') }
		mut written := 0
		for written < count {
			amount := unsafe { C.write(fd, &portion[written], usize(count - written)) }
			if amount < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
			if amount == 0 { return error('cannot save package overlay') }
			written += int(amount)
		}
		remaining -= count
	}
	if C.fsync(fd) != 0 { return os.error_posix() }
	open = false
	if C.close(fd) != 0 { return os.error_posix() }
	validate_overlay(path, request.server.config.maximum)!
	if C.rename(path.str, destination.str) != 0 { return os.error_posix() }
	published = true
	directory := unsafe { C.open(parent.str, C.O_RDONLY | C.O_CLOEXEC) }
	if directory < 0 { return os.error_posix() }
	defer { C.close(directory) }
	if C.fsync(directory) != 0 { return os.error_posix() }
	eprintln('qemu-package-store: saved ${length} bytes to ' + destination)
}

pub fn temporary() !string {
	base := if os.getenv('TMPDIR') != '' { os.getenv('TMPDIR') } else { os.temp_dir() }
	mut name := (base + '/vinix-source-store.XXXXXX\x00').bytes()
	if isnil(C.mkdtemp(name.data)) { return os.error_posix() }
	return name.bytestr().all_before('\x00')
}
