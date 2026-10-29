// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Use V's bundled TLS implementation on both Darwin and Vinix. Each load owns
// and frees its socket, TLS state and response storage, including error paths.
import iostls as _
import time
import os

fn C.mbedtls_ssl_get_verify_result(&C.mbedtls_ssl_context) u32

// musl builds of the bundled TLS library default to /dev/random, while Vinix
// exposes its secure generator through getentropy/getrandom and /dev/urandom.
// Reuse the checked, chunked OS CSPRNG reader; never substitute a local seed.
fn data_http_os_entropy(_ voidptr, bytes &u8, size usize) i32 {
	return if cc_random_generate(bytes, u64(size)) == 0 { i32(0) } else { i32(C.MBEDTLS_ERR_ENTROPY_SOURCE_FAILED) }
}

const data_http_limit = 16 * 1024 * 1024
const data_http_headers = 64 * 1024

struct DataHTTPURL {
	host string
	service string
	authority string
	target string
	tls bool
}

fn data_http_equal(a string, b string) bool {
	if a.len != b.len { return false }
	for i in 0 .. a.len {
		mut byte := a[i]
		mut other := b[i]
		if byte >= `A` && byte <= `Z` { byte += 32 }
		if other >= `A` && other <= `Z` { other += 32 }
		if byte != other { return false }
	}
	return true
}

// Borrow all components from the caller's URL. Never pass an untrusted
// redirect through NSURL's deliberately strict, panic-producing constructor.
fn data_http_url(text string) ?DataHTTPURL {
	if text.len == 0 || text.len > 65536 { return none }
	for i, byte in text {
		if byte <= 32 || byte >= 127 || byte in [u8(`\\`), `"`, `<`, `>`, `^`, 96, `{`, `}`, `|`] { return none }
		if byte == `%` && (i + 2 >= text.len || http_hex(text[i + 1]) < 0 || http_hex(text[i + 2]) < 0) { return none }
	}
	start := text.index('://') or { return none }
	scheme := http_borrow(text, 0, start)
	tls := data_http_equal(scheme, 'https')
	if !tls && !data_http_equal(scheme, 'http') { return none }
	mut end := start + 3
	for end < text.len && text[end] !in [u8(`/`), `?`, `#`] { end++ }
	authority := http_borrow(text, start + 3, end)
	mut colon := authority.len
	for i, byte in authority {
		if byte == `:` { if colon != authority.len { return none }; colon = i; continue }
		if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `0` && byte <= `9`) || byte in [u8(`-`), `.`, `_`]) { return none }
	}
	if colon == 0 { return none }
	mut service := if tls { '443' } else { '80' }
	if colon != authority.len {
		service = http_borrow(authority, colon + 1, authority.len)
		if service.len == 0 || service.len > 5 { return none }
		mut port := 0
		for byte in service { if byte < `0` || byte > `9` { return none }; port = port * 10 + int(byte - `0`) }
		if port == 0 || port > 65535 { return none }
	}
	mut tail := end
	for tail < text.len && text[tail] != `#` { tail++ }
	return DataHTTPURL{host: http_borrow(authority, 0, colon), service: service,
		authority: authority, target: http_borrow(text, end, tail), tls: tls}
}

fn data_http_wait(fd int, write bool, deadline i64) bool {
	return data_http_wait_control(fd, write, deadline, unsafe { nil })
}

fn data_http_cancelled(cancel &u64) bool {
	return cancel != unsafe { nil } && C.ios_load_pointer(cancel) != 0
}

// A task owns the cancellation cell until this synchronous exchange returns.
// Poll in bounded intervals so cancellation never closes a descriptor from a
// different thread (which could race descriptor reuse). DNS retains its own
// platform timeout; socket/TLS waits observe cancellation within 50 ms.
fn data_http_wait_control(fd int, write bool, deadline i64, cancel &u64) bool {
	for {
		left := deadline - time.sys_mono_now()
		if left <= 0 || data_http_cancelled(cancel) { return false }
		mut descriptor := C.pollfd{fd: fd, events: i16(if write { C.POLLOUT } else { C.POLLIN })}
		mut interval := left / time.millisecond + 1
		if cancel != unsafe { nil } && interval > 50 { interval = 50 }
		result := C.poll(unsafe { &descriptor }, 1, i32(interval))
		if result > 0 { return descriptor.revents & i16(C.POLLNVAL) == 0 }
		if result == 0 { if cancel != unsafe { nil } { continue }; return false }
		if unsafe { *C.ios_errno_address() } != C.EINTR { return false }
	}
	return false
}

