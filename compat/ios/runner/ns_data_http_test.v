// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
type DataHTTPSend = fn (u64, u64, u64) u64
struct DataHTTPApi { native bool send u64 }
fn (api DataHTTPApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn (api DataHTTPApi) msg(object u64, name &char, argument u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { DataHTTPSend(voidptr(api.send))(object, selector, argument) }
}
fn (api DataHTTPApi) url(text string) u64 {
	value := api.msg(api.cls(c'NSString'), c'stringWithUTF8String:', u64(text.str))
	return api.msg(api.cls(c'NSURL'), c'URLWithString:', value)
}
fn (api DataHTTPApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls(c'NSAutoreleasePool'), c'new', 0) } }
	return objc_pool_push()
}
fn (api DataHTTPApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}

struct DataHTTPListener { fd int port int }
fn data_http_listener() DataHTTPListener {
	fd := C.socket(C.AF_INET, C.SOCK_STREAM, 0)
	assert fd >= 0;
	mut address := [16]u8{}
	$if macos { address[0] = 16; address[1] = u8(C.AF_INET) } $else { address[0] = u8(C.AF_INET) }
	address[4] = 127; address[7] = 1
	assert C.bind(fd, &address[0], 16) == 0 && C.listen(fd, 8) == 0;
	mut size := u32(16)
	assert C.getsockname(fd, &address[0], &size) == 0;
	assert C.fcntl(fd, C.F_SETFL, usize(C.O_NONBLOCK)) == 0;
	return DataHTTPListener{fd, int(address[2]) * 256 + int(address[3])}
}

fn data_http_server_tls(mut stream DataHTTPStream, cert string, key string, mut private_key C.mbedtls_pk_context) bool {
	stream.tls = true
	C.mbedtls_ssl_init(&stream.ssl); C.mbedtls_ssl_config_init(&stream.config)
	C.mbedtls_x509_crt_init(&stream.ca); C.mbedtls_ctr_drbg_init(&stream.rng); C.mbedtls_entropy_init(&stream.entropy)
	if C.mbedtls_ctr_drbg_seed(&stream.rng, C.mbedtls_entropy_func, &stream.entropy, c'http-test', 9) != 0
		|| C.mbedtls_x509_crt_parse_file(&stream.ca, cert.str) != 0
		|| C.mbedtls_pk_parse_keyfile(&private_key, key.str, unsafe { nil }, C.mbedtls_ctr_drbg_random, &stream.rng) != 0
		|| C.mbedtls_ssl_config_defaults(&stream.config, C.MBEDTLS_SSL_IS_SERVER, C.MBEDTLS_SSL_TRANSPORT_STREAM, C.MBEDTLS_SSL_PRESET_DEFAULT) != 0 { return false }
	C.mbedtls_ssl_conf_rng(&stream.config, C.mbedtls_ctr_drbg_random, &stream.rng)
	if C.mbedtls_ssl_conf_own_cert(&stream.config, &stream.ca, &private_key) != 0 || C.mbedtls_ssl_setup(&stream.ssl, &stream.config) != 0 { return false }
	stream.net.fd = stream.fd
	C.mbedtls_ssl_set_bio(&stream.ssl, &stream.net, unsafe { &C.mbedtls_ssl_send_t(voidptr(data_http_tls_send)) }, C.mbedtls_net_recv, unsafe { nil })
	for {
		result := C.mbedtls_ssl_handshake(&stream.ssl)
		if result == 0 { return true }
		if !stream.retry(result) { return false }
	}
	return false
}

