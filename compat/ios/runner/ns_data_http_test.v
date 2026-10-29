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
	assert C.bind(fd, unsafe { voidptr(&address[0]) }, 16) == 0 && C.listen(fd, 8) == 0;
	mut size := u32(16)
	assert C.getsockname(fd, unsafe { voidptr(&address[0]) }, &size) == 0;
	assert C.fcntl(fd, C.F_SETFL, usize(C.O_NONBLOCK)) == 0;
	return DataHTTPListener{fd, int(address[2]) * 256 + int(address[3])}
}

fn data_http_server_tls(mut stream DataHTTPStream, cert string, key string, mut private_key C.mbedtls_pk_context) bool {
	stream.tls = true
	C.mbedtls_ssl_init(&stream.ssl); C.mbedtls_ssl_config_init(&stream.config)
	C.mbedtls_x509_crt_init(&stream.ca); C.mbedtls_ctr_drbg_init(&stream.rng); C.mbedtls_entropy_init(&stream.entropy)
	if C.mbedtls_ctr_drbg_seed(&stream.rng, data_http_os_entropy, unsafe { nil }, c'http-test', 9) != 0
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

// Characterize Foundation's per-selector task/session delegate fallback before
// connecting the transport to the task lifecycle. All traffic stays on loopback.
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.objc_getProtocol(&char) voidptr
fn C.class_addProtocol(voidptr, voidptr) bool
fn C.__atomic_load_n(&u64, int) u64
fn C.__atomic_store_n(&u64, u64, int)
fn C.__atomic_fetch_add(&u64, u64, int) u64
type TaskHTTPNative5 = fn (u64, u64, u64, u64, u64) u64
type TaskHTTPDisposition = fn (u64, u64)
struct TaskHTTPOracle {
	send u64
	session_delegate u64
	task_delegate u64
	queue u64
mut:
	events [8]u64
	count u64
	finished u64
	bad_queue u64
	state u64
	error_code i64
	body [8]u8
	body_size u64
	deferred bool
	response_seen u64
	pending_block u64
	block_signature [64]u8
}
__global task_http_oracle = unsafe { &TaskHTTPOracle(nil) }
fn task_http_oracle_event(delegate u64, kind u64) {
	mut p := task_http_oracle
	if p.count >= 8 { C.__atomic_store_n(unsafe { &p.bad_queue }, 1, 5); return }
	p.events[p.count] = kind + if delegate == p.task_delegate { u64(10) } else { u64(0) }
	p.count++
	api := DataHTTPApi{native: true, send: p.send}
	if api.msg(api.cls(c'NSOperationQueue'), c'currentQueue', 0) != p.queue { p.bad_queue = 1 }
}
fn task_http_oracle_response(delegate u64, _ &char, _session u64, _task u64, _response u64, complete u64) {
	task_http_oracle_event(delegate, 1)
	mut p := task_http_oracle
	if p.deferred {
		api := DataHTTPApi{native: true, send: p.send}
		p.pending_block = api.msg(complete, c'copy', 0)
		flags := read32(complete + 8)
		if flags & (u32(1) << 30) != 0 {
			descriptor := read64(complete + 24)
			signature := ctext(read64(descriptor + if flags & (u32(1) << 25) != 0 { u64(32) } else { u64(16) }))
			if signature.len < p.block_signature.len { unsafe { C.memcpy(&p.block_signature[0], signature.str, usize(signature.len)) } }
		}
		C.__atomic_store_n(unsafe { &p.response_seen }, 1, 5)
		return
	}
	unsafe { TaskHTTPDisposition(voidptr(read64(complete + 16)))(complete, 1) }
}
fn task_http_oracle_data(delegate u64, _ &char, _session u64, _task u64, data u64) {
	task_http_oracle_event(delegate, 2)
	mut p := task_http_oracle
	api := DataHTTPApi{native: true, send: p.send}
	length := api.msg(data, c'length', 0)
	if length > 8 - p.body_size { p.bad_queue = 1; return }
	unsafe { C.memcpy(&p.body[int(p.body_size)], voidptr(api.msg(data, c'bytes', 0)), usize(length)) }
	p.body_size += length
}
fn task_http_oracle_complete(delegate u64, _ &char, _session u64, task u64, error_object u64) {
	task_http_oracle_event(delegate, 3)
	mut p := task_http_oracle
	api := DataHTTPApi{native: true, send: p.send}
	p.state = api.msg(task, c'state', 0)
	p.error_code = if error_object == 0 { i64(0) } else { i64(api.msg(error_object, c'code', 0)) }
	C.__atomic_store_n(unsafe { &p.finished }, 1, 5)
}
fn test_http_session_native_delegate_routing() {
	$if macos {
		api := DataHTTPApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		all := C.objc_allocateClassPair(unsafe { voidptr(api.cls(c'NSObject')) }, c'VinixHTTPNativeDelegateOracle', 0)
		partial := C.objc_allocateClassPair(unsafe { voidptr(api.cls(c'NSObject')) }, c'VinixHTTPNativeCompleteOracle', 0)
		for cls in [all, partial] {
			assert cls != unsafe { nil };
			assert C.class_addProtocol(cls, C.objc_getProtocol(c'NSURLSessionTaskDelegate'));
			assert C.class_addMethod(cls, C.sel_registerName(c'URLSession:task:didCompleteWithError:'), unsafe { voidptr(task_http_oracle_complete) }, c'v40@0:8@16@24@32');
		}
		assert C.class_addProtocol(all, C.objc_getProtocol(c'NSURLSessionDataDelegate'));
		assert C.class_addMethod(all, C.sel_registerName(c'URLSession:dataTask:didReceiveResponse:completionHandler:'), unsafe { voidptr(task_http_oracle_response) }, c'v48@0:8@16@24@32@?40');
		assert C.class_addMethod(all, C.sel_registerName(c'URLSession:dataTask:didReceiveData:'), unsafe { voidptr(task_http_oracle_data) }, c'v40@0:8@16@24@32');
		C.objc_registerClassPair(all); C.objc_registerClassPair(partial)
		for mode in ['session', 'task', 'partial', 'cancel-before-resume', 'deferred-allow', 'deferred-deny', 'cancel-pending-decision'] {
			pool := api.pool()
			listener := data_http_listener()
			mut workers := []thread bool{}
			if mode != 'cancel-before-resume' { workers << spawn data_http_serve(listener, ['HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nping'], ['/'], false, false) }
			queue := api.msg(api.cls(c'NSOperationQueue'), c'new', 0)
			api.msg(queue, c'setMaxConcurrentOperationCount:', 1)
			session_delegate := api.msg(u64(all), c'new', 0)
			task_delegate := if mode == 'session' { u64(0) } else { api.msg(if mode == 'partial' { u64(partial) } else { u64(all) }, c'new', 0) }
			mut probe := TaskHTTPOracle{send: api.send, session_delegate: session_delegate, task_delegate: task_delegate, queue: queue,
				deferred: mode in ['deferred-allow', 'deferred-deny', 'cancel-pending-decision']}
			task_http_oracle = unsafe { &probe }
			config := api.msg(api.cls(c'NSURLSessionConfiguration'), c'defaultSessionConfiguration', 0)
			session := unsafe { TaskHTTPNative5(voidptr(api.send))(api.cls(c'NSURLSession'), u64(C.sel_registerName(c'sessionWithConfiguration:delegate:delegateQueue:')), config, session_delegate, queue) }
			api.msg(session, c'retain', 0)
			request := api.msg(api.cls(c'NSURLRequest'), c'requestWithURL:', api.url('http://127.0.0.1:${listener.port}/'))
			task := api.msg(session, c'dataTaskWithRequest:', request)
			api.msg(task, c'setDelegate:', task_delegate)
			api.msg(task, if mode == 'cancel-before-resume' { c'cancel' } else { c'resume' }, 0)
			deadline := time.sys_mono_now() + 5 * time.second
			if probe.deferred {
				for C.__atomic_load_n(unsafe { &probe.response_seen }, 5) == 0 {
					if time.sys_mono_now() >= deadline { eprintln('IOS-SESSION-NATIVE-ROUTING: response timeout ' + mode); C._exit(124) }
					time.sleep(time.millisecond)
				}
				time.sleep(20 * time.millisecond)
				// End the process on an unsafe native contract failure. Returning
				// through V's test assertion recovery could leave a native task
				// holding callback state on this expired stack frame.
				if probe.pending_block == 0 || ctext(u64(unsafe { &probe.block_signature[0] })) != 'v16@?0q8' {
					eprintln('IOS-SESSION-NATIVE-ROUTING: invalid response completion block'); C._exit(125)
				}
				if probe.count != 1 || probe.body_size != 0 || C.__atomic_load_n(unsafe { &probe.finished }, 5) != 0 { probe.bad_queue = 1 }
				if mode == 'cancel-pending-decision' {
					api.msg(task, c'cancel', 0)
					time.sleep(40 * time.millisecond)
					if C.__atomic_load_n(unsafe { &probe.finished }, 5) != 0 || probe.body_size != 0 || api.msg(task, c'state', 0) != 2 { probe.bad_queue = 1 }
					// Native cancellation remains pending until this response
					// handler is called. A late allow must still end as -999.
					unsafe { TaskHTTPDisposition(voidptr(read64(probe.pending_block + 16)))(probe.pending_block, 1) }
				}
				else { unsafe { TaskHTTPDisposition(voidptr(read64(probe.pending_block + 16)))(probe.pending_block, if mode == 'deferred-allow' { u64(1) } else { u64(0) }) } }
			}
			for C.__atomic_load_n(unsafe { &probe.finished }, 5) == 0 {
				if time.sys_mono_now() >= deadline { eprintln('IOS-SESSION-NATIVE-ROUTING: completion timeout ' + mode); C._exit(124) }
				time.sleep(time.millisecond)
			}
			api.msg(queue, c'waitUntilAllOperationsAreFinished', 0)
			if mode == 'cancel-before-resume' { C.close(listener.fd) } else { assert workers[0].wait(); }
			unsafe { workers.free() }
			assert probe.bad_queue == 0 && probe.state == 3;
			cancelled := mode in ['cancel-before-resume', 'deferred-deny', 'cancel-pending-decision']
			assert probe.error_code == if cancelled { i64(-999) } else { i64(0) };
			expected := match mode {
				'session' { [u64(1), 2, 3, 0, 0, 0, 0, 0]! }
				'task' { [u64(11), 12, 13, 0, 0, 0, 0, 0]! }
				'partial' { [u64(1), 2, 13, 0, 0, 0, 0, 0]! }
				'deferred-allow' { [u64(11), 12, 13, 0, 0, 0, 0, 0]! }
				'deferred-deny', 'cancel-pending-decision' { [u64(11), 13, 0, 0, 0, 0, 0, 0]! }
				else { [u64(13), 0, 0, 0, 0, 0, 0, 0]! }
			}
			assert probe.events == expected && probe.count == if mode == 'cancel-before-resume' { u64(1) } else if cancelled { u64(2) } else { u64(3) };
			assert probe.body_size == if cancelled { u64(0) } else { u64(4) };
			if probe.body_size != 0 { assert C.memcmp(&probe.body[0], c'ping', 4) == 0; }
			println('IOS-SESSION-NATIVE-ROUTING: ${mode} events=${probe.events} count=${probe.count} body=${probe.body_size} code=${probe.error_code} state=${probe.state}')
			api.msg(session, c'invalidateAndCancel', 0)
			if probe.pending_block != 0 { api.msg(probe.pending_block, c'release', 0) }
			api.msg(session, c'release', 0); api.msg(task_delegate, c'release', 0); api.msg(session_delegate, c'release', 0); api.msg(queue, c'release', 0)
			api.drain(pool)
			task_http_oracle = unsafe { nil }
		}
	}
}

fn test_http_transport_os_entropy() {
	mut bytes := [515]u8{}
	bytes[0] = 0xa5; bytes[514] = 0x5a
	assert data_http_os_entropy(unsafe { nil }, unsafe { nil }, 1) == C.MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
	assert data_http_os_entropy(unsafe { nil }, unsafe { nil }, 0) == 0;
	assert data_http_os_entropy(unsafe { nil }, unsafe { &bytes[1] }, 513) == 0;
	assert bytes[0] == 0xa5 && bytes[514] == 0x5a;
	println('IOS-HTTP-TRANSPORT-ENTROPY: OS CSPRNG callback, 513-byte chunked fill, canaries and rejected invalid buffer')
}

struct HTTPControlProbe {
mut:
	ready u64
	cancel u64
}
fn http_control_cancel(probe &HTTPControlProbe) bool {
	deadline := time.sys_mono_now() + 3 * time.second
	for C.ios_load_pointer(unsafe { &probe.ready }) == 0 {
		if time.sys_mono_now() > deadline { C.ios_store_pointer(unsafe { &probe.cancel }, 1); return false }
		time.sleep(time.millisecond)
	}
	time.sleep(40 * time.millisecond)
	C.ios_store_pointer(unsafe { &probe.cancel }, 1)
	return true
}
fn http_control_server(listener DataHTTPListener, tls bool, mode string, probe &HTTPControlProbe) bool {
	defer { C.close(listener.fd); C.ios_store_pointer(unsafe { &probe.ready }, 1) }
	deadline := time.sys_mono_now() + 5 * time.second
	if !data_http_wait(listener.fd, false, deadline) { return false }
	fd := C.accept(listener.fd, unsafe { nil }, unsafe { nil })
	if fd < 0 { return false }
	data_http_no_sigpipe(fd)
	mut receive_buffer := i32(8192)
	if C.fcntl(fd, C.F_SETFL, usize(C.O_NONBLOCK)) != 0
		|| C.setsockopt(fd, C.SOL_SOCKET, C.SO_RCVBUF, &receive_buffer, u32(sizeof(receive_buffer))) != 0 { C.close(fd); return false }
	mut key := C.mbedtls_pk_context{}
	C.mbedtls_pk_init(&key)
	defer { C.mbedtls_pk_free(&key) }
	mut stream := &DataHTTPStream{fd: fd, deadline: deadline}
	defer { stream.close(); unsafe { free(stream) } }
	if mode == 'handshake' {
		C.ios_store_pointer(unsafe { &probe.ready }, 1)
		time.sleep(1500 * time.millisecond)
		return true
	}
	if tls && !data_http_server_tls(mut stream, os.getenv('VINIX_IOS_HTTP_CERT'), os.getenv('VINIX_IOS_HTTP_KEY'), mut key) { return false }
	mut headers := []u8{cap: data_http_headers}; headers.flags |= .noslices
	defer { unsafe { headers.free() } }
	for { line := stream.line(mut headers) or { return false }; if line.len == 0 { break } }
	prefix := match mode {
		'length' { 'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nab' }
		'eof' { 'HTTP/1.0 200 OK\r\n\r\nab' }
		'chunk' { 'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nab' }
		else { '' }
	}
	if prefix.len != 0 && !stream.send(prefix) { return false }
	C.ios_store_pointer(unsafe { &probe.ready }, 1)
	time.sleep(1500 * time.millisecond)
	// The client must have cancelled before this tail arrives. A closed peer
	// is expected; sending it still exercises SIGPIPE suppression for TLS too.
	stream.send(if mode == 'headers' { 'HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nlate' }
		else if mode == 'chunk' { 'cd\r\n0\r\n\r\n' } else { 'cd' })
	if tls { C.mbedtls_ssl_close_notify(&stream.ssl) }
	return true
}
fn test_http_transport_cancellation() {
	mut cancelled := u64(1)
	start := time.sys_mono_now()
	if result := http_transport_exchange_control('http://127.0.0.1:1/', HTTPTransportRequest{}, '', 4 * time.second, unsafe { &cancelled }) { result.dispose(); assert false; }
	assert time.sys_mono_now() - start < time.second;
	for tls in [false, true] {
		for mode in ['headers', 'length', 'eof', 'chunk', 'upload', 'handshake'] {
			if mode == 'handshake' && !tls { continue }
			listener := data_http_listener()
			mut probe := HTTPControlProbe{}
			server := spawn http_control_server(listener, tls, mode, unsafe { &probe })
			canceller := spawn http_control_cancel(unsafe { &probe })
			body := []u8{len: if mode == 'upload' { data_http_limit } else { 0 }, init: 0x61}
			request := HTTPTransportRequest{method: if mode == 'upload' { 'POST' } else { 'GET' }, body: body}
			address := '${if tls { 'https' } else { 'http' }}://localhost:${listener.port}/'
			began := time.sys_mono_now()
			result := http_transport_exchange_control(address, request, os.getenv('VINIX_IOS_HTTP_CERT'), 4 * time.second, unsafe { &probe.cancel })
			elapsed := time.sys_mono_now() - began
			assert canceller.wait() && server.wait();
			unsafe { body.free(); address.free() }
			if value := result { value.dispose(); assert false, mode; }
			assert elapsed < time.second, 'cancellation waited for peer/timeout: ${mode} tls=${tls}';
		}
	}
	println('IOS-HTTP-TRANSPORT-CANCEL: pre-cancel, stalled headers, fixed/EOF/chunked partial bodies, blocked 16 MiB uploads and TLS handshake; cancellation remains failure and wakes before peer completion')
}

type HTTPDecisionInvoke = fn (u64, i64)
fn http_decision_invoke(block u64, value i64) {
	unsafe { HTTPDecisionInvoke(voidptr(read64(block + 16)))(block, value) }
}
fn http_decision_concurrent(block u64, value i64) {
	for _ in 0 .. 64 {
		copy := block_copy(block)
		http_decision_invoke(copy, value)
		block_release(copy)
	}
}
fn http_decision_waiter(gate &URLSessionResponseDecision, cancel &u64, entered &u64) bool {
	C.__atomic_store_n(entered, 1, 5)
	result := url_session_response_decision_wait(gate, cancel, time.sys_mono_now() + 4 * time.second)
	url_session_response_decision_release(gate)
	return result
}
fn test_http_response_decision_blocks() {
	for _ in 0 .. 2 {
		objc_start()
		for allow in [false, true]! {
			gate := url_session_response_decision_new()
			block := url_session_response_decision_block(gate)
			copy := block_copy(block)
			assert copy == block && gate.refs == 2;
			assert is_block(block) && read64(block + 24) == u64(unsafe { &gate.descriptor[0] });
			assert read64(read64(block + 24) + 8) == 40 && ctext(read64(read64(block + 24) + 32)) == 'v16@?0q8';
			http_decision_invoke(block, if allow { i64(1) } else { i64(0) })
			http_decision_invoke(copy, if allow { i64(0) } else { i64(1) })
			assert url_session_response_decision_wait(gate, unsafe { nil }, time.sys_mono_now() + time.second) == allow;
			block_release(block); assert gate.refs == 2;
			block_release(copy); assert gate.refs == 1;
			url_session_response_decision_release(gate)
		}
		for action in ['close', 'cancel', 'timeout', 'pre-cancel'] {
			gate := url_session_response_decision_new()
			block := url_session_response_decision_block(gate)
			mut cancel := u64(0); mut entered := u64(0)
			if action in ['close', 'cancel'] {
				url_session_response_decision_retain(gate) // The worker owns its wait.
				worker := spawn http_decision_waiter(gate, unsafe { &cancel }, unsafe { &entered })
				deadline := time.sys_mono_now() + time.second
				for C.__atomic_load_n(unsafe { &entered }, 5) == 0 { assert time.sys_mono_now() < deadline; time.sleep(time.millisecond) }
				time.sleep(10 * time.millisecond)
				began := time.sys_mono_now()
				if action == 'close' { url_session_response_decision_close(gate) }
				else { C.__atomic_store_n(unsafe { &cancel }, 1, 5) }
				assert !worker.wait() && time.sys_mono_now() - began < time.second;
			} else {
				if action == 'pre-cancel' { C.__atomic_store_n(unsafe { &cancel }, 1, 5); http_decision_invoke(block, 1) }
				assert !url_session_response_decision_wait(gate, unsafe { &cancel }, time.sys_mono_now() + 20 * time.millisecond);
			}
			assert gate.refs == 2 && gate.closed;
			url_session_response_decision_release(gate)
			// The descriptor and gate outlive the worker/transfer owner's reference.
			http_decision_invoke(block, 1)
			assert gate.closed && gate.settled;
			copy := block_copy(block)
			block_release(block); http_decision_invoke(copy, 0); block_release(copy)
		}
		gate := url_session_response_decision_new()
		block := url_session_response_decision_block(gate)
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn http_decision_concurrent(block, i64(i & 1)) }
		workers.wait(); unsafe { workers.free() }
		assert gate.settled && gate.refs == 2;
		chosen := gate.allow
		assert url_session_response_decision_wait(gate, unsafe { nil }, time.sys_mono_now() + time.second) == chosen;
		url_session_response_decision_release(gate); block_release(block)
		assert ios_runtime.block_refs.len == 0 && ios_runtime.live == 0;
		objc_stop()
	}
	println('IOS-HTTP-RESPONSE-DECISION: signed 64-bit block ABI, copy identity/descriptor lifetime, first choice, 512 competing copied-block calls, close/cancel/timeout and late invocation after owner release PASS')
}