fn data_http_no_sigpipe(fd int) {
	$if macos {
		mut enabled := i32(1)
		C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &enabled, u32(sizeof(enabled)))
	}
}

// mbedTLS's stock Unix sender uses write(), which can terminate the whole
// runner with SIGPIPE when a peer closes. Preserve its nonblocking contract.
fn data_http_tls_send(context voidptr, buffer &u8, size usize) i32 {
	fd := unsafe { &C.mbedtls_net_context(context) }.fd
	result := C.send(fd, buffer, size, C.MSG_NOSIGNAL)
	if result >= 0 { return i32(result) }
	error := unsafe { *C.ios_errno_address() }
	if error in [C.EINTR, C.EAGAIN, C.EWOULDBLOCK] { return C.MBEDTLS_ERR_SSL_WANT_WRITE }
	if error in [C.EPIPE, C.ECONNRESET] { return C.MBEDTLS_ERR_NET_CONN_RESET }
	return C.MBEDTLS_ERR_NET_SEND_FAILED
}

fn data_http_connect(url DataHTTPURL, deadline i64) int {
	return data_http_connect_control(url, deadline, unsafe { nil })
}

fn data_http_connect_control(url DataHTTPURL, deadline i64, cancel &u64) int {
	if data_http_cancelled(cancel) { return -1 }
	host := url.host.clone(); service := url.service.clone()
	defer { unsafe { host.free(); service.free() } }
	hints := C.addrinfo{ai_family: C.AF_UNSPEC, ai_socktype: C.SOCK_STREAM}
	mut addresses := unsafe { &C.addrinfo(nil) }
	// The resolver retains its platform timeout; all socket work shares one
	// deadline across addresses, redirects, handshake, headers and body.
	if C.getaddrinfo(host.str, service.str, &hints, &addresses) != 0 { return -1 }
	defer { C.freeaddrinfo(addresses) }
	mut address := addresses
	for address != unsafe { nil } && time.sys_mono_now() < deadline && !data_http_cancelled(cancel) {
		fd := C.socket(address.ai_family, address.ai_socktype, address.ai_protocol)
		if fd >= 0 {
			data_http_no_sigpipe(fd)
			flags := C.fcntl(fd, C.F_GETFL, usize(0))
			if flags >= 0 && C.fcntl(fd, C.F_SETFL, usize(flags | C.O_NONBLOCK)) == 0 {
				result := C.connect(fd, address.ai_addr, address.ai_addrlen)
				if result == 0 { return fd }
				if unsafe { *C.ios_errno_address() } == C.EINPROGRESS && data_http_wait_control(fd, true, deadline, cancel) {
					mut error := i32(0); mut size := u32(sizeof(error))
					if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &error, &size) == 0 && error == 0 { return fd }
				}
			}
			C.close(fd)
		}
		address = address.ai_next
	}
	return -1
}

struct DataHTTPStream {
mut:
	fd int = -1
	tls bool
	deadline i64
	cancel &u64 = unsafe { nil }
	ssl C.mbedtls_ssl_context
	config C.mbedtls_ssl_config
	ca C.mbedtls_x509_crt
	rng C.mbedtls_ctr_drbg_context
	entropy C.mbedtls_entropy_context
	net C.mbedtls_net_context
	buffer [8192]u8
	position int
	length int
	eof bool
}

fn (mut stream DataHTTPStream) close() {
	if stream.tls {
		C.mbedtls_ssl_free(&stream.ssl); C.mbedtls_ssl_config_free(&stream.config)
		C.mbedtls_x509_crt_free(&stream.ca); C.mbedtls_ctr_drbg_free(&stream.rng)
		C.mbedtls_entropy_free(&stream.entropy)
	}
	if stream.fd >= 0 { C.close(stream.fd); stream.fd = -1 }
}

