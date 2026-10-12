// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Public response data stays outside Foundation's reserved private ivars.
struct URLResponseState {
mut:
	refs [4]u64 // URL, base MIME type, base encoding, HTTP headers.
	length i64
	status u64
	http bool
}

fn response_name(cls u64) string {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return '' }
		if info.name in ['NSURLResponse', 'NSHTTPURLResponse'] { return info.name }
		current = info.parent
		if current == 0 { return '' }
	}
	panic('iOS: cyclic response superclass chain')
}

fn response_types(name string, meta bool, selector string) ?string {
	if name !in ['NSURLResponse', 'NSHTTPURLResponse'] { return none }
	if meta {
		if name == 'NSHTTPURLResponse' && selector == 'localizedStringForStatusCode:' { return '@24@0:8q16' }
		return none
	}
	match selector {
		'init', 'copy', 'URL', 'MIMEType', 'textEncodingName' { return '@16@0:8' }
		'copyWithZone:' { return '@24@0:8^{_NSZone=}16' }
		'expectedContentLength' { return 'q16@0:8' }
		'initWithURL:MIMEType:expectedContentLength:textEncodingName:' { return '@48@0:8@16@24q32@40' }
		else {}
	}
	if name != 'NSHTTPURLResponse' { return none }
	return match selector {
		'initWithURL:statusCode:HTTPVersion:headerFields:' { '@48@0:8@16q24@32@40' }
		'statusCode' { 'q16@0:8' }
		'allHeaderFields' { '@16@0:8' }
		'valueForHTTPHeaderField:' { '@24@0:8@16' }
		else { return none }
	}
}

fn response_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return response_types(response_name(if meta { object } else { read64(object) }), meta, selector) != none
}

fn response_state(object u64) &URLResponseState {
	mut header := obj_header(object)
	if !header.response_owned || header.native_size < 24 { panic('iOS: invalid response storage') }
	if header.response != unsafe { nil } { panic('iOS: response reinitialization is not implemented') }
	header.response = unsafe { &URLResponseState(C.calloc(1, sizeof(URLResponseState))) }
	if header.response == unsafe { nil } { panic('iOS: cannot allocate response state') }
	header.response.length = -1
	return header.response
}

fn response_init_base(object u64, url u64, mime u64, length i64, encoding u64) {
	if objc_is_kind(object, ios_runtime.names['NSHTTPURLResponse']) { panic('iOS: HTTP response requires its header initializer') }
	request_url(url)
	if mime != 0 { request_string(mime, false) }
	if encoding != 0 { request_string(encoding, false) }
	mut state := response_state(object)
	state.refs[0] = if url == 0 { u64(0) } else { objc_copy_value(url, false) }
	state.refs[1] = if mime == 0 { u64(0) } else { owned_string(string_text(mime)) }
	state.refs[2] = if encoding == 0 { u64(0) } else { owned_string(string_text(encoding)) }
	state.length = length
}

fn response_headers(input u64) u64 {
	if input != 0 && !objc_is_kind(input, ios_runtime.names['NSDictionary']) { panic('iOS: response headers require a dictionary') }
	result := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	mut target := obj_header(result)
	target.response_headers = true // Native CF snapshots report mutable class identity but reject mutation.
	if input == 0 { return result }
	source := obj_header(input)
	if source.cf_raw_keys || source.cf_raw_values || source.keys.len > 128 { panic('iOS: response headers exceed the object profile') }
	for i, key in source.keys {
		name := request_string(key, true)
		value := source.items[i]
		request_string(value, false)
		if request_header_index(result, name) >= 0 { panic('iOS: duplicate case-folded response fields are not implemented') }
		mut canonical := name
		for standard in ['Content-Type', 'Content-Length', 'Content-Disposition', 'Server', 'Date', 'Cache-Control', 'Last-Modified', 'Etag', 'Location', 'Connection', 'Transfer-Encoding', 'Set-Cookie', 'Www-Authenticate', 'Access-Control-Allow-Origin']! {
			if request_ascii_equal(name, standard) { canonical = standard; break }
		}
		owned_key := owned_string(canonical)
		cf_dictionary_insert(mut target, owned_key, value)
		objc_release(owned_key)
	}
	return result
}

fn response_header_copy(input u64) u64 {
	result := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	mut target := obj_header(result)
	target.response_headers = true
	source := obj_header(input)
	for i, key in source.keys { cf_dictionary_insert(mut target, key, source.items[i]) }
	return result
}