// One listener per case; all requests and responses stay on loopback. TLS
// contexts and keys outlive the connection and are released after it closes.
fn data_http_serve(listener DataHTTPListener, replies []string, paths []string, tls bool, delay bool) bool {
	defer { C.close(listener.fd) }
	for i, reply in replies {
		deadline := time.sys_mono_now() + 5 * time.second
		if !data_http_wait(listener.fd, false, deadline) { return false }
		fd := C.accept(listener.fd, unsafe { nil }, unsafe { nil })
		if fd < 0 { return false }
		data_http_no_sigpipe(fd)
		assert C.fcntl(fd, C.F_SETFL, usize(C.O_NONBLOCK)) == 0;
		mut key := C.mbedtls_pk_context{}
		C.mbedtls_pk_init(&key)
		defer { C.mbedtls_pk_free(&key) }
		mut stream := &DataHTTPStream{fd: fd, deadline: deadline}
		defer { stream.close(); unsafe { free(stream) } }
		if tls && !data_http_server_tls(mut stream, os.getenv('VINIX_IOS_HTTP_CERT'), os.getenv('VINIX_IOS_HTTP_KEY'), mut key) { return false }
		mut headers := []u8{cap: data_http_headers}; headers.flags |= .noslices
		defer { unsafe { headers.free() } }
		line := stream.line(mut headers) or { return false }
		assert line == 'GET ${paths[i]} HTTP/1.1', line;
		for { header := stream.line(mut headers) or { return false }; if header.len == 0 { break } }
		if delay { time.sleep(100 * time.millisecond) }
		stream.send(reply)
		if tls { C.mbedtls_ssl_close_notify(&stream.ssl) }
	}
	return true
}

fn data_http_case(reply string, expected string, succeeds bool) {
	listener := data_http_listener()
	worker := spawn data_http_serve(listener, [reply], ['/binary%20data?q=%00'], false, false)
	url := 'http://127.0.0.1:${listener.port}/binary%20data?q=%00#fragment'
	if body := data_http_fetch(url, '', 2 * time.second) {
		assert succeeds && body.bytestr() == expected, 'unexpected HTTP body';
		unsafe { body.free() }
	} else { assert !succeeds, reply; }
	assert worker.wait();
}

fn test_data_http_framing() {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) == 0;
	data_http_no_sigpipe(pair[0])
	C.close(pair[1])
	mut context := C.mbedtls_net_context{fd: pair[0]}
	assert data_http_tls_send(&context, c'x', 1) == C.MBEDTLS_ERR_NET_CONN_RESET;
	C.close(pair[0])
	mut bytes := []u8{len: 8193}
	for i in 0 .. bytes.len { bytes[i] = u8(i % 251) }
	body := bytes.bytestr()
	data_http_case('HTTP/1.1 200 OK\r\nContent-Length: ${body.len}\r\n\r\n${body}', body, true)
	data_http_case('HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n', '', true)
	data_http_case('HTTP/1.1 204 No Content\r\n\r\n', '', true)
	data_http_case('HTTP/1.0 200 OK\r\n\r\nclose body', 'close body', true)
	data_http_case('HTTP/1.1 103 Early Hints\r\nLink: </a>\r\n\r\nHTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nTransfer-Encoding: Chunked\r\n\r\n3;ext=1\r\nabc\r\n2\r\nde\r\n0\r\nX-Trailer: yes\r\n\r\n', 'abcde', true)
	for reply in [
		'HTTP/1.1 404 Missing\r\nContent-Length: 0\r\n\r\n',
		'HTTP/1.1 500 Error\r\nContent-Length: 0\r\n\r\n',
		'HTTP/1.1 101 Switching Protocols\r\n\r\n',
		'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabc',
		'HTTP/1.1 200 OK\r\nContent-Length: 16777217\r\n\r\n',
		'HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n',
		'HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n',
		'HTTP/1.1 200 OK\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n',
		'HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n',
		'HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n',
		'HTTP/1.1 200 OK\r\nBad Header: x\r\n\r\n',
		'HTTP/1.1 200 OK\n\n',
		'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1000001\r\n',
		'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nab',
		'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\naX\n0\r\n\r\n',
		'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nbad\r\n\r\n',
		'HTTP/1.1 204 No Content\r\nContent-Length: 1\r\n\r\nx',
		'HTTP/1.1 200 OK\r\nX-Large: ' + 'x'.repeat(data_http_headers) + '\r\n\r\n',
	] { data_http_case(reply, '', false) }
	println('IOS-DATA-HTTP-FRAMING: binary, empty, EOF, informational, chunked, trailers; malformed, truncated and oversized responses return nil')
}

