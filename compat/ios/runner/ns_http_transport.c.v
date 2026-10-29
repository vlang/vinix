// SPDX-License-Identifier: GPL-2.0-or-later
module main

import strings
import time

// One bounded exchange. Inputs are borrowed until return; results own every
// byte and can cross a worker boundary without touching the Objective-C runtime.
// Redirect and callback policy belongs to the session, not this socket layer.
struct HTTPTransportField {
	name string
	value string
}

struct HTTPTransportRequest {
	method string = 'GET'
	fields []HTTPTransportField
	body []u8
}

struct HTTPTransportResult {
	status int
	fields []HTTPTransportField
	body []u8
}

fn (result HTTPTransportResult) dispose() {
	result.dispose_fields()
	unsafe { result.body.free() }
}

fn (result HTTPTransportResult) dispose_fields() {
	for field in result.fields { unsafe { field.name.free(); field.value.free() } }
	unsafe { result.fields.free() }
}

// The returned view lives as long as the result. Repeated fields remain
// separate in fields (notably Set-Cookie); policy callers choose how to join.
fn (result HTTPTransportResult) field(name string) ?string {
	for field in result.fields { if data_http_equal(field.name, name) { return field.value } }
	return none
}

fn http_transport_token(text string) bool {
	if text.len == 0 || text.len > 256 { return false }
	for byte in text {
		if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `0` && byte <= `9`)
			|| byte in [u8(33), 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126]) { return false }
	}
	return true
}

fn http_transport_wire(url DataHTTPURL, input HTTPTransportRequest) ?string {
	// CONNECT requires a tunnel; TRACE forbids a body. Neither is a data load.
	if input.method !in ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']
		|| input.fields.len > 128 || input.body.len > data_http_limit { return none }
	mut size := input.method.len + url.target.len + url.authority.len + 160
	for i, field in input.fields {
		if !http_transport_token(field.name) { return none }
		for byte in field.value { if (byte < 32 && byte != `\t`) || byte == 127 { return none } }
		for j in 0 .. i { if data_http_equal(input.fields[j].name, field.name) { return none } }
		// Own the framing and origin. Accept matching supplied framing once,
		// rather than silently sending conflicting fields or ignoring a value.
		if data_http_equal(field.name, 'Content-Length') {
			length := data_http_number(field.value, 10) or { return none }
			if length != input.body.len { return none }
		} else if data_http_equal(field.name, 'Host') {
			if !data_http_equal(field.value, url.authority) { return none }
		} else if data_http_equal(field.name, 'Connection') {
			if !data_http_equal(field.value, 'close') { return none }
		} else if data_http_equal(field.name, 'Accept-Encoding') {
			if !data_http_equal(field.value, 'identity') { return none }
		} else if data_http_equal(field.name, 'Transfer-Encoding') || data_http_equal(field.name, 'Expect')
			|| data_http_equal(field.name, 'Trailer') || data_http_equal(field.name, 'Upgrade') { return none }
		if field.name.len + field.value.len > data_http_headers - size - 4 { return none }
		size += field.name.len + field.value.len + 4
	}
	if size > data_http_headers { return none }
	// The frozen V compiler boxes an escaping mutable builder header. Own that
	// header explicitly as well as its buffer, so repeated requests free both.
	mut builder := unsafe { &strings.Builder(C.calloc(1, sizeof(strings.Builder))) }
	if builder == unsafe { nil } { panic('iOS: cannot allocate HTTP request builder') }
	unsafe { *builder = strings.new_builder(size) }
	defer { unsafe { builder.free(); C.free(builder) } }
	builder.write_string(input.method); builder.write_string(' ')
	if url.target.len == 0 || url.target[0] == `?` { builder.write_string('/') }
	builder.write_string(url.target)
	builder.write_string(' HTTP/1.1\r\nHost: '); builder.write_string(url.authority)
	builder.write_string('\r\nAccept-Encoding: identity\r\nConnection: close\r\n')
	for field in input.fields {
		if data_http_equal(field.name, 'Host') || data_http_equal(field.name, 'Content-Length')
			|| data_http_equal(field.name, 'Connection') || data_http_equal(field.name, 'Accept-Encoding') { continue }
		builder.write_string(field.name); builder.write_string(': '); builder.write_string(field.value); builder.write_string('\r\n')
	}
	if input.body.len != 0 || input.method in ['POST', 'PUT', 'PATCH'] || input.fields.any(data_http_equal(it.name, 'Content-Length')) {
		length := input.body.len.str()
		builder.write_string('Content-Length: '); builder.write_string(length); builder.write_string('\r\n')
		unsafe { length.free() }
	}
	builder.write_string('\r\n')
	result := builder.str()
	return result
}

fn http_transport_exchange(text string, input HTTPTransportRequest, ca_file string, timeout i64) ?HTTPTransportResult {
	return http_transport_exchange_control(text, input, ca_file, timeout, unsafe { nil })
}

// The caller keeps the atomic cancellation cell alive until return. Cancelled
// reads remain failures, including close-delimited and partially cached bodies.
fn http_transport_exchange_control(text string, input HTTPTransportRequest, ca_file string, timeout i64, cancel &u64) ?HTTPTransportResult {
	if data_http_cancelled(cancel) { return none }
	url := data_http_url(text) or { return none }
	wire := http_transport_wire(url, input) or { return none }
	defer { unsafe { wire.free() } }
	if timeout <= 0 || timeout > 24 * time.hour { return none }
	deadline := time.sys_mono_now() + timeout
	mut stream := &DataHTTPStream{fd: data_http_connect_control(url, deadline, cancel), deadline: deadline, cancel: cancel}
	defer { stream.close(); unsafe { free(stream) } }
	if stream.fd < 0 || data_http_cancelled(cancel) || (url.tls && !stream.secure(url.host, ca_file)) || !stream.send(wire) { return none }
	if input.body.len != 0 && !stream.send(unsafe { tos(input.body.data, input.body.len) }) { return none }
	mut storage := []u8{cap: data_http_headers}; storage.flags |= .noslices
	defer { unsafe { storage.free() } }
	mut start := 0
	mut response := stream.headers(mut storage) or { return none }
	for response.status in [100, 102, 103] {
		start = storage.len
		response = stream.headers(mut storage) or { return none }
	}
	if response.status < 200 { return none } // No upgrade/tunnel protocol.
	// Capture the final header block before the body decoder appends trailers.
	mut fields := []HTTPTransportField{cap: 16}; fields.flags |= .noslices
	mut success := false
	defer {
		if !success {
			for field in fields { unsafe { field.name.free(); field.value.free() } }
			unsafe { fields.free() }
		}
	}
	mut offset := start
	for offset < storage.len && storage[offset] != `\n` { offset++ }
	offset++
	for offset + 2 < storage.len {
		end := offset
		mut line_end := end
		for line_end < storage.len && storage[line_end] != `\r` { line_end++ }
		if line_end == end { break }
		line := unsafe { tos(&u8(storage.data) + offset, line_end - offset) }
		colon := line.index(':') or { return none }
		if fields.len == 128 { return none }
		fields << HTTPTransportField{name: http_borrow(line, 0, colon).clone(),
			value: data_http_trim(http_borrow(line, colon + 1, line.len)).clone()}
		offset = line_end + 2
	}
	body := data_http_body(mut stream, response, mut storage, input.method == 'HEAD') or { return none }
	if data_http_cancelled(cancel) { unsafe { body.free() }; return none }
	success = true
	return HTTPTransportResult{status: response.status, fields: fields, body: body}
}
