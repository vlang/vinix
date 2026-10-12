// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Public request data is owned outside the measured 24-byte native record.
// The private Foundation/CFNetwork ivars remain reserved; no load is started.
struct URLRequestState {
mut:
	refs [6]u64 // URL, main-document URL, method, body, headers, cookie partition.
	timeout f64
	cache_policy u64
	network_service u64
	attribution u64
	mutable bool
	cellular bool
	expensive bool
	constrained bool
	cookies bool
	pipelining bool
	http3 bool
	dnssec bool
}

fn request_name(cls u64) string {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return '' }
		if info.name in ['NSURLRequest', 'NSMutableURLRequest'] { return info.name }
		current = info.parent
		if current == 0 { return '' }
	}
	panic('iOS: cyclic request superclass chain')
}

fn request_types(name string, meta bool, selector string) ?string {
	if name !in ['NSURLRequest', 'NSMutableURLRequest'] { return none }
	if meta {
		return match selector {
			'requestWithURL:' { '@24@0:8@16' }
			'requestWithURL:cachePolicy:timeoutInterval:' { '@40@0:8@16Q24d32' }
			else { return none }
		}
	}
	match selector {
		'init', 'copy', 'mutableCopy', 'URL', 'mainDocumentURL', 'HTTPMethod', 'HTTPBody', 'HTTPBodyStream', 'allHTTPHeaderFields', 'cookiePartitionIdentifier' { return '@16@0:8' }
		'initWithURL:', 'valueForHTTPHeaderField:' { return '@24@0:8@16' }
		'initWithURL:cachePolicy:timeoutInterval:' { return '@40@0:8@16Q24d32' }
		'copyWithZone:', 'mutableCopyWithZone:' { return '@24@0:8^{_NSZone=}16' }
		'timeoutInterval' { return 'd16@0:8' }
		'cachePolicy', 'networkServiceType', 'attribution' { return 'Q16@0:8' }
		'allowsCellularAccess', 'allowsExpensiveNetworkAccess', 'allowsConstrainedNetworkAccess', 'HTTPShouldHandleCookies', 'HTTPShouldUsePipelining', 'assumesHTTP3Capable', 'requiresDNSSECValidation' { return 'B16@0:8' }
		else {}
	}
	if name != 'NSMutableURLRequest' { return none }
	return match selector {
		'setURL:', 'setMainDocumentURL:', 'setHTTPMethod:', 'setHTTPBody:', 'setHTTPBodyStream:', 'setAllHTTPHeaderFields:', 'setCookiePartitionIdentifier:' { 'v24@0:8@16' }
		'setValue:forHTTPHeaderField:', 'addValue:forHTTPHeaderField:' { 'v32@0:8@16@24' }
		'setCachePolicy:', 'setNetworkServiceType:', 'setAttribution:' { 'v24@0:8Q16' }
		'setTimeoutInterval:' { 'v24@0:8d16' }
		'setAllowsCellularAccess:', 'setAllowsExpensiveNetworkAccess:', 'setAllowsConstrainedNetworkAccess:', 'setHTTPShouldHandleCookies:', 'setHTTPShouldUsePipelining:', 'setAssumesHTTP3Capable:', 'setRequiresDNSSECValidation:' { 'v20@0:8B16' }
		else { return none }
	}
}

fn request_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	name := request_name(if meta { object } else { read64(object) })
	return request_types(name, meta, selector) != none
}

fn request_url(value u64) {
	if value != 0 && !objc_is_kind(value, ios_runtime.names['NSURL']) { panic('iOS: request URL must be a URL') }
}

fn request_initialize(object u64, url u64, cache u64, timeout f64) {
	mut header := obj_header(object)
	if !header.request_owned || header.native_size < 24 { panic('iOS: invalid request storage') }
	if header.request != unsafe { nil } { panic('iOS: request reinitialization is not implemented') }
	request_url(url)
	if cache > 5 || !math.is_finite(timeout) { panic('iOS: unsupported request cache policy or timeout') }
	header.request = unsafe { &URLRequestState(C.calloc(1, sizeof(URLRequestState))) }
	if header.request == unsafe { nil } { panic('iOS: cannot allocate request state') }
	header.request.refs[0] = if url == 0 { u64(0) } else { objc_copy_value(url, false) }
	header.request.refs[2] = owned_string('GET')
	header.request.timeout = timeout
	header.request.cache_policy = cache
	header.request.mutable = objc_is_kind(object, ios_runtime.names['NSMutableURLRequest'])
	header.request.cellular = true
	header.request.expensive = true
	header.request.constrained = true
	header.request.cookies = true
}

fn request_dispose(mut header ObjHeader) {
	if header.request == unsafe { nil } { return }
	for value in header.request.refs { objc_release(value) }
	C.free(header.request)
	header.request = unsafe { nil }
}

fn request_dictionary_copy(object u64) u64 {
	if object == 0 { return 0 }
	copy := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	mut target := obj_header(copy)
	for key in obj_header(object).keys { target.keys << objc_retain(key) }
	for value in obj_header(object).items { target.items << objc_retain(value) }
	return copy
}