fn test_data_http_redirects_and_timeout() {
	listener := data_http_listener()
	base := 'http://127.0.0.1:${listener.port}'
	replies := ['HTTP/1.1 302 Found\r\nLocation: ${base}/dir/a\r\n\r\n', 'HTTP/1.1 307 Found\r\nLocation: b\r\n\r\n', 'HTTP/1.1 308 Found\r\nLocation: ?query\r\n\r\n', 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok']
	worker := spawn data_http_serve(listener, replies, ['/start', '/dir/a', '/dir/b', '/dir/b?query'], false, false)
	body := data_http_fetch(base + '/start', '', 2 * time.second) or { panic('redirect failed') }
	assert body.bytestr() == 'ok' && worker.wait();
	unsafe { body.free() }
	loop_listener := data_http_listener()
	loop_worker := spawn data_http_serve(loop_listener, []string{len: 6, init: 'HTTP/1.1 302 Found\r\nLocation: /loop\r\n\r\n'}, []string{len: 6, init: '/loop'}, false, false)
	if _ := data_http_fetch('http://127.0.0.1:${loop_listener.port}/loop', '', 2 * time.second) { assert false; }
	assert loop_worker.wait();
	slow := data_http_listener()
	slow_worker := spawn data_http_serve(slow, ['HTTP/1.0 200 OK\r\n\r\nlate'], ['/'], false, true)
	if _ := data_http_fetch('http://127.0.0.1:${slow.port}/', '', 25 * time.millisecond) { assert false; }
	assert slow_worker.wait();
	for invalid in ['http://', 'http://user@host/', 'http://host:0/', 'http://host:65536/', 'http://host:%31/', 'http://host/a b', 'http://host/%x0', 'http://host/\r\nX:bad', 'ftp://host/', 'http://host/\\x'] {
		if _ := data_http_url(invalid) { assert false, invalid; }
	}
	println('IOS-DATA-HTTP-REDIRECT: absolute, relative, query, six-request bound, deadline and URL validation')
}

fn test_data_http_tls() {
	cert := os.getenv('VINIX_IOS_HTTP_CERT')
	assert cert.len > 0;
	for mode in ['trusted', 'hostname', 'untrusted', 'downgrade', 'close'] {
		listener := data_http_listener()
		reply := if mode == 'downgrade' { 'HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/\r\n\r\n' } else if mode == 'close' { 'HTTP/1.0 200 OK\r\n\r\nsecure' } else { 'HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nsecure' }
		worker := spawn data_http_serve(listener, [reply], ['/'], true, false)
		host := if mode == 'hostname' { '127.0.0.1' } else { 'localhost' }
		trust := if mode == 'untrusted' { '/etc/ssl/cert.pem' } else { cert }
		if body := data_http_fetch('https://${host}:${listener.port}/', trust, 2 * time.second) {
			assert mode in ['trusted', 'close'] && body.bytestr() == 'secure', mode;
			unsafe { body.free() }
		} else { assert mode !in ['trusted', 'close'], mode; }
		served := worker.wait()
		assert served == (mode !in ['hostname', 'untrusted']), mode;
	}
	println('IOS-DATA-HTTP-TLS: trusted certificate, hostname and CA verification, close-notify and downgrade rejection')
}

fn data_http_factory(api DataHTTPApi) {
	for name in [c'NSData', c'NSMutableData']! {
		listener := data_http_listener()
		worker := spawn data_http_serve(listener, ['HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\na\x00\xffz'], ['/'], false, false)
		pool := api.pool()
		data := api.msg(api.cls(name), c'dataWithContentsOfURL:', api.url('http://127.0.0.1:${listener.port}/'))
		assert data != 0 && api.msg(data, c'length', 0) == 4 && worker.wait();
		assert C.memcmp(unsafe { voidptr(api.msg(data, c'bytes', 0)) }, c'a\x00\xffz', 4) == 0;
		if name == c'NSMutableData' { unsafe { *&u8(voidptr(api.msg(data, c'mutableBytes', 0))) = 42 } }
		api.msg(data, c'retain', 0); api.drain(pool)
		assert api.msg(data, c'length', 0) == 4;
		api.msg(data, c'release', 0)
	}
}

fn test_data_http_factory() {
	$if macos {
		api := DataHTTPApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		method := C.class_getClassMethod(unsafe { voidptr(api.cls(c'NSData')) }, C.sel_registerName(c'dataWithContentsOfURL:'))
		assert ctext(u64(C.method_getTypeEncoding(method))) == '@24@0:8@16';
		data_http_factory(api)
	}
	for _ in 0 .. 2 {
		objc_start()
		api := DataHTTPApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		data_http_factory(api)
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn data_http_factory(api) }
		workers.wait()
		assert ios_runtime.live == 0;
		objc_stop(); assert ios_runtime.live == 0;
	}
	println('IOS-DATA-HTTP-FACTORY: native ABI and binary oracle, mutable results, retained data, concurrent loads and two zero-live-object shutdowns')
}

