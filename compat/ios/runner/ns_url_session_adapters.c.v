// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Plain owned bytes, with no Objective-C references. The caller must keep the
// input objects alive and exclude concurrent mutation while capturing them.
// Later mutation and even runtime teardown cannot invalidate the snapshot.
// This adapter does not start a load or implement the policies it records.
struct URLSessionRequestSnapshot {
mut:
	issue URLSessionSnapshotIssue
	url string
	main_document string
	method string
	fields []HTTPTransportField
	body []u8
	request URLSessionRequestPolicy
	configuration URLSessionConfigurationPolicy
}

enum URLSessionSnapshotIssue { none storage url headers body }

struct URLSessionRequestPolicy {
	timeout f64
	cache u64
	service u64
	attribution u64
	cellular bool
	expensive bool
	constrained bool
	cookies bool
	pipelining bool
	http3 bool
	dnssec bool
	cookie_partition bool
}

struct URLSessionConfigurationPolicy {
	request_timeout f64
	resource_timeout f64
	cache u64
	service u64
	cookie_accept u64
	multipath i64
	maximum_connections i64
	tls_minimum i32
	tls_maximum i32
	cellular bool
	expensive bool
	constrained bool
	waits bool
	discretionary bool
	launch_events bool
	pipelining bool
	cookies bool
	dnssec bool
	background bool
	identifier bool
	shared_container bool
	proxy bool
	default_protocols bool
	custom_protocols bool
}

fn (snapshot &URLSessionRequestSnapshot) dispose() {
	for field in snapshot.fields { unsafe { field.name.free(); field.value.free() } }
	unsafe {
		snapshot.fields.free(); snapshot.body.free()
		snapshot.method.free(); snapshot.url.free(); snapshot.main_document.free()
		C.free(snapshot)
	}
}

fn (snapshot &URLSessionRequestSnapshot) borrowed_request() HTTPTransportRequest {
	return HTTPTransportRequest{method: snapshot.method, fields: snapshot.fields, body: snapshot.body}
}

fn url_session_snapshot_flag(configuration u64, offset u64) bool {
	return unsafe { *(&u8(configuration + offset)) != 0 }
}

// HTTPAdditionalHeaders is shallow-copied by the configuration. The source's
// strings and body can therefore still be mutable: clone bytes, not references.
// Request fields override configuration fields without case-sensitive aliases.
fn url_session_snapshot_fields(input u64, mut snapshot URLSessionRequestSnapshot) bool {
	if input == 0 { return true }
	if !objc_is_kind(input, ios_runtime.names['NSDictionary']) { return false }
	header := obj_header(input)
	if header.cf_raw_keys || header.cf_raw_values || header.keys.len != header.items.len || header.keys.len > 128 { return false }
	for i, key in header.keys {
		value := header.items[i]
		if !objc_is_kind(key, ios_runtime.names['NSString']) || !objc_is_kind(value, ios_runtime.names['NSString']) { return false }
		name := string_text(key); text := string_text(value)
		if !http_transport_token(name) || text.len > data_http_headers { return false }
		for byte in text { if (byte < 32 && byte != `\t`) || byte == 127 { return false } }
		mut index := -1
		for j, field in snapshot.fields { if request_ascii_equal(field.name, name) { index = j; break } }
		if index < 0 {
			if snapshot.fields.len == 128 { return false }
			snapshot.fields << HTTPTransportField{name: name.clone(), value: text.clone()}
		} else {
			old := snapshot.fields[index]
			snapshot.fields[index] = HTTPTransportField{name: name.clone(), value: text.clone()}
			unsafe { old.name.free(); old.value.free() }
		}
	}
	return true
}