struct HTTPDecisionProbe {
	gate &URLSessionResponseDecision
	mode string
mut:
	cancel u64
	entered u64
	calls u64
	bad bool
}
fn http_decision_policy(context voidptr, response HTTPTransportResponseHead, deadline i64) bool {
	mut p := unsafe { &HTTPDecisionProbe(context) }
	p.calls++
	empty := p.mode in ['empty', 'expired-allow']
	wanted_status := if empty { 204 } else { 500 }
	final_value := response.field('X-Final') or { '' }
	if response.status != wanted_status
		|| final_value != 'yes' || response.field('X-Interim') != none { p.bad = true }
	mut cookies := 0
	for field in response.fields { if data_http_equal(field.name, 'Set-Cookie') { cookies++; if field.value !in ['a=1', 'b=2'] { p.bad = true } } }
	if cookies != 2 { p.bad = true }
	C.__atomic_store_n(unsafe { &p.entered }, 1, 5)
	if p.mode == 'cached-cancel' { C.__atomic_store_n(unsafe { &p.cancel }, 1, 5); return true }
	if p.mode == 'expired-allow' {
		for time.sys_mono_now() <= deadline { time.sleep(time.millisecond) }
		return true
	}
	return url_session_response_decision_wait(p.gate, unsafe { &p.cancel }, deadline)
}
fn http_decision_server(listener DataHTTPListener, tls bool, probe &HTTPDecisionProbe) bool {
	defer { C.close(listener.fd) }
	deadline := time.sys_mono_now() + 4 * time.second
	if !data_http_wait(listener.fd, false, deadline) { return false }
	fd := C.accept(listener.fd, unsafe { nil }, unsafe { nil })
	if fd < 0 { return false }
	data_http_no_sigpipe(fd)
	if C.fcntl(fd, C.F_SETFL, usize(C.O_NONBLOCK)) != 0 { C.close(fd); return false }
	mut key := C.mbedtls_pk_context{}
	C.mbedtls_pk_init(&key)
	defer { C.mbedtls_pk_free(&key) }
	mut stream := &DataHTTPStream{fd: fd, deadline: deadline}
	defer { stream.close(); unsafe { free(stream) } }
	if tls && !data_http_server_tls(mut stream, os.getenv('VINIX_IOS_HTTP_CERT'), os.getenv('VINIX_IOS_HTTP_KEY'), mut key) { return false }
	mut storage := []u8{cap: data_http_headers}; storage.flags |= .noslices
	defer { unsafe { storage.free() } }
	line := stream.line(mut storage) or { return false }
	if line != 'GET / HTTP/1.1' { return false }
	for { header := stream.line(mut storage) or { return false }; if header.len == 0 { break } }
	if probe.mode == 'malformed' { return stream.send('HTTP/1.1 200 OK\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\nping') }
	empty := probe.mode in ['empty', 'expired-allow']
	head := 'HTTP/1.1 103 Early Hints\r\nX-Interim: ignored\r\n\r\nHTTP/1.1 ${if empty { '204 No Content' } else { '500 Failure' }}\r\nX-Final: yes\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\nContent-Length: ${if empty { '0' } else { '4' }}\r\n\r\n'
	defer { unsafe { head.free() } }
	if probe.mode == 'cached-cancel' {
		wire := head + 'ping'
		defer { unsafe { wire.free() } }
		return stream.send(wire)
	}
	if !stream.send(head) { return false }
	// Withhold the body until the policy has actually seen the final headers.
	// Reading the full body before invoking the policy would deadlock this case.
	for C.__atomic_load_n(unsafe { &probe.entered }, 5) == 0 {
		if time.sys_mono_now() >= deadline { return false }
		time.sleep(time.millisecond)
	}
	if !empty { stream.send('ping') }
	if tls { C.mbedtls_ssl_close_notify(&stream.ssl) }
	return true
}
fn http_decision_choose(block u64, probe &HTTPDecisionProbe) bool {
	defer { block_release(block) }
	deadline := time.sys_mono_now() + 4 * time.second
	for C.__atomic_load_n(unsafe { &probe.entered }, 5) == 0 {
		if time.sys_mono_now() >= deadline { return false }
		time.sleep(time.millisecond)
	}
	time.sleep(20 * time.millisecond)
	match probe.mode {
		'allow', 'empty' { http_decision_invoke(block, 1) }
		'deny' { http_decision_invoke(block, 0) }
		'cancel' { C.__atomic_store_n(unsafe { &probe.cancel }, 1, 5); http_decision_invoke(block, 1) }
		'close' { url_session_response_decision_close(probe.gate); http_decision_invoke(block, 1) }
		else {}
	}
	return true
}
fn test_http_transport_response_decisions() {
	objc_start()
	for tls in [false, true] {
		for mode in ['allow', 'deny', 'cancel', 'close', 'timeout', 'empty', 'cached-cancel', 'expired-allow', 'malformed'] {
			gate := url_session_response_decision_new()
			block := url_session_response_decision_block(gate)
			mut probe := HTTPDecisionProbe{gate: gate, mode: mode}
			listener := data_http_listener()
			server := spawn http_decision_server(listener, tls, unsafe { &probe })
			mut choosers := []thread bool{}
			if mode !in ['malformed', 'cached-cancel', 'expired-allow'] { choosers << spawn http_decision_choose(block_copy(block), unsafe { &probe }) }
			address := '${if tls { 'https' } else { 'http' }}://localhost:${listener.port}/'
			timeout := if mode in ['timeout', 'expired-allow'] { time.second } else { 3 * time.second }
			result := http_transport_exchange_policy(address, HTTPTransportRequest{}, os.getenv('VINIX_IOS_HTTP_CERT'), timeout,
				unsafe { &probe.cancel }, unsafe { &probe }, http_decision_policy)
			for chooser in choosers { assert chooser.wait(); }
			unsafe { choosers.free(); address.free() }
			assert server.wait() && !probe.bad;
			assert probe.calls == if mode == 'malformed' { u64(0) } else { u64(1) };
			if value := result {
				assert mode in ['allow', 'empty'], mode;
				assert value.status == if mode == 'empty' { 204 } else { 500 };
				assert value.body == if mode == 'empty' { []u8{} } else { 'ping'.bytes() };
				value.dispose()
			} else { assert mode !in ['allow', 'empty'], mode; }
			url_session_response_decision_close(gate)
			url_session_response_decision_release(gate)
			http_decision_invoke(block, 1) // Late completion cannot revive a closed load.
			block_release(block)
		}
	}
	assert ios_runtime.block_refs.len == 0 && ios_runtime.live == 0;
	objc_stop()
	println('IOS-HTTP-TRANSPORT-DECISION: HTTP/TLS headers precede body, deferred allow/deny, close/cancel/deadline, cached body cancellation, empty body, final status/error body, repeated fields and malformed framing PASS')
}