fn http_transport_serve(listener DataHTTPListener, method string, expected_body string, reply string, tls bool) bool {
	defer { C.close(listener.fd) }
	deadline := time.sys_mono_now() + 5 * time.second
	if !data_http_wait(listener.fd, false, deadline) { return false }
	fd := C.accept(listener.fd, unsafe { nil }, unsafe { nil })
	if fd < 0 { return false }
	data_http_no_sigpipe(fd)
	if C.fcntl(fd, C.F_SETFL, usize(C.O_NONBLOCK)) != 0 { return false }
	mut key := C.mbedtls_pk_context{}
	C.mbedtls_pk_init(&key)
	defer { C.mbedtls_pk_free(&key) }
	mut stream := &DataHTTPStream{fd: fd, deadline: deadline}
	defer { stream.close(); unsafe { free(stream) } }
	if tls && !data_http_server_tls(mut stream, os.getenv('VINIX_IOS_HTTP_CERT'), os.getenv('VINIX_IOS_HTTP_KEY'), mut key) { return false }
	mut storage := []u8{cap: data_http_headers}; storage.flags |= .noslices
	defer { unsafe { storage.free() } }
	line := stream.line(mut storage) or { return false }
	if line != '${method} /submit?q=%00 HTTP/1.1' { return false }
	mut host := 0; mut lengths := 0; mut custom := 0; mut content_type := 0
	for {
		header := stream.line(mut storage) or { return false }
		if header.len == 0 { break }
		if header.starts_with('Host: ') { host++; if header != 'Host: localhost:${listener.port}' { return false } }
		if header.starts_with('Content-Length: ') { lengths++; if header != 'Content-Length: ${expected_body.len}' { return false } }
		if header == 'X-Test: exact value\tand tab' { custom++ }
		if header == 'Content-Type: application/octet-stream' { content_type++ }
	}
	if host != 1 || lengths != 1 || custom != 1 || content_type != 1 { return false }
	for byte in expected_body { if stream.read() or { return false } != byte { return false } }
	if !stream.send(reply) { return false }
	if tls { C.mbedtls_ssl_close_notify(&stream.ssl) }
	return true
}

fn http_transport_case(method string, payload string, reply string, status int, expected string, tls bool) {
	listener := data_http_listener()
	worker := spawn http_transport_serve(listener, method, payload, reply, tls)
	length := payload.len.str()
	defer { unsafe { length.free() } }
	authority := 'localhost:${listener.port}'
	defer { unsafe { authority.free() } }
	fields := [HTTPTransportField{'X-Test', 'exact value\tand tab'},
		HTTPTransportField{'Content-Type', 'application/octet-stream'}, HTTPTransportField{'cOnTeNt-LeNgTh', length},
		HTTPTransportField{'hOsT', authority}, HTTPTransportField{'CONNECTION', 'close'}, HTTPTransportField{'accept-ENCODING', 'identity'}]
	defer { unsafe { fields.free() } }
	bytes := payload.bytes()
	defer { unsafe { bytes.free() } }
	input := HTTPTransportRequest{method: method, fields: fields, body: bytes}
	address := '${if tls { 'https' } else { 'http' }}://localhost:${listener.port}/submit?q=%00#fragment'
	defer { unsafe { address.free() } }
	result := http_transport_exchange(address, input, os.getenv('VINIX_IOS_HTTP_CERT'), 2 * time.second) or { panic('request/response exchange failed') }
	defer { result.dispose() }
	assert worker.wait() && result.status == status && result.body.len == expected.len;
	if expected.len > 0 { assert C.memcmp(result.body.data, expected.str, usize(expected.len)) == 0; }
	assert result.fields.len >= 1;
	// Returned strings and binary data must survive unrelated parser allocations.
	mut churn := []u8{len: data_http_headers, init: 0xaa}
	assert result.fields[0].name == 'X-Result' && result.fields[0].value == 'saved';
	unsafe { churn.free() }
	mut cookies := 0
	for field in result.fields { if field.name == 'Set-Cookie' { cookies++; assert field.value in ['a=1', 'b=2']; } }
	assert cookies == 2;
}

