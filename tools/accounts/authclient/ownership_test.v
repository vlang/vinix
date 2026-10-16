// SPDX-License-Identifier: GPL-2.0-or-later
module authclient

import authproto
import os

#include <fcntl.h>
#include <sys/wait.h>
fn C.bind(int, voidptr, u32) int
fn C.listen(int, int) int
fn C.accept(int, voidptr, voidptr) int
fn C.fork() int
fn C.waitpid(int, &i32, int) int
fn C._exit(int)
fn C.usleep(u32) int
fn C.unlink(&char) int
fn C.pipe(&i32) int
fn C.kill(int, int) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn client_cycles() int { $if auth_client_baseline ? { return 5 }; return 1000 }
fn client_error(err IError) string {
	message := err.msg()
	unsafe { err.free() }
	return message
}
fn client_fds() int {
	mut count := 0
	for fd in 0 .. 128 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}
fn client_window(label string) {
	$if track_heap ? {
		kept := C.vinix_heap_end()
		println('AUTH CLIENT ' + label + ' retained ' + kept.str() + ' bytes')
		$if !auth_client_baseline ? { assert kept == 0, kept.str() }
	}
}
fn client_settle() { $if auth_client_guest ? { assert C.usleep(7_000_000) == 0 } }

// The child serves one bounded cohort. Only the parent's complete client call
// is tracked; the listener, input buffers and variadic table belong to the test.
struct ClientServer { mut: pid int ack int }
fn (mut server ClientServer) close() {
	if server.pid > 0 {
		C.kill(server.pid, 15)
		mut status := i32(0)
		C.waitpid(server.pid, unsafe { &status }, 0)
		C.close(server.ack)
		server.pid = -1
	}
}
fn (server &ClientServer) acknowledge() {
	mut byte := u8(0)
	assert C.read(server.ack, unsafe { &byte }, 1) == 1 && byte == 1
}
fn client_server(path string, response []u8, empty_request bool) ClientServer {
	mut location := C.sockaddr_un{}
	location.sun_family = u16(C.AF_UNIX)
	unsafe { vmemcpy(&location.sun_path[0], path.str, path.len) }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	assert fd >= 0
	assert C.bind(fd, unsafe { &location }, u32(sizeof(C.sockaddr_un))) == 0
	assert C.listen(fd, 8) == 0
	mut ack := [2]i32{}
	assert C.pipe(unsafe { &ack[0] }) == 0
	pid := C.fork()
	assert pid >= 0
	if pid == 0 {
		C.close(ack[0])
		for _ in 0 .. client_cycles() {
			peer := C.accept(fd, unsafe { nil }, unsafe { nil })
			if peer < 0 { C._exit(80) }
			if empty_request {
				mut byte := u8(0)
				if C.read(peer, unsafe { &byte }, 1) != 0 { C._exit(81) }
			} else {
				mut request := authproto.read_frame(peer) or { C._exit(82); return ClientServer{} }
				if request.code != authproto.op_verify || request.fields.len != 2
					|| request.fields[0] != [u8(0), 1, 255] || request.fields[1] != [u8(7), 0, 8] { C._exit(83) }
				request.close()
				if response.len > 0 && C.write(peer, response.data, usize(response.len)) != response.len { C._exit(84) }
			}
			C.close(peer)
			byte := u8(1)
			if C.write(ack[1], unsafe { &byte }, 1) != 1 { C._exit(85) }
		}
		C.close(fd)
		C._exit(0)
	}
	C.close(fd)
	C.close(ack[1])
	return ClientServer{ pid: pid, ack: ack[0] }
}
fn client_reap(mut server ClientServer, path string) {
	mut status := i32(0)
	pid := server.pid
	assert C.waitpid(pid, unsafe { &status }, 0) == pid && status == 0, status.str()
	C.close(server.ack)
	server.pid = -1
	assert C.unlink(path.str) == 0
	client_settle()
}
fn client_fields() [][]u8 {
	mut fields := [][]u8{cap: 2}
	for bytes in [[u8(0), 1, 255], [u8(7), 0, 8]] {
		unsafe { fields.push_many(&bytes, 1) }
	}
	return fields
}
fn client_reset(mut fields [][]u8) {
	fields[0][0] = 0; fields[0][1] = 1; fields[0][2] = 255
	fields[1][0] = 7; fields[1][1] = 0; fields[1][2] = 8
}
fn client_wiped(fields [][]u8) {
	assert fields.len == 2 && fields[0].len == 3 && fields[1].len == 3
	assert fields[0].all(it == 0) && fields[1].all(it == 0)
}
fn client_free(fields [][]u8) { unsafe { for field in fields { field.free() }; (&array(&fields)).free() } }

