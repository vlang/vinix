// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Private HTTP backend for host-only, process-lifetime session cookies. No
// Objective-C objects escape to network workers. Public/custom cookie stores,
// domain cookies and persistence need separate implementations.
struct URLSessionCookie {
	host string
	path string
	name string
	value string
	secure bool
	remove bool
}

enum URLSessionCookieIssue { none ignored syntax limit persistence domain attribute }
struct URLSessionCookieParse {
	issue URLSessionCookieIssue
	cookie URLSessionCookie
}

fn session_cookie_trim(text string) string {
	mut start := 0; mut end := text.len
	for start < end && text[start] in [u8(` `), `\t`] { start++ }
	for end > start && text[end - 1] in [u8(` `), `\t`] { end-- }
	return http_borrow(text, start, end)
}

fn session_cookie_path(url DataHTTPURL) string {
	mut end := 0
	for end < url.target.len && url.target[end] != `?` { end++ }
	if end == 0 || url.target[0] != `/` { return '/' }
	return http_borrow(url.target, 0, end)
}

fn session_cookie_default_path(url DataHTTPURL) string {
	path := session_cookie_path(url)
	mut slash := 0
	for i, byte in path { if byte == `/` { slash = i } }
	return if slash == 0 { '/' } else { http_borrow(path, 0, slash) }
}

// All returned spans are borrowed until the caller commits a cloned record.
// RFC 6265 sections 5.1.4/5.2/5.4 define path, replacement and wire ordering.
fn session_cookie_parse(text string, url DataHTTPURL) URLSessionCookieParse {
	if text.len > 4096 { return URLSessionCookieParse{issue: .limit} }
	mut end := 0
	for end < text.len && text[end] != `;` { end++ }
	pair := session_cookie_trim(http_borrow(text, 0, end))
	equal := pair.index('=') or { return URLSessionCookieParse{issue: .ignored} }
	name := session_cookie_trim(http_borrow(pair, 0, equal))
	value := session_cookie_trim(http_borrow(pair, equal + 1, pair.len))
	if name.len == 0 { return URLSessionCookieParse{issue: .ignored} }
	if !http_transport_token(name) || name.starts_with('__Host-') || name.starts_with('__Secure-') {
		return URLSessionCookieParse{issue: .syntax}
	}
	// Strict unquoted cookie-octets; never reinterpret combined header fields,
	// controls, UTF-8, quotes or delimiters as executable wire headers.
	for byte in value {
		if byte < 33 || byte > 126 || byte in [u8(`"`), `,`, `;`, `\\`] { return URLSessionCookieParse{issue: .syntax} }
	}
	mut path := session_cookie_default_path(url)
	mut secure := false
	mut remove := false
	for end < text.len {
		start := end + 1; end = start
		for end < text.len && text[end] != `;` { end++ }
		part := session_cookie_trim(http_borrow(text, start, end))
		if part.len == 0 { continue }
		position := part.index('=') or { part.len }
		attribute := session_cookie_trim(http_borrow(part, 0, position))
		input := if position == part.len { '' } else { session_cookie_trim(http_borrow(part, position + 1, part.len)) }
		if data_http_equal(attribute, 'Path') {
			path = session_cookie_default_path(url)
			if input.len != 0 && input[0] == `/` {
				for byte in input { if byte < 32 || byte >= 127 { return URLSessionCookieParse{issue: .syntax} } }
				path = input
			}
		} else if data_http_equal(attribute, 'Secure') || data_http_equal(attribute, 'HttpOnly') {
			if position != part.len { return URLSessionCookieParse{issue: .attribute} }
			if data_http_equal(attribute, 'Secure') { secure = true }
		} else if data_http_equal(attribute, 'Max-Age') {
			mut start_digit := 0
			if input.len != 0 && input[0] == `-` { start_digit = 1 }
			if start_digit == input.len { return URLSessionCookieParse{issue: .syntax} }
			mut positive := false
			for byte in http_borrow(input, start_digit, input.len) {
				if byte < `0` || byte > `9` { return URLSessionCookieParse{issue: .syntax} }
				if byte != `0` { positive = true }
			}
			if start_digit == 0 && positive { return URLSessionCookieParse{issue: .persistence} }
			remove = true
		} else if data_http_equal(attribute, 'Expires') { return URLSessionCookieParse{issue: .persistence} }
		else if data_http_equal(attribute, 'Domain') { return URLSessionCookieParse{issue: .domain} }
		else { return URLSessionCookieParse{issue: .attribute} }
	}
	return URLSessionCookieParse{cookie: URLSessionCookie{host: url.host, path: path, name: name, value: value, secure: secure, remove: remove}}
}