fn response_init_http(object u64, url u64, status u64, version u64, headers u64) {
	request_url(url)
	if version != 0 { request_string(version, false) }
	mut state := response_state(object)
	state.http = true
	state.refs[0] = if url == 0 { u64(0) } else { objc_copy_value(url, false) }
	state.refs[3] = response_headers(headers)
	state.status = status & 1023 // Measured Foundation stores ten status bits.
}

fn response_initialize(object u64) {
	if objc_is_kind(object, ios_runtime.names['NSHTTPURLResponse']) { response_init_http(object, 0, 200, 0, 0) }
	else { response_init_base(object, 0, 0, -1, 0) }
	obj_header(object).response.refs[1] = owned_string('application/octet-stream')
}

fn response_dispose(mut header ObjHeader) {
	if header.response == unsafe { nil } { return }
	for value in header.response.refs { objc_release(value) }
	C.free(header.response)
	header.response = unsafe { nil }
}

fn response_trim(text string) string {
	mut start := 0
	mut end := text.len
	for start < end && text[start] in [u8(32), 9] { start++ }
	for end > start && text[end - 1] in [u8(32), 9] { end-- }
	return http_borrow(text, start, end)
}

fn response_lower(text string) u64 {
	if text.len == 0 { return 0 }
	object := owned_string(text)
	header := obj_header(object)
	for i in 0 .. text.len { byte := unsafe { (&u8(header.text))[i] }; if byte >= 65 && byte <= 90 { unsafe { (&u8(header.text))[i] = byte + 32 } } }
	return objc_autorelease(object)
}

fn response_header_value(headers u64, name string) u64 {
	index := request_header_index(headers, name)
	return if index < 0 { u64(0) } else { obj_header(headers).items[index] }
}

fn response_content_type(headers u64, encoding bool) u64 {
	input := response_header_value(headers, 'Content-Type')
	if input == 0 { return 0 }
	text := request_string(input, false)
	mut end := 0
	for end < text.len && text[end] != `;` { end++ }
	if !encoding { return response_lower(response_trim(http_borrow(text, 0, end))) }
	for end < text.len {
		start := end + 1
		end = start
		for end < text.len && text[end] != `;` { end++ }
		part := response_trim(http_borrow(text, start, end))
		if equal := part.index('=') {
			if request_ascii_equal(response_trim(http_borrow(part, 0, equal)), 'charset') { return response_lower(response_trim(http_borrow(part, equal + 1, part.len))) }
		}
	}
	return 0
}

fn response_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	name := response_name(if meta { object } else { read64(object) })
	if response_types(name, meta, selector) == none { return false }
	if meta { frame.x[0] = objc_autorelease(owned_string(response_status_text(i64(frame.x[2])))); return true }
	if selector == 'init' { response_initialize(object); return true }
	if selector == 'initWithURL:MIMEType:expectedContentLength:textEncodingName:' { response_init_base(object, frame.x[2], frame.x[3], i64(frame.x[4]), frame.x[5]); return true }
	if selector == 'initWithURL:statusCode:HTTPVersion:headerFields:' { response_init_http(object, frame.x[2], frame.x[3], frame.x[4], frame.x[5]); return true }
	state := obj_header(object).response
	if state == unsafe { nil } { panic('iOS: response is not initialized') }
	match selector {
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'URL' { frame.x[0] = state.refs[0] }
		'MIMEType', 'textEncodingName' {
			mut result := state.refs[if selector == 'MIMEType' { 1 } else { 2 }]
			if state.http { parsed := response_content_type(state.refs[3], selector == 'textEncodingName'); if parsed != 0 { result = parsed } }
			frame.x[0] = result
		}
		'expectedContentLength' {
			mut length := state.length
			if state.http { value := response_header_value(state.refs[3], 'Content-Length'); if value != 0 { length = response_length(request_string(value, false)) } }
			frame.x[0] = u64(length)
		}
		'statusCode' { frame.x[0] = state.status }
		'allHeaderFields' { frame.x[0] = objc_autorelease(response_header_copy(state.refs[3])) }
		'valueForHTTPHeaderField:' { frame.x[0] = response_header_value(state.refs[3], request_string(frame.x[2], true)) }
		else { return false }
	}
	return true
}

fn response_length(text string) i64 {
	mut position := 0
	for position < text.len && text[position] in [u8(32), 9, 11, 12] { position++ }
	mut negative := false
	if position < text.len && text[position] in [u8(43), 45] { negative = text[position] == 45; position++ }
	mut value := u64(0)
	for position < text.len && text[position] >= 48 && text[position] <= 57 {
		digit := u64(text[position] - 48)
		value = if value > (u64(9223372036854775807) - digit) / 10 { u64(9223372036854775807) } else { value * 10 + digit }
		position++
	}
	return if negative && value != 0 { i64(-1) } else { i64(value) }
}