fn url_session_request_snapshot(request u64, configuration u64) &URLSessionRequestSnapshot {
	mut result := unsafe { &URLSessionRequestSnapshot(C.calloc(1, sizeof(URLSessionRequestSnapshot))) }
	if result == unsafe { nil } { panic('iOS: cannot allocate URL session request snapshot') }
	result.fields = []HTTPTransportField{cap: 16}
	result.fields.flags |= .noslices
	// No constructors, application copies, dispatches or destructors in this
	// critical section. Plain allocations and byte copies cannot reenter user code.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	result.issue = .storage
	if request == 0 || configuration == 0 { return result }
	if read64(request) !in [ios_runtime.names['NSURLRequest'], ios_runtime.names['NSMutableURLRequest']]!
		|| read64(configuration) != ios_runtime.names['NSURLSessionConfiguration'] { return result }
	header := obj_header(request); config := url_session_configuration_state(configuration)
	if !header.request_owned || header.request == unsafe { nil } || header.destroying || header.destroyed { return result }
	source := header.request
	result.request = URLSessionRequestPolicy{timeout: source.timeout, cache: source.cache_policy,
		service: source.network_service, attribution: source.attribution, cellular: source.cellular,
		expensive: source.expensive, constrained: source.constrained, cookies: source.cookies,
		pipelining: source.pipelining, http3: source.http3, dnssec: source.dnssec, cookie_partition: source.refs[5] != 0}
	result.configuration = URLSessionConfigurationPolicy{
		request_timeout: unsafe { *(&f64(configuration + 176)) }, resource_timeout: unsafe { *(&f64(configuration + 184)) },
		cache: read64(configuration + 168), service: read64(configuration + 192), cookie_accept: read64(configuration + 216),
		multipath: i64(read64(configuration + 544)), maximum_connections: i64(i32(read32(configuration + 8))),
		tls_minimum: i32(read32(configuration + 140)), tls_maximum: i32(read32(configuration + 144)),
		cellular: url_session_snapshot_flag(configuration, 64), expensive: url_session_snapshot_flag(configuration, 65),
		constrained: url_session_snapshot_flag(configuration, 66), waits: url_session_snapshot_flag(configuration, 67),
		discretionary: url_session_snapshot_flag(configuration, 68), launch_events: url_session_snapshot_flag(configuration, 69),
		pipelining: url_session_snapshot_flag(configuration, 70), cookies: url_session_snapshot_flag(configuration, 71),
		dnssec: url_session_snapshot_flag(configuration, 72), background: url_session_snapshot_flag(configuration, 117),
		identifier: config.fields[0] != 0, shared_container: config.fields[1] != 0, proxy: config.fields[2] != 0,
		default_protocols: config.url_session_configuration_default_protocols,
		custom_protocols: config.fields[4] != 0 && obj_header(config.fields[4]).items.len != 0}
	result.issue = .url
	for i in 0 .. 2 {
		url := source.refs[i]
		if url == 0 { if i == 0 { return result }; continue }
		if read64(url) != ios_runtime.names['NSURL'] || obj_header(url).number != 1 { return result }
		text := string_text(obj_header(url).fields[1])
		if text.len == 0 || text.len > data_http_headers { return result }
		if i == 0 { result.url = text.clone() } else { result.main_document = text.clone() }
	}
	result.issue = .headers
	method := if source.refs[2] == 0 { 'GET' } else { string_text(source.refs[2]) }
	if !http_transport_token(method) { return result }
	result.method = method.clone()
	if !url_session_snapshot_fields(config.fields[3], mut result) || !url_session_snapshot_fields(source.refs[4], mut result) { return result }
	result.issue = .body
	if source.refs[3] != 0 {
		count := data_length(source.refs[3]); bytes := data_pointer(source.refs[3])
		if count > u64(data_http_limit) || (count != 0 && bytes == 0) { return result }
		if count != 0 {
			result.body = []u8{len: int(count)}
			unsafe { C.memcpy(result.body.data, voidptr(bytes), usize(count)) }
		}
	}
	result.issue = .none
	return result
}

enum URLSessionTransportProfile {
	supported snapshot protocols background proxy cookies cache network tls timeout wire
}

// Built-in HTTP(S) selection does not imply permission to ignore shared stores,
// custom protocols, proxy, TLS or network constraints.
fn (snapshot &URLSessionRequestSnapshot) transport_profile() URLSessionTransportProfile {
	if snapshot.issue != .none { return .snapshot }
	r := snapshot.request; c := snapshot.configuration
	route := snapshot.protocol_route()
	if route == .custom { return .protocols }
	if c.background || c.identifier || c.shared_container || c.launch_events { return .background }
	if c.proxy { return .proxy }
	if r.cookies || c.cookies || r.cookie_partition { return .cookies }
	if r.cache != 1 || c.cache != 1 { return .cache }
	if !r.cellular || !r.expensive || !r.constrained || r.service != 0 || r.pipelining || r.http3 || r.dnssec
		|| !c.cellular || !c.expensive || !c.constrained || c.waits || c.discretionary || c.service != 0
		|| c.multipath != 0 || c.pipelining || c.dnssec || c.maximum_connections <= 0 { return .network }
	if c.tls_minimum != 8 || c.tls_maximum != 0 { return .tls }
	if !math.is_finite(r.timeout) || !math.is_finite(c.request_timeout) || !math.is_finite(c.resource_timeout)
		|| r.timeout <= 0 || c.request_timeout <= 0 || c.resource_timeout <= 0 { return .timeout }
	// NSString request-field encoding has not yet been characterized beyond
	// ASCII. Preserve its bytes in the snapshot without claiming a wire mapping.
	for field in snapshot.fields { for byte in field.value { if byte >= 127 { return .wire } } }
	if route == .unsupported { return .wire }
	url := data_http_url(snapshot.url) or { return .wire }
	wire := http_transport_wire(url, snapshot.borrowed_request()) or { return .wire }
	unsafe { wire.free() }
	return .supported
}