fn test_http_transport_requests_and_status() {
	final_headers := 'X-Result: saved\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\n'
	large := 'a\x00\xffz'.repeat(16385)
	defer { unsafe { large.free() } }
	for tls in [false, true] {
		http_transport_case('POST', 'a\x00\xffz', 'HTTP/1.1 201 Created\r\n${final_headers}Content-Length: 4\r\n\r\nx\x00\xfez', 201, 'x\x00\xfez', tls)
		http_transport_case('POST', large, 'HTTP/1.1 200 OK\r\n${final_headers}Content-Length: 2\r\n\r\nok', 200, 'ok', tls)
		http_transport_case('PUT', 'upload', 'HTTP/1.1 404 Missing\r\n${final_headers}Content-Length: 7\r\n\r\nmissing', 404, 'missing', tls)
		http_transport_case('PATCH', 'update', 'HTTP/1.1 103 Early Hints\r\nX-Interim: ignored\r\n\r\nHTTP/1.1 500 Failure\r\n${final_headers}Transfer-Encoding: chunked\r\n\r\n3\r\nbad\r\n0\r\nX-Trailer: final\r\n\r\n', 500, 'bad', tls)
		http_transport_case('HEAD', '', 'HTTP/1.1 200 OK\r\n${final_headers}Content-Length: 999\r\n\r\n', 200, '', tls)
		http_transport_case('GET', '', 'HTTP/1.1 304 Not Modified\r\n${final_headers}Content-Length: 999\r\n\r\n', 304, '', tls)
		http_transport_case('DELETE', '', 'HTTP/1.1 302 Found\r\n${final_headers}Location: http://127.0.0.1:1/private\r\nContent-Length: 0\r\n\r\n', 302, '', tls)
	}
	println('IOS-HTTP-TRANSPORT: HTTP/TLS methods, binary bodies, HEAD/304, 404/500, informational/chunked responses, duplicate fields, owned results and redirects returned to caller')
}

fn test_http_transport_validation() {
	assert data_http_equal('Content-Length', 'content-LENGTH') && data_http_equal('hOsT', 'HOST');
	assert !data_http_equal('Host', 'hosts') && !data_http_equal('X-Test', 'X-Text');
	url := data_http_url('http://localhost:1234/') or { panic('URL fixture') }
	for fields in [
		[HTTPTransportField{'X-Test', 'bad\r\nInjected: value'}],
		[HTTPTransportField{'Bad Field', 'value'}],
		[HTTPTransportField{'X-Test', 'a\x00b'}],
		[HTTPTransportField{'X-Test', '\x7f'}],
		[HTTPTransportField{'X-Test', 'one'}, HTTPTransportField{'x-test', 'two'}],
		[HTTPTransportField{'Transfer-Encoding', 'chunked'}],
		[HTTPTransportField{'Host', 'other-origin'}],
		[HTTPTransportField{'Content-Length', '3'}],
		[HTTPTransportField{'Content-Length', '-1'}],
		[HTTPTransportField{'Expect', '100-continue'}],
		[HTTPTransportField{'Accept-Encoding', 'gzip'}],
		[HTTPTransportField{'Connection', 'keep-alive'}],
		[HTTPTransportField{'Upgrade', 'websocket'}],
		[HTTPTransportField{'Trailer', 'X-Test'}],
		[HTTPTransportField{'X-Large', 'x'.repeat(data_http_headers)}],
	] {
		if wire := http_transport_wire(url, HTTPTransportRequest{fields: fields}) { unsafe { wire.free() }; assert false; }
	}
	for method in ['CONNECT', 'TRACE', 'GET\r\nX-Test:', '', 'get'] {
		if wire := http_transport_wire(url, HTTPTransportRequest{method: method}) { unsafe { wire.free() }; assert false; }
	}
	for timeout in [i64(0), -1, 25 * time.hour] {
		if _ := http_transport_exchange('http://localhost:1/', HTTPTransportRequest{}, '', timeout) { assert false; }
	}
	println('IOS-HTTP-TRANSPORT-VALIDATION: conflicting framing/origin, control bytes, duplicate request fields, unsupported coding/methods, header bound and timeout range rejected')
}