fn (mut stream DataHTTPStream) retry(result int) bool {
	if time.sys_mono_now() >= stream.deadline || data_http_cancelled(stream.cancel) { return false }
	if stream.tls {
		if result == C.MBEDTLS_ERR_SSL_WANT_READ { return data_http_wait_control(stream.fd, false, stream.deadline, stream.cancel) }
		if result == C.MBEDTLS_ERR_SSL_WANT_WRITE { return data_http_wait_control(stream.fd, true, stream.deadline, stream.cancel) }
		return result == C.MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET
	}
	error := unsafe { *C.ios_errno_address() }
	return error == C.EINTR || ((error == C.EAGAIN || error == C.EWOULDBLOCK) && data_http_wait_control(stream.fd, false, stream.deadline, stream.cancel))
}

fn (mut stream DataHTTPStream) secure(host string, ca_file string) bool {
	stream.tls = true
	C.mbedtls_ssl_init(&stream.ssl); C.mbedtls_ssl_config_init(&stream.config)
	C.mbedtls_x509_crt_init(&stream.ca); C.mbedtls_ctr_drbg_init(&stream.rng); C.mbedtls_entropy_init(&stream.entropy)
	mut result := C.mbedtls_x509_crt_parse_file(&stream.ca, ca_file.str)
	if result != 0 { return stream.tls_failure('ca-file', result) }
	result = C.mbedtls_ctr_drbg_seed(&stream.rng, data_http_os_entropy, unsafe { nil }, c'vinix-ios-data', 14)
	if result != 0 { return stream.tls_failure('entropy', result) }
	result = C.mbedtls_ssl_config_defaults(&stream.config, C.MBEDTLS_SSL_IS_CLIENT, C.MBEDTLS_SSL_TRANSPORT_STREAM, C.MBEDTLS_SSL_PRESET_DEFAULT)
	if result != 0 { return stream.tls_failure('config', result) }
	C.mbedtls_ssl_conf_authmode(&stream.config, C.MBEDTLS_SSL_VERIFY_REQUIRED)
	C.mbedtls_ssl_conf_ca_chain(&stream.config, &stream.ca, unsafe { nil })
	C.mbedtls_ssl_conf_rng(&stream.config, C.mbedtls_ctr_drbg_random, &stream.rng)
	name := host.clone(); defer { unsafe { name.free() } }
	result = C.mbedtls_ssl_setup(&stream.ssl, &stream.config)
	if result != 0 { return stream.tls_failure('setup', result) }
	result = C.mbedtls_ssl_set_hostname(&stream.ssl, name.str)
	if result != 0 { return stream.tls_failure('hostname', result) }
	stream.net.fd = stream.fd
	C.mbedtls_ssl_set_bio(&stream.ssl, &stream.net, unsafe { &C.mbedtls_ssl_send_t(voidptr(data_http_tls_send)) }, C.mbedtls_net_recv, unsafe { nil })
	for time.sys_mono_now() < stream.deadline && !data_http_cancelled(stream.cancel) {
		result = C.mbedtls_ssl_handshake(&stream.ssl)
		if result == 0 { return true }
		if !stream.retry(result) { return stream.tls_failure('handshake', result) }
	}
	return false
}

fn (stream &DataHTTPStream) tls_failure(stage string, code int) bool {
	trace := os.getenv('VINIX_IOS_HTTP_TRACE')
	defer { unsafe { trace.free() } }
	if trace == '1' {
		flags := if stage == 'handshake' { C.mbedtls_ssl_get_verify_result(&stream.ssl) } else { u32(0) }
		mut buffer := [192]u8{}
		count := C.snprintf(unsafe { &char(&buffer[0]) }, usize(buffer.len), c'IOS-DATA-HTTP-TLS-FAIL: %.*s code=%d verify=%u\n', i32(stage.len), stage.str, i32(code), flags)
		if count > 0 && count < buffer.len { C.write(2, &buffer[0], usize(count)) }
	}
	return false
}

fn (mut stream DataHTTPStream) send(request string) bool {
	return stream.send_counted(request, unsafe { nil })
}

fn (mut stream DataHTTPStream) send_counted(request string, sent &u64) bool {
	mut offset := 0
	for offset < request.len && time.sys_mono_now() < stream.deadline && !data_http_cancelled(stream.cancel) {
		result := if stream.tls { int(C.mbedtls_ssl_write(&stream.ssl, unsafe { request.str + offset }, usize(request.len - offset))) }
			else { int(C.send(stream.fd, unsafe { request.str + offset }, usize(request.len - offset), C.MSG_NOSIGNAL)) }
		if result > 0 {
			offset += result
			if sent != unsafe { nil } { C.ios_store_pointer(sent, u64(offset)) }
			continue
		}
		if result == 0 { return false }
		if !stream.tls {
			error := unsafe { *C.ios_errno_address() }
			if error == C.EINTR { continue }
			if (error == C.EAGAIN || error == C.EWOULDBLOCK) && data_http_wait_control(stream.fd, true, stream.deadline, stream.cancel) { continue }
			return false
		}
		if !stream.retry(result) { return false }
	}
	return offset == request.len
}