struct URLSessionResponseSnapshot {
mut:
	status int
	fields []HTTPTransportField
}

fn (snapshot &URLSessionResponseSnapshot) dispose() {
	for field in snapshot.fields { unsafe { field.name.free(); field.value.free() } }
	unsafe { snapshot.fields.free(); C.free(snapshot) }
}

// HTTP header octets use Latin-1 at the Objective-C boundary (native oracle).
// Do not pass arbitrary wire octets to an NSString's UTF-8 backing storage.
fn url_session_header_utf8(text string) string {
	mut count := text.len
	for byte in text { if byte >= 128 { count++ } }
	buffer := unsafe { &u8(C.malloc(usize(count + 1))) }
	if buffer == unsafe { nil } { panic('iOS: cannot allocate HTTP response field') }
	mut position := 0
	for byte in text {
		unsafe {
			if byte < 128 { buffer[position] = byte; position++ }
			else { buffer[position] = 0xc0 | (byte >> 6); buffer[position + 1] = 0x80 | (byte & 63); position += 2 }
		}
	}
	unsafe { buffer[count] = 0; return tos(buffer, count) }
}

// Freeze the borrowed transport view BEFORE Objective-C allocation, because a
// replaced class initializer/constructor can mutate or retire caller storage.
// Raw transport fields stay separate; only response properties join duplicates.
fn url_session_response_snapshot(head HTTPTransportResponseHead) &URLSessionResponseSnapshot {
	if head.status < 200 || head.status > 599 || head.fields.len > 128 { return unsafe { nil } }
	mut size := 0
	for field in head.fields {
		if !http_transport_token(field.name) || field.value.len > data_http_headers { return unsafe { nil } }
		if field.name.len + field.value.len + 4 > data_http_headers - size { return unsafe { nil } }
		size += field.name.len + field.value.len + 4
		for byte in field.value { if (byte < 32 && byte != `\t`) || byte == 127 { return unsafe { nil } } }
	}
	mut result := unsafe { &URLSessionResponseSnapshot(C.calloc(1, sizeof(URLSessionResponseSnapshot))) }
	if result == unsafe { nil } { panic('iOS: cannot allocate URL session response snapshot') }
	result.status = head.status
	result.fields = []HTTPTransportField{cap: 16}
	result.fields.flags |= .noslices
	for field in head.fields {
		mut index := -1
		for i, previous in result.fields { if request_ascii_equal(previous.name, field.name) { index = i; break } }
		decoded := url_session_header_utf8(field.value)
		if decoded.len > data_http_headers {
			unsafe { decoded.free() }; result.dispose(); return unsafe { nil }
		}
		if index < 0 { result.fields << HTTPTransportField{name: field.name.clone(), value: decoded} }
		else {
			old := result.fields[index]
			if decoded.len + 2 > data_http_headers - old.value.len {
				unsafe { decoded.free() }; result.dispose(); return unsafe { nil }
			}
			joined := old.value + ', ' + decoded
			result.fields[index] = HTTPTransportField{name: old.name, value: joined}
			unsafe { old.value.free(); decoded.free() }
		}
	}
	return result
}

// Returns an owned NSHTTPURLResponse. All headers survive input disposal and
// queued delivery. This does not store cookies, process authentication, follow
// redirects or imply that any status (including 4xx/5xx) is a transport error.
fn url_session_response_object(url u64, head HTTPTransportResponseHead) u64 {
	snapshot := url_session_response_snapshot(head)
	if snapshot == unsafe { nil } { return 0 }
	defer { snapshot.dispose() }
	objc_retain(url)
	defer { objc_release(url) }
	headers := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	if headers == 0 { return 0 }
	defer { objc_release(headers) }
	for field in snapshot.fields {
		key := owned_string(field.name); value := owned_string(field.value)
		if key == 0 || value == 0 { objc_release(key); objc_release(value); return 0 }
		mut dictionary := obj_header(headers)
		cf_dictionary_insert(mut dictionary, key, value)
		objc_release(key); objc_release(value)
	}
	response := objc_allocate(ios_runtime.names['NSHTTPURLResponse'])
	if response != 0 { response_init_http(response, url, u64(snapshot.status), 0, headers) }
	return response
}

// Freeze borrowed body bytes before an NSData constructor can reenter. The
// returned object owns the buffer directly; no transport storage is retained.
fn url_session_data_object(bytes []u8) u64 {
	if bytes.len > data_http_limit { return 0 }
	mut owned := bytes.clone()
	owned.flags |= .noslices
	object := objc_allocate(ios_runtime.names['NSData'])
	if object == 0 { unsafe { owned.free() }; return 0 }
	obj_header(object).data = owned
	return object
}
