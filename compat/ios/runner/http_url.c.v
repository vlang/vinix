// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

// URL fields 0/1 retain their existing file path/absoluteString meaning.
// HTTP URLs additionally own scheme, host, query, fragment and port at 2..6.
// No network operation is performed by URL construction.
fn http_borrow(text string, start int, end int) string {
	return unsafe { tos(text.str + start, end - start) }
}

fn http_hex(value u8) int {
	if value >= `0` && value <= `9` { return int(value - `0`) }
	if value >= `a` && value <= `f` { return int(value - `a`) + 10 }
	if value >= `A` && value <= `F` { return int(value - `A`) + 10 }
	return -1
}

fn http_url_initialize(object u64, input u64) bool {
	if input == 0 { return false }
	if !objc_is_kind(input, ios_runtime.names['NSString']) {
		panic('iOS: URL input must be a string')
	}
	// The argument can be an existing component of the URL being initialized.
	objc_retain(input)
	defer { objc_release(input) }
	text := string_text(input)
	if text.len > 65536 { panic('iOS: HTTP URL exceeds limit') }
	for b in text {
		if b <= 32 || b >= 127 || b in [`\\`, `"`, `<`, `>`, `^`, 96, `{`, `}`, `|`] {
			panic('iOS: HTTP URL requires escaped ASCII bytes')
		}
	}
	colon := text.index('://') or { panic('iOS: only absolute HTTP URLs are implemented') }
	scheme := http_borrow(text, 0, colon)
	lower := scheme.to_lower()
	defer { unsafe { lower.free() } }
	if lower !in ['http', 'https'] { panic('iOS: URL scheme is outside the HTTP profile') }
	mut end := colon + 3
	for end < text.len && text[end] !in [`/`, `?`, `#`] { end++ }
	authority := http_borrow(text, colon + 3, end)
	if authority.len == 0 { return false }
	if authority.contains('@') || authority.contains('[') || authority.contains(']') {
		panic('iOS: HTTP URL user information and IPv6 are not implemented')
	}
	mut host := authority
	mut port := u64(0)
	if position := authority.index(':') {
		host = http_borrow(authority, 0, position)
		if host.len == 0 || position + 1 == authority.len { return false }
		for b in http_borrow(authority, position + 1, authority.len) {
			if b < `0` || b > `9` { return false }
			port = port * 10 + u64(b - `0`)
			if port > 65535 { return false }
		}
	}
	for b in host {
		if !((b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`)
			|| (b >= `0` && b <= `9`) || b in [`-`, `.`, `_`]) {
			return false
		}
	}
	mut path_end := end
	for path_end < text.len && text[path_end] !in [`?`, `#`] { path_end++ }
	mut decoded := []u8{cap: path_end - end}
	decoded.flags |= .noslices
	defer { unsafe { decoded.free() } }
	mut i := end
	for i < path_end {
		if text[i] == `%` {
			if i + 2 >= path_end { return false }
			a := http_hex(text[i + 1])
			b := http_hex(text[i + 2])
			if a < 0 || b < 0 { return false }
			decoded << u8(a * 16 + b)
			i += 3
		} else {
			decoded << text[i]
			i++
		}
	}
	path := unsafe { tos(decoded.data, decoded.len) }
	if !utf8.validate_str(path) || path.contains('\x00') { return false }
	mut path_length := path.len
	if path_length > 1 && path[path_length - 1] == `/` { path_length-- }
	mut query_start := -1
	mut query_end := path_end
	if query_end < text.len && text[query_end] == `?` {
		query_start = query_end + 1
		query_end++
		for query_end < text.len && text[query_end] != `#` { query_end++ }
	}
	// Reinitialization must retire the old components too.
	for j in 0 .. 7 { store_field(object, j, 0) }
	for j, value in [http_borrow(path, 0, path_length), text, scheme, host]! {
		component := owned_string(value)
		store_field(object, j, component)
		objc_release(component)
	}
	if query_start >= 0 {
		component := owned_string(http_borrow(text, query_start, query_end))
		store_field(object, 4, component)
		objc_release(component)
	}
	if query_end < text.len && text[query_end] == `#` {
		component := owned_string(http_borrow(text, query_end + 1, text.len))
		store_field(object, 5, component)
		objc_release(component)
	}
	if authority.contains(':') {
		number := cookie_integer(i64(port))
		store_field(object, 6, number)
		objc_release(number)
	}
	obj_header(object).number = 1
	return true
}

fn http_url_builtin_types(name string, meta bool, selector string) ?string {
	if name != 'NSURL' { return none }
	if meta {
		if selector == 'URLWithString:' { return '@24@0:8@16' }
		return none
	}
	return match selector {
		'initWithString:' { '@24@0:8@16' }
		'host', 'path', 'absoluteString', 'scheme', 'query', 'fragment', 'port' { '@16@0:8' }
		'isFileURL' { 'B16@0:8' }
		'setResourceValue:forKey:error:' { 'B40@0:8@16@24^@32' }
		else { return none }
	}
}

fn http_url_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes {
		if object != ios_runtime.names['NSURL'] || selector != 'URLWithString:' { return false }
		url := objc_allocate(object)
		if !http_url_initialize(url, frame.x[2]) {
			objc_release(url)
			frame.x[0] = 0
		} else {
			frame.x[0] = objc_autorelease(url)
		}
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['NSURL']) { return false }
	if selector == 'setResourceValue:forKey:error:' {
		frame.x[0] = u64(ns_url_set_resource(object, frame.x[2], frame.x[3], frame.x[4]))
		return true
	}
	if selector == 'initWithString:' {
		if !http_url_initialize(object, frame.x[2]) {
			objc_release(object)
			frame.x[0] = 0
		}
		return true
	}
	header := obj_header(object)
	match selector {
		'path' { frame.x[0] = header.fields[0] }
		'absoluteString' {
			frame.x[0] = if header.number == 1 {
				header.fields[1]
			} else {
				ui_file_url_string(object)
			}
		}
		'scheme' {
			frame.x[0] = if header.number == 1 { header.fields[2] } else { make_string(c'file') }
		}
		'host' { frame.x[0] = if header.number == 1 { header.fields[3] } else { u64(0) } }
		'query' { frame.x[0] = header.fields[4] }
		'fragment' { frame.x[0] = header.fields[5] }
		'port' { frame.x[0] = header.fields[6] }
		'isFileURL' { frame.x[0] = u64(header.number != 1) }
		else { return false }
	}
	return true
}