fn (mut stream DataHTTPStream) read() ?u8 {
	if data_http_cancelled(stream.cancel) { return none }
	if stream.position == stream.length {
		for {
			if time.sys_mono_now() >= stream.deadline || data_http_cancelled(stream.cancel) { return none }
			result := if stream.tls { int(C.mbedtls_ssl_read(&stream.ssl, &stream.buffer[0], usize(stream.buffer.len))) }
				else { int(C.recv(stream.fd, &stream.buffer[0], usize(stream.buffer.len), 0)) }
			if result > 0 { stream.position = 0; stream.length = result; break }
			if result == 0 || (stream.tls && result == C.MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) {
				stream.eof = !stream.tls || result == C.MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY
				return none
			}
			if !stream.retry(result) { return none }
		}
	}
	value := stream.buffer[stream.position]; stream.position++
	return value
}

fn (mut stream DataHTTPStream) line(mut storage []u8) ?string {
	start := storage.len
	for storage.len < data_http_headers {
		byte := stream.read() or { return none }
		storage << byte
		if byte == `\n` {
			if storage.len - start < 2 || storage[storage.len - 2] != `\r` { return none }
			return unsafe { tos(&u8(storage.data) + start, storage.len - start - 2) }
		}
		if storage.len > start + 1 && storage[storage.len - 2] == `\r` { return none }
		if byte == 0 || (byte < 32 && byte !in [u8(`\r`), `\t`]) || byte == 127 { return none }
	}
	return none
}

fn data_http_trim(text string) string {
	mut first := 0; mut last := text.len
	for first < last && text[first] in [u8(` `), `\t`] { first++ }
	for last > first && text[last - 1] in [u8(` `), `\t`] { last-- }
	return http_borrow(text, first, last)
}

fn data_http_number(text string, base int) ?int {
	if text.len == 0 { return none }
	mut value := 0
	for byte in text {
		digit := http_hex(byte)
		if digit < 0 || digit >= base || value > (data_http_limit - digit) / base { return none }
		value = value * base + digit
	}
	return value
}

struct DataHTTPResponse {
	status int
	length int = -1
	chunked bool
	location string
}