fn test_http_response_decision_rejections() {
	for value in [i64(-1), 2, 3, 4]! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork()
		assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); C.dup2(fds[1], 2); C.close(fds[1])
			objc_start()
			gate := url_session_response_decision_new()
			block := url_session_response_decision_block(gate)
			http_decision_invoke(block, value)
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [8192]u8{}
		mut length := 0
		for {
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0 && length + int(count) < bytes.len;
			length += int(count)
		}
		C.close(fds[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains('response conversion to a download/stream task and invalid dispositions are not implemented'), output;
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	println('IOS-HTTP-RESPONSE-DECISION-REJECT: unsupported download/stream and invalid dispositions fail explicitly PASS')
}

@[heap]
struct SessionWorkerProbe {
mut:
	entered u64
	release_gate u64
	runs u64
	done u64
	completed u64
	cancelled u64
	rejected u64
	stopped u64
	responses u64
	bad u64
	held_weak [69]u64
	temporary_weak [69]u64
}
fn session_worker_require(good bool, reason string) {
	if !good { eprintln('IOS-SESSION-WORKERS: FAIL ' + reason); C._exit(125) }
}
fn session_worker_wait(value &u64, wanted u64) {
	deadline := time.sys_mono_now() + 10 * time.second
	for C.__atomic_load_n(value, 5) != wanted {
		if time.sys_mono_now() >= deadline { eprintln('IOS-SESSION-WORKERS: FAIL work/cleanup timeout'); C._exit(124) }
		time.sleep(time.millisecond)
	}
}
fn session_worker_count(probe &SessionWorkerProbe, outcome URLSessionWorkerOutcome) {
	match outcome {
		.completed { C.__atomic_fetch_add(unsafe { &probe.completed }, 1, 5) }
		.cancelled { C.__atomic_fetch_add(unsafe { &probe.cancelled }, 1, 5) }
		.rejected { C.__atomic_fetch_add(unsafe { &probe.rejected }, 1, 5) }
		.stopped { C.__atomic_fetch_add(unsafe { &probe.stopped }, 1, 5) }
	}
}
struct SessionWorkerUnit {
	probe &SessionWorkerProbe
	index int
	held bool
	object u64
}
fn session_worker_unit(probe &SessionWorkerProbe, index int, held bool) &SessionWorkerUnit {
	mut context := unsafe { &SessionWorkerUnit(C.calloc(1, sizeof(SessionWorkerUnit))) }
	object := objc_new(ios_runtime.names['NSObject'])
	objc_store_weak(unsafe { &probe.held_weak[index] }, object)
	unsafe { *context = SessionWorkerUnit{probe: probe, index: index, held: held, object: object} }
	return context
}
fn session_worker_unit_run(pointer voidptr, cancel &u64) {
	context := unsafe { &SessionWorkerUnit(pointer) }
	p := context.probe
	C.__atomic_fetch_add(unsafe { &p.runs }, 1, 5)
	object := objc_autorelease(objc_new(ios_runtime.names['NSObject']))
	objc_store_weak(unsafe { &p.temporary_weak[context.index] }, object)
	if context.held {
		C.__atomic_fetch_add(unsafe { &p.entered }, 1, 5)
		for C.__atomic_load_n(unsafe { &p.release_gate }, 5) == 0 && !data_http_cancelled(cancel) { time.sleep(time.millisecond) }
	}
}
fn session_worker_query(probe &SessionWorkerProbe) {
	if url_session_workers_cancel(~u64(0)) { C.__atomic_store_n(unsafe { &probe.bad }, 1, 5) }
}
fn session_worker_unit_cleanup(pointer voidptr, outcome URLSessionWorkerOutcome) {
	context := unsafe { &SessionWorkerUnit(pointer) }
	p := context.probe
	if context.index == 0 {
		// A different thread must reenter both locks while cleanup is waiting.
		query := spawn session_worker_query(p)
		query.wait()
	}
	objc_release(context.object)
	session_worker_count(p, outcome)
	C.free(pointer)
	C.__atomic_fetch_add(unsafe { &p.done }, 1, 5)
}
fn test_session_worker_capacity_and_ownership() {
	mut previous := u64(0)
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		mut p := unsafe { &SessionWorkerProbe(C.calloc(1, sizeof(SessionWorkerProbe))) }
		mut identities := [68]u64{}
		for i in 0 .. 4 { identities[i] = url_session_workers_submit(session_worker_unit(p, i, true), session_worker_unit_run, session_worker_unit_cleanup) }
		session_worker_wait(unsafe { &p.entered }, 4)
		session_worker_require(identities[0] > previous && !url_session_workers_cancel(previous), 'old identity aliased a new runtime')
		for i in 4 .. 68 { identities[i] = url_session_workers_submit(session_worker_unit(p, i, false), session_worker_unit_run, session_worker_unit_cleanup) }
		rejected := url_session_workers_submit(session_worker_unit(p, 68, false), session_worker_unit_run, session_worker_unit_cleanup)
		session_worker_require(rejected == 0 && p.rejected == 1 && p.held_weak[68] == 0, 'queue limit did not retire rejected context')
		session_worker_require(url_session_workers_cancel(identities[4]) && url_session_workers_cancel(identities[4]), 'queued cancellation failed')
		C.__atomic_store_n(unsafe { &p.release_gate }, 1, 5)
		session_worker_wait(unsafe { &p.done }, 69)
		previous = identities[0]
		objc_stop()
		assert p.runs == 67 && p.completed == 67 && p.cancelled == 1 && p.rejected == 1 && p.stopped == 0 && p.bad == 0;
		for i in 0 .. 69 {
			assert p.held_weak[i] == 0 && p.temporary_weak[i] == 0;
			objc_destroy_weak(unsafe { &p.held_weak[i] }); objc_destroy_weak(unsafe { &p.temporary_weak[i] })
		}
		assert url_session_workers == unsafe { nil } && !url_session_workers_cancel(previous) && ios_runtime.live == 0;
		system_data_stop(); C.free(p)
	}
	println('IOS-SESSION-WORKERS-OWNERSHIP: four independent workers, 64 queued contexts, rejection cleanup, queued cancellation, unlocked reentrant retirement, autorelease/weak ownership and unique IDs across two runtimes PASS')
}