fn (cookie URLSessionCookie) dispose() {
	unsafe { cookie.host.free(); cookie.path.free(); cookie.name.free(); cookie.value.free() }
}

fn session_cookie_store(cookie URLSessionCookie) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut index := -1
	for i, old in ios_runtime.url_session_cookies {
		if data_http_equal(old.host, cookie.host) && old.path == cookie.path && old.name == cookie.name { index = i; break }
	}
	if cookie.remove {
		if index >= 0 { ios_runtime.url_session_cookies[index].dispose(); ios_runtime.url_session_cookies.delete(index) }
		return
	}
	if index < 0 && ios_runtime.url_session_cookies.len >= 1024 { panic('iOS: URL session cookie store limit exceeded') }
	owned := URLSessionCookie{host: cookie.host.clone(), path: cookie.path.clone(), name: cookie.name.clone(), value: cookie.value.clone(), secure: cookie.secure}
	if index < 0 { ios_runtime.url_session_cookies << owned }
	else { old := ios_runtime.url_session_cookies[index]; ios_runtime.url_session_cookies[index] = owned; old.dispose() }
}

fn session_cookie_matches(cookie URLSessionCookie, url DataHTTPURL) bool {
	if !data_http_equal(cookie.host, url.host) || (cookie.secure && !url.tls) { return false }
	path := session_cookie_path(url)
	return path == cookie.path || (path.starts_with(cookie.path) && (cookie.path.ends_with('/') || path[cookie.path.len] == `/`))
}

fn session_cookie_header(url DataHTTPURL) string {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut selected := []int{cap: ios_runtime.url_session_cookies.len}; selected.flags |= .noslices
	defer { unsafe { selected.free() } }
	mut length := 0
	for i, cookie in ios_runtime.url_session_cookies {
		if !session_cookie_matches(cookie, url) { continue }
		length += cookie.name.len + cookie.value.len + 3
		if length > data_http_headers - 1024 { panic('iOS: URL session cookie header limit exceeded') }
		selected << i
		mut j := selected.len - 1
		for j > 0 && ios_runtime.url_session_cookies[selected[j - 1]].path.len < cookie.path.len {
			selected[j] = selected[j - 1]; j--
		}
		selected[j] = i
	}
	mut bytes := []u8{cap: length}; bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for i, index in selected {
		cookie := ios_runtime.url_session_cookies[index]
		if i != 0 { bytes << `;`; bytes << ` ` }
		for byte in cookie.name { bytes << byte }; bytes << `=`
		for byte in cookie.value { bytes << byte }
	}
	return bytes.bytestr()
}

fn session_cookie_prepare(mut snapshot URLSessionRequestSnapshot) {
	if !snapshot.request.cookies { return }
	for field in snapshot.fields { if data_http_equal(field.name, 'Cookie') { return } }
	url := data_http_url(snapshot.url) or { panic('iOS: invalid cookie request URL') }
	header := session_cookie_header(url)
	if header.len == 0 { unsafe { header.free() }; return }
	if snapshot.fields.len >= 128 { panic('iOS: URL session cookie request field limit exceeded') }
	snapshot.fields << HTTPTransportField{name: 'Cookie'.clone(), value: header}
}

fn session_cookie_receive(snapshot &URLSessionRequestSnapshot, head HTTPTransportResponseHead) {
	if !snapshot.request.cookies { return }
	url := data_http_url(snapshot.url) or { panic('iOS: invalid cookie response URL') }
	for field in head.fields {
		if !data_http_equal(field.name, 'Set-Cookie') { continue }
		parsed := session_cookie_parse(field.value, url)
		if parsed.issue == .ignored { continue }
		if parsed.issue != .none { panic('iOS: URL session response cookie profile is not implemented: ' + parsed.issue.str()) }
		session_cookie_store(parsed.cookie)
	}
}

fn session_cookies_stop() {
	// All transport workers and callback users have joined before retirement.
	for cookie in ios_runtime.url_session_cookies { cookie.dispose() }
	unsafe { ios_runtime.url_session_cookies.free() }
	ios_runtime.url_session_cookies = []URLSessionCookie{}
}