fn test_complete_transactions_retire_storage_and_preserve_borrowed_fields() {
	directory := os.temp_dir() + '/vinix-auth-client-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {}; unsafe { directory.free() } }
	path := directory + '/service.sock'; defer { unsafe { path.free() } }
	mut fields := client_fields(); defer { client_free(fields) }
	mut response := authproto.Frame{ code: authproto.status_denied, fields: client_fields() }
	defer { response.close() }
	wire := authproto.encode(response)!; defer { unsafe { wire.free() } }
	before := client_fds()
	for mode in [0, 1, 2]! {
		// root checking accepts a real root peer, and sends no bytes to an
		// ordinary peer. The same fixture runs with both identities in guests.
		guard_rejects := mode == 2 && os.geteuid() != 0
		mut server := client_server(path, wire, guard_rejects)
		defer { server.close() }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. client_cycles() {
			client_reset(mut fields)
			if guard_rejects {
				if mut reply := ask_root(path, authproto.op_verify, ...fields) { reply.close(); assert false }
				else { message := client_error(err); assert message == 'the authentication service peer is not root'; unsafe { message.free() } }
			} else {
				mut request := authproto.Frame{ code: authproto.op_verify, fields: unsafe { fields } }
				mut reply := if mode == 0 { transact(path, mut request)! }
					else if mode == 1 { ask(path, authproto.op_verify, ...fields)! }
					else { ask_root(path, authproto.op_verify, ...fields)! }
				assert reply.code == response.code && reply.fields == response.fields
				client_wiped(fields)
				reply.close(); reply.close()
			}
			client_wiped(fields)
			server.acknowledge()
		}
		client_window(if mode == 0 { 'transact' } else if mode == 1 { 'ask' } else { 'ask_root' })
		client_reap(mut server, path)
		assert client_fds() == before
	}
	println('AUTH CLIENT successful transactions and root peer decisions preserve ownership and descriptors PASS')
}

fn test_refusals_erase_borrowed_requests_and_retire_transport_scratch() {
	directory := os.temp_dir() + '/vinix-auth-refusal-' + os.getpid().str()
	os.mkdir(directory, mode: 0o700)!
	defer { os.rmdir_all(directory) or {}; unsafe { directory.free() } }
	path := directory + '/service.sock'; defer { unsafe { path.free() } }
	mut fields := client_fields(); defer { client_free(fields) }
	mut response := authproto.Frame{ fields: client_fields() }; defer { response.close() }
	wire := authproto.encode(response)!; defer { unsafe { wire.free() } }
	mut malformed := wire.clone(); malformed[0] = 0; defer { unsafe { malformed.free() } }
	mut oversized := wire.clone(); oversized[20] = 255; defer { unsafe { oversized.free() } }
	mut bad_count := wire.clone(); bad_count[8] = 255; defer { unsafe { bad_count.free() } }
	// EOF before header, in header, after a complete first field, bad magic,
	// and oversized late field. Each preserves the public generic diagnosis.
	before := client_fds()
	for mode in 0 .. 7 {
		data := match mode { 0 { unsafe { wire[..0] } } 1 { unsafe { wire[..5] } }
			2 { unsafe { wire[..20] } } 3 { unsafe { wire[..wire.len - 1] } }
			4 { malformed } 5 { bad_count } else { oversized } }
		mut server := client_server(path, data, false)
		defer { server.close() }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. client_cycles() {
			client_reset(mut fields)
			if mut reply := ask(path, authproto.op_verify, ...fields) { reply.close(); assert false }
			else { message := client_error(err); assert message == 'the authentication service is busy or refused the request'; unsafe { message.free() } }
			client_wiped(fields)
			server.acknowledge()
		}
		client_window(match mode { 0 { 'reply EOF' } 1 { 'partial header' } 2 { 'partial length' }
			3 { 'partial body' } 4 { 'bad magic' } 5 { 'excess field count' } else { 'oversized late field' } })
		client_reap(mut server, path)
		assert client_fds() == before
	}
	long_path := '/'.repeat(100); defer { unsafe { long_path.free() } }
	for socket in [long_path, path] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. client_cycles() {
			client_reset(mut fields)
			if mut reply := ask(socket, authproto.op_verify, ...fields) { reply.close(); assert false }
			else { message := client_error(err); assert message in ['socket path too long', 'the authentication service is not running']; unsafe { message.free() } }
			client_wiped(fields)
		}
		client_window('unavailable/path refusal')
		assert client_fds() == before
		client_settle()
	}
	mut invalid := authproto.Frame{ fields: [][]u8{len: authproto.max_fields + 1} }
	defer { invalid.close() }
	mut server := client_server(path, []u8{}, true)
	defer { server.close() }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. client_cycles() {
		if mut reply := transact(path, mut invalid) { reply.close(); assert false }
		else { message := client_error(err); assert message == 'too many fields'; unsafe { message.free() } }
		server.acknowledge()
	}
	client_window('invalid request')
	client_reap(mut server, path)
	assert client_fds() == before
	println('AUTH CLIENT interrupted replies and local refusals erase requests and preserve descriptors PASS')
}