struct SessionWorkerDecisionCallback { block u64 }
fn session_worker_decision_run(pointer voidptr) {
	context := unsafe { &SessionWorkerDecisionCallback(pointer) }
	http_decision_invoke(context.block, 1)
}
fn session_worker_decision_drop(pointer voidptr) {
	context := unsafe { &SessionWorkerDecisionCallback(pointer) }
	block_release(context.block)
	C.free(pointer)
}
struct SessionWorkerHTTP {
	probe &SessionWorkerProbe
	server_probe &HTTPDecisionProbe
	gate &URLSessionResponseDecision
	queue u64
	object u64
	url string
	ca string
	mode string
mut:
	control &u64 = unsafe { nil } // Borrowed only until run returns.
}
fn session_worker_http_policy(pointer voidptr, response HTTPTransportResponseHead, deadline i64) bool {
	context := unsafe { &SessionWorkerHTTP(pointer) }
	if response.status != 500 { C.__atomic_store_n(unsafe { &context.probe.bad }, 1, 5) }
	mut callback := unsafe { &SessionWorkerDecisionCallback(C.calloc(1, sizeof(SessionWorkerDecisionCallback))) }
	unsafe { *callback = SessionWorkerDecisionCallback{block: url_session_response_decision_block(context.gate)} }
	// This queued context owns only the completion block, whose independent
	// gate can outlive the HTTP context and the executor's cancellation cell.
	ns_operation_queue_submit(context.queue, callback, session_worker_decision_run, session_worker_decision_drop)
	C.__atomic_store_n(unsafe { &context.server_probe.entered }, 1, 5)
	C.__atomic_fetch_add(unsafe { &context.probe.entered }, 1, 5)
	return url_session_response_decision_wait(context.gate, context.control, deadline)
}
fn session_worker_http_run(pointer voidptr, control &u64) {
	mut context := unsafe { &SessionWorkerHTTP(pointer) }
	context.control = unsafe { control }
	C.__atomic_fetch_add(unsafe { &context.probe.runs }, 1, 5)
	if response := http_transport_exchange_policy(context.url, HTTPTransportRequest{}, context.ca, 6 * time.second, control, pointer, session_worker_http_policy) {
		if context.mode != 'allow' || response.status != 500 || response.body.len != 4 || C.memcmp(response.body.data, c'ping', 4) != 0 {
			C.__atomic_store_n(unsafe { &context.probe.bad }, 1, 5)
		}
		C.__atomic_fetch_add(unsafe { &context.probe.responses }, 1, 5)
		response.dispose()
	} else if context.mode == 'allow' { C.__atomic_store_n(unsafe { &context.probe.bad }, 1, 5) }
	context.control = unsafe { nil }
}
fn session_worker_http_cleanup(pointer voidptr, outcome URLSessionWorkerOutcome) {
	context := unsafe { &SessionWorkerHTTP(pointer) }
	p := context.probe
	url_session_response_decision_close(context.gate)
	url_session_response_decision_release(context.gate)
	objc_release(context.queue); objc_release(context.object)
	unsafe { context.url.free(); context.ca.free() }
	session_worker_count(p, outcome)
	C.free(pointer)
	C.__atomic_fetch_add(unsafe { &p.done }, 1, 5)
}
fn test_session_workers_http_callbacks_and_shutdown() {
	cert := os.getenv('VINIX_IOS_HTTP_CERT')
	defer { unsafe { cert.free() } }
	for tls in [false, true] {
		for mode in ['allow', 'cancel', 'stop'] {
			objc_start(); system_data_start()!
			pool := objc_pool_push()
			mut p := unsafe { &SessionWorkerProbe(C.calloc(1, sizeof(SessionWorkerProbe))) }
			queue := objc_new(ios_runtime.names['NSOperationQueue'])
			api := DataHTTPApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) })}
			api.msg(queue, c'setSuspended:', 1)
			mut weak_queue := u64(0)
			objc_store_weak(unsafe { &weak_queue }, queue)
			mut servers := []thread bool{}
			mut probes := [4]&HTTPDecisionProbe{}
			mut identities := [4]u64{}
			for i in 0 .. 4 {
				gate := url_session_response_decision_new()
				mut server_probe := unsafe { &HTTPDecisionProbe(C.calloc(1, sizeof(HTTPDecisionProbe))) }
				unsafe { *server_probe = HTTPDecisionProbe{gate: gate, mode: 'allow'} }
				probes[i] = server_probe
				listener := data_http_listener()
				servers << spawn http_decision_server(listener, tls, server_probe)
				object := objc_new(ios_runtime.names['NSObject'])
				objc_store_weak(unsafe { &p.held_weak[i] }, object)
				mut context := unsafe { &SessionWorkerHTTP(C.calloc(1, sizeof(SessionWorkerHTTP))) }
				unsafe { *context = SessionWorkerHTTP{probe: p, server_probe: server_probe, gate: gate, queue: objc_retain(queue), object: object,
					url: '${if tls { 'https' } else { 'http' }}://localhost:${listener.port}/', ca: cert.clone(), mode: mode} }
				identities[i] = url_session_workers_submit(context, session_worker_http_run, session_worker_http_cleanup)
				session_worker_require(identities[i] != 0, 'HTTP work was not accepted')
			}
			session_worker_wait(unsafe { &p.entered }, 4)
			session_worker_require(api.msg(queue, c'operationCount', 0) == 4, 'missing deferred response operations')
			if mode == 'stop' {
				for i in 4 .. 8 { session_worker_require(url_session_workers_submit(session_worker_unit(p, i, false), session_worker_unit_run, session_worker_unit_cleanup) != 0, 'queued shutdown work rejected') }
				url_session_workers_stop()
				session_worker_require(p.done == 8 && p.stopped == 8 && p.runs == 4, 'shutdown did not join running and discard queued work')
				session_worker_require(url_session_workers_submit(session_worker_unit(p, 8, false), session_worker_unit_run, session_worker_unit_cleanup) == 0 && p.stopped == 9, 'retired pool accepted new work')
				// Keep callbacks suspended: objc_stop must discard them after
				// the network contexts/cancellation cells have already retired.
			} else {
				if mode == 'cancel' { for id in identities { session_worker_require(url_session_workers_cancel(id), 'running cancellation failed') } }
				else { api.msg(queue, c'setSuspended:', 0) }
				session_worker_wait(unsafe { &p.done }, 4)
				if mode == 'cancel' { api.msg(queue, c'setSuspended:', 0) }
				api.msg(queue, c'waitUntilAllOperationsAreFinished', 0)
			}
			for server in servers { session_worker_require(server.wait(), 'loopback server failed') }
			unsafe { servers.free() }
			objc_release(queue); objc_pool_pop(pool)
			objc_stop()
			assert p.bad == 0 && p.responses == if mode == 'allow' { u64(4) } else { u64(0) };
			assert p.completed == if mode == 'stop' { u64(0) } else { u64(4) };
			for i in 0 .. 9 {
				assert p.held_weak[i] == 0;
				objc_destroy_weak(unsafe { &p.held_weak[i] })
			}
			assert weak_queue == 0 && ios_runtime.live == 0 && ios_runtime.block_refs.len == 0 && url_session_workers == unsafe { nil };
			objc_destroy_weak(unsafe { &weak_queue })
			for probe in probes { C.free(probe) }
			system_data_stop(); C.free(p)
		}
	}
	println('IOS-SESSION-WORKERS-HTTP: four blocked HTTP/TLS exchanges leave delegate workers available; cancellation, late response blocks, stop/join before dispatch discard, queued work retirement and weak ownership PASS')
}

