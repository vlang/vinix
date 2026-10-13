// SPDX-License-Identifier: GPL-2.0-or-later
module qualcore

import os
import sourcecommand
import net
import time

fn test_http_status_and_header_framing_reject_truncated_or_invalid_responses() {
	parsed := response('HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n42')!
	assert parsed.status == 200 && parsed.length == 2 && parsed.body == '42'
	for invalid in ['', 'HTTP/1.0 200 OK\r\nContent-Length: 2', 'HTTP/1.0 two OK\r\n\r\n', 'SMTP 200 OK\r\n\r\n'] {
		if _ := response(invalid) { assert false, 'invalid HTTP response accepted' }
	}
	if _ := expect_http(HttpResponse{200, 0, ''}, 401, '', false) {
		assert false, 'unauthorized success accepted'
	}
}

fn test_http_artifact_creation_refuses_existing_files_and_symlink_aliases() {
	root := sourcecommand.temporary('vinix-http-private')!
	defer { os.rmdir_all(root) or {} }
	write_private_http(root + '/token', 'sentinel')!
	assert os.stat(root + '/token')!.mode & 0o777 == 0o600
	if _ := write_private_http(root + '/token', 'overwrite') { assert false, 'existing private file overwritten' }
	os.symlink('token', root + '/alias')!
	if _ := write_private_http(root + '/alias', 'overwrite') { assert false, 'private file alias followed' }
	assert os.read_file(root + '/token')! == 'sentinel'
}

fn incomplete_http_server(mut listener net.TcpListener) ! {
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.set_read_timeout(time.second)
	mut buffer := []u8{len: 4096}
	mut text := ''
	for !text.contains('\r\n\r\n') { text += buffer[..connection.read(mut buffer)!].bytestr() }
	connection.write_string('HTTP/1.0 200 OK\r\n')!
}

fn test_http_transport_failure_identifies_request_without_credentials() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	listener.set_accept_timeout(time.second)
	worker := spawn incomplete_http_server(mut listener)
	defer { worker.wait() or { panic(err) } }
	address := '127.0.0.1:' + listener.addr()!.port()!.str()
	if _ := request(address, 'GET', '/index.html', 'private-authorization', 'private-body',
		time.sys_mono_now() + u64(3 * time.second)) {
		assert false, 'incomplete HTTP response accepted'
	} else {
		assert err.msg().contains('HTTP GET /index.html response: incomplete HTTP response headers')
		assert !err.msg().contains('private-authorization') && !err.msg().contains('private-body')
	}
}