fn (mut stream DataHTTPStream) headers(mut storage []u8) ?DataHTTPResponse {
	line := stream.line(mut storage) or { return none }
	if line.len < 12 || !(line.starts_with('HTTP/1.0 ') || line.starts_with('HTTP/1.1 '))
		|| (line.len > 12 && line[12] != ` `) { return none }
	status := data_http_number(http_borrow(line, 9, 12), 10) or { return none }
	if status < 100 || status > 599 { return none }
	mut length := -1; mut chunked := false; mut location := ''
	for {
		header := stream.line(mut storage) or { return none }
		if header.len == 0 { break }
		colon := header.index(':') or { return none }
		if colon == 0 { return none }
		name := http_borrow(header, 0, colon)
		for byte in name { if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`) || (byte >= `0` && byte <= `9`) || byte in [u8(`!`), `#`, `$`, `%`, `&`, 39, `*`, `+`, `-`, `.`, `^`, `_`, 96, `|`, `~`]) { return none } }
		value := data_http_trim(http_borrow(header, colon + 1, header.len))
		if data_http_equal(name, 'content-length') {
			if length >= 0 || chunked { return none }
			length = data_http_number(value, 10) or { return none }
		} else if data_http_equal(name, 'transfer-encoding') {
			if chunked || length >= 0 || !data_http_equal(value, 'chunked') { return none }
			chunked = true
		} else if data_http_equal(name, 'location') {
			if location.len != 0 { return none }; location = value
		} else if data_http_equal(name, 'content-encoding') && !data_http_equal(value, 'identity') { return none }
	}
	return DataHTTPResponse{status: status, length: length, chunked: chunked, location: location}
}

// Resolve ordinary relative redirect references without decoding request bytes.
fn data_http_redirect(current string, location string) ?string {
	if location.len == 0 || location.len > 65536 { return none }
	url := data_http_url(current) or { return none }
	if location.contains('://') { data_http_url(location) or { return none }; return location.clone() }
	scheme := if url.tls { 'https:' } else { 'http:' }
	if location.starts_with('//') { return scheme + location }
	base := '${scheme}//${url.authority}'
	defer { unsafe { base.free() } }
	if location[0] == `/` { return base + location }
	mut path := url.target
	if query := path.index('?') { path = http_borrow(path, 0, query) }
	if location[0] == `?` { return '${base}${if path.len == 0 { '/' } else { path }}${location}' }
	if location[0] == `#` { return current + location }
	last := path.last_index('/') or { -1 }
	return '${base}${if last < 0 { '/' } else { http_borrow(path, 0, last + 1) }}${location}'
}

fn data_http_fetch(original string, ca_file string, timeout i64) ?[]u8 {
	mut current := original.clone()
	defer { unsafe { current.free() } }
	deadline := time.sys_mono_now() + timeout
	for _ in 0 .. 6 {
		url := data_http_url(current) or { return none }
		response := http_transport_exchange(current, HTTPTransportRequest{}, ca_file, deadline - time.sys_mono_now()) or { return none }
		mut transferred := false
		defer { response.dispose_fields(); if !transferred { unsafe { response.body.free() } } }
		if response.status in [301, 302, 303, 307, 308] {
			location := response.field('location') or { return none }
			next := data_http_redirect(current, location) or { return none }
			// Refuse transport downgrade rather than expose an HTTPS request.
			next_url := data_http_url(next) or { unsafe { next.free() }; return none }
			if url.tls && !next_url.tls { unsafe { next.free() }; return none }
			unsafe { current.free() }; current = next
			continue
		}
		if response.status < 200 || response.status >= 300 { return none }
		transferred = true
		return response.body
	}
	return none
}

// Shared framing for NSData and the session transport. The caller decides
// whether an HTTP status is acceptable; framing errors never become success.
fn data_http_body(mut stream DataHTTPStream, response DataHTTPResponse, mut headers []u8, head bool) ?[]u8 {
	return data_http_body_counted(mut stream, response, mut headers, head, unsafe { nil })
}

fn data_http_body_counted(mut stream DataHTTPStream, response DataHTTPResponse, mut headers []u8, head bool, received &u64) ?[]u8 {
	mut body := []u8{cap: if head { 0 } else if response.length >= 0 { response.length } else { 8192 }}; body.flags |= .noslices
	mut success := false
	defer { if !success { unsafe { body.free() } } }
	if head || response.status == 304 { success = true; return body }
	if response.status in [204, 205] {
		if response.length > 0 || response.chunked { return none }
		success = true; return body
	}
	if !response.chunked && response.length < 0 {
		for {
			byte := stream.read() or {
				if !stream.eof { return none }
				break
			}
			if body.len == data_http_limit { return none }
			body << byte
			if received != unsafe { nil } { C.ios_store_pointer(received, u64(body.len)) }
		}
		success = true; return body
	}
	for {
		mut count := response.length
		if response.chunked {
			line := stream.line(mut headers) or { return none }
			end := line.index(';') or { line.len }
			count = data_http_number(http_borrow(line, 0, end), 16) or { return none }
			if count == 0 {
				for { trailer := stream.line(mut headers) or { return none }; if trailer.len == 0 { break }; if !trailer.contains(':') { return none } }
				break
			}
		}
		if count > data_http_limit - body.len { return none }
		for _ in 0 .. count {
			body << stream.read() or { return none }
			if received != unsafe { nil } { C.ios_store_pointer(received, u64(body.len)) }
		}
		if !response.chunked { break }
		if stream.read() or { return none } != `\r` || stream.read() or { return none } != `\n` { return none }
	}
	success = true
	return body
}

fn data_http_load(url u64, cls u64) u64 {
	bytes := data_http_fetch(ctext(u64(obj_header(obj_header(url).fields[1]).text)), '/etc/ssl/cert.pem', 10 * time.second) or { return 0 }
	result := objc_allocate(cls)
	mut header := obj_header(result)
	header.data = bytes
	return objc_autorelease(result)
}