fn session_worker_shutdown_run(_ voidptr, _ &u64) { objc_stop() }
fn session_worker_noop_run(_ voidptr, _ &u64) {}
fn session_worker_shutdown_cleanup(_ voidptr, _ URLSessionWorkerOutcome) { objc_stop() }
fn session_worker_noop_cleanup(_ voidptr, _ URLSessionWorkerOutcome) {}
fn session_worker_reject_watchdog() { time.sleep(5 * time.second); C._exit(124) }
fn test_session_worker_shutdown_rejections() {
	for mode in ['run', 'cleanup', 'rejected-cleanup'] {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0;
		pid := C.fork()
		assert pid >= 0;
		if pid == 0 {
			C.close(fds[0]); C.dup2(fds[1], 2); C.close(fds[1])
			spawn session_worker_reject_watchdog()
			objc_start(); system_data_start()!
			if mode == 'rejected-cleanup' { url_session_workers_stop() }
			url_session_workers_submit(unsafe { nil }, if mode == 'run' { session_worker_shutdown_run } else { session_worker_noop_run },
				if mode == 'run' { session_worker_noop_cleanup } else { session_worker_shutdown_cleanup })
			time.sleep(6 * time.second); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [8192]u8{}; mut length := 0
		for {
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0 && length + int(count) < bytes.len;
			length += int(count)
		}
		C.close(fds[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256;
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains('runtime shutdown inside URL session work or cleanup is not implemented'), output;
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output;
	}
	println('IOS-SESSION-WORKERS-REJECT: shutdown from run, worker cleanup and synchronous rejected cleanup fails before joins/retirement PASS')
}