fn request_copy(object u64, mutable_copy bool) u64 {
	source := obj_header(object).request
	if source == unsafe { nil } { panic('iOS: request is not initialized') }
	if !source.mutable && !mutable_copy { return objc_retain(object) }
	copy := objc_allocate(ios_runtime.names['NSMutableURLRequest'])
	mut header := obj_header(copy)
	header.request = unsafe { &URLRequestState(C.calloc(1, sizeof(URLRequestState))) }
	if header.request == unsafe { nil } { panic('iOS: cannot copy request state') }
	unsafe { *header.request = *source }
	header.request.mutable = true
	for i, value in source.refs { header.request.refs[i] = if i == 4 { request_dictionary_copy(value) } else { objc_retain(value) } }
	return copy
}

fn request_ascii_equal(left string, right string) bool {
	if left.len != right.len { return false }
	for i, a in left {
		b := right[i]
		folded_a := if a >= `a` && a <= `z` { a - 32 } else { a }
		folded_b := if b >= `a` && b <= `z` { b - 32 } else { b }
		if folded_a != folded_b { return false }
	}
	return true
}

fn request_string(value u64, field bool) string {
	if value == 0 || !objc_is_kind(value, ios_runtime.names['NSString']) { panic('iOS: request header and method values must be strings') }
	text := string_text(value)
	if text.len > 65536 { panic('iOS: request string exceeds limit') }
	for b in text { if b == 0 || b == 10 || b == 13 { panic('iOS: request string contains a control byte') } }
	if field {
		if text.len == 0 || text.len > 256 { panic('iOS: request field name exceeds the token profile') }
		for b in text {
			if !((b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`) || (b >= `0` && b <= `9`) || b in [u8(33), 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126]) { panic('iOS: request field name requires an ASCII token') }
		}
	}
	return text
}

fn request_header_index(headers u64, name string) int {
	if headers == 0 { return -1 }
	for i, key in obj_header(headers).keys { if request_ascii_equal(string_text(key), name) { return i } }
	return -1
}

fn request_header_put(headers u64, key u64, value u64, append_value bool) {
	name := request_string(key, true)
	if value != 0 { request_string(value, false) }
	mut header := obj_header(headers)
	index := request_header_index(headers, name)
	if value == 0 { if append_value { panic('iOS: request header append requires a value') }; if index >= 0 { collection_remove(mut header, index) }; return }
	if index < 0 {
		if header.keys.len >= 128 { panic('iOS: request header count exceeds limit') }
		header.keys << objc_retain(key)
		array_append(mut header, value)
		return
	}
	mut combined := u64(0)
	if append_value {
		text := string_text(header.items[index]) + ',' + string_text(value)
		if text.len > 65536 { panic('iOS: combined request header exceeds limit') }
		combined = owned_string(text)
		unsafe { text.free() }
	}
	// Both arguments can alias the old header slots; acquire before retirement.
	owned_key := objc_retain(key)
	owned_value := objc_retain(if append_value { combined } else { value })
	objc_store_strong(unsafe { &header.keys[index] }, owned_key)
	objc_store_strong(unsafe { &header.items[index] }, owned_value)
	objc_release(owned_key)
	objc_release(owned_value)
	objc_release(combined)
}

fn request_headers(input u64) u64 {
	if input != 0 && !objc_is_kind(input, ios_runtime.names['NSDictionary']) { panic('iOS: request headers require a dictionary') }
	result := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	if input == 0 { return result }
	source := obj_header(input)
	if source.cf_raw_keys || source.cf_raw_values || source.keys.len > 128 { panic('iOS: request header dictionary exceeds the object profile') }
	for i, key in source.keys {
		value := source.items[i]
		// Foundation skips entries whose key or value is not an NSString.
		if !objc_is_kind(key, ios_runtime.names['NSString']) || !objc_is_kind(value, ios_runtime.names['NSString']) { continue }
		request_header_put(result, key, value, false)
	}
	return result
}

fn request_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	name := request_name(if meta { object } else { read64(object) })
	if request_types(name, meta, selector) == none { return false }
	if meta {
		request := objc_allocate(object)
		request_initialize(request, frame.x[2], if selector == 'requestWithURL:' { u64(0) } else { frame.x[3] }, if selector == 'requestWithURL:' { f64(60) } else { frame_double(frame, 0) })
		frame.x[0] = objc_autorelease(request)
		return true
	}
	if selector in ['init', 'initWithURL:', 'initWithURL:cachePolicy:timeoutInterval:'] {
		request_initialize(object, if selector == 'init' { u64(0) } else { frame.x[2] }, if selector == 'initWithURL:cachePolicy:timeoutInterval:' { frame.x[3] } else { u64(0) }, if selector == 'initWithURL:cachePolicy:timeoutInterval:' { frame_double(frame, 0) } else { f64(60) })
		return true
	}
	mut state := obj_header(object).request
	if state == unsafe { nil } { panic('iOS: request is not initialized') }
	value := frame.x[2]
	match selector {
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:' { frame.x[0] = request_copy(object, selector.starts_with('mutableCopy')) }
		'URL' { frame.x[0] = state.refs[0] }
		'mainDocumentURL' { frame.x[0] = state.refs[1] }
		'HTTPMethod' { frame.x[0] = state.refs[2] }
		'HTTPBody' { frame.x[0] = state.refs[3] }
		'HTTPBodyStream' { frame.x[0] = 0 }
		'allHTTPHeaderFields' { frame.x[0] = objc_autorelease(request_dictionary_copy(state.refs[4])) }
		'cookiePartitionIdentifier' { frame.x[0] = state.refs[5] }
		'valueForHTTPHeaderField:' { index := request_header_index(state.refs[4], request_string(value, true)); frame.x[0] = if index < 0 { u64(0) } else { obj_header(state.refs[4]).items[index] } }
		'setURL:', 'setMainDocumentURL:' { request_url(value); copy := if value == 0 { u64(0) } else { objc_copy_value(value, false) }; objc_store_strong(unsafe { &state.refs[if selector == 'setURL:' { 0 } else { 1 }] }, copy); objc_release(copy) }
		'setHTTPMethod:' {
			mut normalized := u64(0)
			if value != 0 { text := request_string(value, false); for verb in ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'CONNECT', 'PATCH']! { if request_ascii_equal(text, verb) { normalized = owned_string(verb); break } }; if normalized == 0 { normalized = objc_retain(value) } }
			objc_store_strong(unsafe { &state.refs[2] }, normalized); objc_release(normalized)
		}
		'setCookiePartitionIdentifier:' { if value != 0 { request_string(value, false) }; objc_store_strong(unsafe { &state.refs[5] }, value) }
		'setHTTPBody:' { if value != 0 && !objc_is_kind(value, ios_runtime.names['NSData']) { panic('iOS: request body must be data') }; copy := if value == 0 { u64(0) } else { objc_copy_value(value, false) }; objc_store_strong(unsafe { &state.refs[3] }, copy); objc_release(copy) }
		'setHTTPBodyStream:' { if value != 0 { panic('iOS: nonnil request body streams are not implemented') }; objc_store_strong(unsafe { &state.refs[3] }, 0) }
		'setAllHTTPHeaderFields:' { copy := request_headers(value); objc_store_strong(unsafe { &state.refs[4] }, copy); objc_release(copy) }
		'setValue:forHTTPHeaderField:', 'addValue:forHTTPHeaderField:' { if state.refs[4] == 0 { state.refs[4] = objc_allocate(ios_runtime.names['NSMutableDictionary']) }; request_header_put(state.refs[4], frame.x[3], value, selector.starts_with('addValue:')) }
		'timeoutInterval' { frame_float_return(mut frame, 0, state.timeout) }
		'setTimeoutInterval:' { timeout := frame_double(frame, 0); if !math.is_finite(timeout) { panic('iOS: request timeout must be finite') }; state.timeout = timeout }
		'cachePolicy' { frame.x[0] = state.cache_policy }
		'setCachePolicy:' { if value > 5 { panic('iOS: request cache policy is not implemented') }; state.cache_policy = value }
		'networkServiceType' { frame.x[0] = state.network_service }
		'setNetworkServiceType:' { if value !in [u64(0), 1, 2, 3, 4, 6, 8, 9, 11] { panic('iOS: request network service type is not implemented') }; state.network_service = value }
		'attribution' { frame.x[0] = state.attribution }
		'setAttribution:' { if value > 1 { panic('iOS: request attribution is not implemented') }; state.attribution = value }
		'allowsCellularAccess' { frame.x[0] = u64(state.cellular) }
		'setAllowsCellularAccess:' { state.cellular = u8(value) != 0 }
		'allowsExpensiveNetworkAccess' { frame.x[0] = u64(state.expensive) }
		'setAllowsExpensiveNetworkAccess:' { state.expensive = u8(value) != 0 }
		'allowsConstrainedNetworkAccess' { frame.x[0] = u64(state.constrained) }
		'setAllowsConstrainedNetworkAccess:' { state.constrained = u8(value) != 0 }
		'HTTPShouldHandleCookies' { frame.x[0] = u64(state.cookies) }
		'setHTTPShouldHandleCookies:' { state.cookies = u8(value) != 0 }
		'HTTPShouldUsePipelining' { frame.x[0] = u64(state.pipelining) }
		'setHTTPShouldUsePipelining:' { state.pipelining = u8(value) != 0 }
		'assumesHTTP3Capable' { frame.x[0] = u64(state.http3) }
		'setAssumesHTTP3Capable:' { state.http3 = u8(value) != 0 }
		'requiresDNSSECValidation' { frame.x[0] = u64(state.dnssec) }
		'setRequiresDNSSECValidation:' { state.dnssec = u8(value) != 0 }
		else { return false }
	}
	return true
}