type HTTPTransportNative4 = fn (u64, u64, u64, u64) u64
type HTTPTransportNativeLoad = fn (u64, u64, u64, &u64, &u64) u64

fn test_http_transport_native_status_oracle() {
	$if macos {
		api := DataHTTPApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		pool := api.pool()
		defer { api.drain(pool) }
		listener := data_http_listener()
		worker := spawn http_transport_serve(listener, 'POST', 'a\x00\xffz', 'HTTP/1.1 404 Missing\r\nX-Result: saved\r\nContent-Length: 4\r\n\r\nx\x00\xfez', false)
		url := api.url('http://localhost:${listener.port}/submit?q=%00')
		request := api.msg(api.cls(c'NSMutableURLRequest'), c'requestWithURL:', url)
		api.msg(request, c'setHTTPMethod:', api.msg(api.cls(c'NSString'), c'stringWithUTF8String:', u64(c'POST')))
		data := unsafe { HTTPTransportNative4(voidptr(api.send))(api.cls(c'NSData'), u64(C.sel_registerName(c'dataWithBytes:length:')), u64(c'a\x00\xffz'), 4) }
		api.msg(request, c'setHTTPBody:', data)
		for field in [HTTPTransportField{'X-Test', 'exact value\tand tab'}, HTTPTransportField{'Content-Type', 'application/octet-stream'}] {
			name := api.msg(api.cls(c'NSString'), c'stringWithUTF8String:', u64(field.name.str))
			value := api.msg(api.cls(c'NSString'), c'stringWithUTF8String:', u64(field.value.str))
			unsafe { HTTPTransportNative4(voidptr(api.send))(request, u64(C.sel_registerName(c'setValue:forHTTPHeaderField:')), value, name) }
		}
		mut response := u64(0); mut error_object := u64(0)
		body := unsafe { HTTPTransportNativeLoad(voidptr(api.send))(api.cls(c'NSURLConnection'), u64(C.sel_registerName(c'sendSynchronousRequest:returningResponse:error:')), request, &response, &error_object) }
		assert worker.wait() && response != 0 && body != 0 && error_object == 0;
		assert api.msg(response, c'statusCode', 0) == 404 && api.msg(body, c'length', 0) == 4;
		assert C.memcmp(unsafe { voidptr(api.msg(body, c'bytes', 0)) }, c'x\x00\xfez', 4) == 0;
		println('IOS-HTTP-TRANSPORT-NATIVE: Foundation sends binary POST with custom headers and preserves the 404 response/body without a transport error')
	}
}

fn test_http_transport_header_count_bound() {
	listener := data_http_listener()
	reply := 'HTTP/1.1 200 OK\r\n' + 'X-Test: value\r\n'.repeat(129) + 'Content-Length: 0\r\n\r\n'
	worker := spawn data_http_serve(listener, [reply], ['/'], false, false)
	url := 'http://127.0.0.1:${listener.port}/'
	result := http_transport_exchange(url, HTTPTransportRequest{}, '', 2 * time.second)
	assert worker.wait();
	if value := result { value.dispose(); assert false; }
	unsafe { url.free(); reply.free() }
	println('IOS-HTTP-TRANSPORT-BOUNDS: excessive response fields reject the exchange and retire previously copied fields')
}
