// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import time

struct AbiHTTPCookie {
mut:
	isa     u64
	private u64
}

fn cookie_integer(value i64) u64 {
	object := objc_allocate(ios_runtime.names['NSNumber'])
	obj_header(object).number = value
	return object
}

fn cookie_property(properties u64, key string) u64 {
	header := obj_header(properties)
	for i, candidate in header.keys {
		if string_text(candidate) == key { return header.items[i] }
	}
	return 0
}

fn cookie_put(properties u64, key string, value u64) {
	name := owned_string(key)
	dictionary_put(properties, name, value)
	objc_release(name)
}

fn cookie_put_text(properties u64, key string, text string) {
	value := owned_string(text)
	cookie_put(properties, key, value)
	objc_release(value)
}

fn cookie_text(value u64) string {
	if value == 0 { return '' }
	if !objc_is_kind(value, ios_runtime.names['NSString']) {
		panic('iOS: cookie property requires a string')
	}
	text := string_text(value)
	if text.len > 65536 { panic('iOS: cookie property exceeds limit') }
	for b in text {
		if b == 0 || b == 10 || b == 13 { panic('iOS: cookie property contains a control byte') }
	}
	return text
}

fn cookie_decimal(text string) i64 {
	mut position := 0
	for position < text.len && text[position] in [` `, `\t`] { position++ }
	mut sign := i64(1)
	if position < text.len && text[position] in [`-`, `+`] {
		if text[position] == `-` { sign = -1 }
		position++
	}
	mut number := i64(0)
	for position < text.len && text[position] >= `0` && text[position] <= `9` {
		number = number * 10 + i64(text[position] - `0`)
		if number > 2147483647 { panic('iOS: cookie integer exceeds the measured profile') }
		position++
	}
	return number * sign
}

fn cookie_initialize(object u64, input u64) bool {
	if !obj_header(object).cookie_owned || obj_header(object).native_size < sizeof(AbiHTTPCookie) {
		panic('iOS: invalid cookie storage')
	}
	if input == 0 { return false }
	if !objc_is_kind(input, ios_runtime.names['NSDictionary']) {
		panic('iOS: cookie properties require a dictionary')
	}
	source := obj_header(input)
	if source.cf_raw_keys || source.cf_raw_values || source.keys.len > 128 {
		panic('iOS: unsupported cookie property dictionary')
	}
	for key in source.keys {
		if !objc_is_kind(key, ios_runtime.names['NSString']) {
			panic('iOS: cookie keys require strings')
		}
	}
	name := cookie_property(input, 'Name')
	value := cookie_property(input, 'Value')
	path := cookie_property(input, 'Path')
	domain := cookie_property(input, 'Domain')
	if name == 0 || value == 0 || path == 0 || cookie_text(name).len == 0 { return false }
	properties := objc_allocate(ios_runtime.names['NSDictionary'])
	defer { objc_release(properties) }
	// Each value is copied, including mutable NSString subclasses.
	cookie_put_text(properties, 'Name', cookie_text(name))
	cookie_put_text(properties, 'Value', cookie_text(value))
	cookie_put_text(properties, 'Path', cookie_text(path))
	if domain != 0 {
		text := cookie_text(domain)
		for b in text { if b >= 128 { panic('iOS: Unicode cookie domains are not implemented') } }
		lower := text.to_lower_ascii()
		defer { unsafe { lower.free() } }
		cookie_put_text(properties, 'Domain', lower)
	} else {
		origin := cookie_property(input, 'OriginURL')
		mut url := origin
		mut allocated := false
		if origin != 0 && objc_is_kind(origin, ios_runtime.names['NSString']) {
			url = objc_allocate(ios_runtime.names['NSURL'])
			allocated = true
			if !http_url_initialize(url, origin) {
				objc_release(url)
				return false
			}
		}
		defer { if allocated { objc_release(url) } }
		if url == 0 { return false }
		if !objc_is_kind(url, ios_runtime.names['NSURL']) {
			panic('iOS: cookie origin requires a URL or string')
		}
		if obj_header(url).number != 1 || obj_header(url).fields[3] == 0 { return false }
		cookie_put_text(properties, 'Domain', string_text(obj_header(url).fields[3]))
	}
	created := math.floor(cf_absolute_time())
	created_input := cookie_property(input, 'Created')
	mut creation_time := i64(created)
	if created_input != 0 {
		if !objc_is_kind(created_input, ios_runtime.names['NSNumber']) {
			panic('iOS: cookie creation requires an integer timestamp')
		}
		header := obj_header(created_input)
		if header.is_real || header.number < 0 {
			panic('iOS: cookie creation is outside the integer timestamp profile')
		}
		creation_time = header.number
	}
	if creation_time != 0 {
		creation := cookie_integer(creation_time)
		cookie_put(properties, 'Created', creation)
		objc_release(creation)
	}
	mut expires := u64(0)
	provided := cookie_property(input, 'Expires')
	if ns_date_is_date(provided) {
		if !math.is_finite(cf_date_absolute(provided)) {
			panic('iOS: cookie expiry must be finite')
		}
		expires = objc_retain(provided)
	} else if provided != 0 && !objc_is_kind(provided, ios_runtime.names['NSString']) {
		panic('iOS: cookie expiry requires a date in the CFDate profile')
	}
	max_age := cookie_property(input, 'Max-Age')
	if max_age != 0 {
		objc_release(expires)
		expires = cf_date_create(0, created + f64(cookie_decimal(cookie_text(max_age))))
	}
	defer { objc_release(expires) }
	discard := cookie_property(input, 'Discard')
	if discard != 0 {
		cookie_text(discard)
		objc_release(expires)
		expires = 0
	}
	if expires != 0 { cookie_put(properties, 'Expires', expires) }
	session := expires == 0
	if session { cookie_put_text(properties, 'Discard', 'TRUE') }
	mut version := i64(0)
	version_value := cookie_property(input, 'Version')
	if version_value != 0 {
		version = cookie_decimal(cookie_text(version_value))
		if version < 0 || version > 255 {
			panic('iOS: cookie version exceeds the measured profile')
		}
		cookie_put_text(properties, 'Version', cookie_text(version_value))
	}
	secure := cookie_property(input, 'Secure')
	http_only := cookie_property(input, 'HttpOnly')
	if secure != 0 {
		cookie_text(secure)
		cookie_put_text(properties, 'Secure', 'TRUE')
	}
	if http_only != 0 {
		cookie_text(http_only)
		cookie_put_text(properties, 'HttpOnly', 'TRUE')
	}
	comment := cookie_property(input, 'Comment')
	if comment != 0 { cookie_put_text(properties, 'Comment', cookie_text(comment)) }
	comment_url := cookie_property(input, 'CommentURL')
	mut comment_address := u64(0)
	defer { objc_release(comment_address) }
	if comment_url != 0 {
		if objc_is_kind(comment_url, ios_runtime.names['NSURL']) {
			if obj_header(comment_url).number != 1 {
				panic('iOS: cookie comment requires an HTTP URL')
			}
			comment_address = objc_retain(comment_url)
			cookie_put_text(properties, 'CommentURL', string_text(obj_header(comment_url).fields[1]))
		} else {
			cookie_put_text(properties, 'CommentURL', cookie_text(comment_url))
			comment_address = objc_allocate(ios_runtime.names['NSURL'])
			if !http_url_initialize(comment_address, comment_url) {
				objc_release(comment_address)
				comment_address = 0
			}
		}
	}
	same_site := cookie_property(input, 'SameSite')
	if same_site != 0 {
		lower := cookie_text(same_site).to_lower_ascii()
		defer { unsafe { lower.free() } }
		if lower in ['lax', 'strict'] { cookie_put_text(properties, 'SameSite', lower) }
	}
	ports := objc_allocate(ios_runtime.names['NSArray'])
	defer { objc_release(ports) }
	port := cookie_property(input, 'Port')
	if port != 0 {
		number := cookie_integer(cookie_decimal(cookie_text(port)))
		array_append(mut obj_header(ports), number)
		objc_release(number)
		cookie_put(properties, 'Port', ports)
	}
	obj_header(ports).json_immutable = true
	obj_header(properties).json_immutable = true
	private := objc_allocate(ios_runtime.names['NSHTTPCookieInternal'])
	mut state := obj_header(private)
	store_field(private, 0, properties)
	store_field(private, 1, ports)
	store_field(private, 2, comment_address)
	state.number = version
	state.valid = secure != 0
	state.loaded = http_only != 0
	state.repeat = session
	mut record := unsafe { &AbiHTTPCookie(object) }
	objc_store_strong(unsafe { &record.private }, private)
	objc_release(private)
	return true
}

fn cookie_dispose(object u64, mut header ObjHeader) {
	if !header.cookie_owned { return }
	mut record := unsafe { &AbiHTTPCookie(object) }
	objc_release(record.private)
	record.private = 0
	header.cookie_owned = false
}

fn cookie_state(object u64) &ObjHeader {
	private := unsafe { (&AbiHTTPCookie(object)).private }
	if private == 0 { panic('iOS: cookie is not initialized') }
	return obj_header(private)
}

fn cookie_properties_copy(properties u64) u64 {
	result := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	header := obj_header(properties)
	for i, key in header.keys { dictionary_put(result, key, header.items[i]) }
	return result
}

fn cookie_equal(left u64, right u64) bool {
	if left == right { return true }
	if !objc_is_kind(right, ios_runtime.names['NSHTTPCookie']) { return false }
	a := cookie_state(left)
	b := cookie_state(right)
	for key in ['Name', 'Value', 'Domain', 'Path', 'Version', 'Secure', 'HttpOnly', 'Discard',
		'Expires', 'Comment', 'CommentURL', 'Port', 'SameSite']! {
		if !object_equal(cookie_property(a.fields[0], key), cookie_property(b.fields[0], key)) {
			return false
		}
	}
	return true
}

fn cookie_request(cookies u64) u64 {
	if cookies != 0 && !objc_is_kind(cookies, ios_runtime.names['NSArray']) {
		panic('iOS: cookie request requires an array')
	}
	result := objc_allocate(ios_runtime.names['NSDictionary'])
	if cookies == 0 || obj_header(cookies).items.len == 0 { return result }
	if obj_header(cookies).items.len > 1024 { panic('iOS: cookie request exceeds count limit') }
	mut bytes := []u8{cap: 256}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for i, object in obj_header(cookies).items {
		if !objc_is_kind(object, ios_runtime.names['NSHTTPCookie']) {
			panic('iOS: request array requires cookies')
		}
		properties := cookie_state(object).fields[0]
		name := string_text(cookie_property(properties, 'Name'))
		value := string_text(cookie_property(properties, 'Value'))
		if bytes.len + name.len + value.len + 3 > 1048576 {
			panic('iOS: cookie request header exceeds limit')
		}
		if i > 0 {
			bytes << u8(`;`)
			bytes << u8(` `)
		}
		unsafe { bytes.push_many(name.str, name.len) }
		bytes << u8(`=`)
		unsafe { bytes.push_many(value.str, value.len) }
	}
	cookie_put_text(result, 'Cookie', unsafe { tos(bytes.data, bytes.len) })
	return result
}

// Only the observed RFC1123 GMT form is accepted for response expiry dates.
fn cookie_http_date(text string) u64 {
	if text.len != 29 || text[3] != `,` || text[4] != ` ` || text[7] != ` `
		|| text[11] != ` ` || text[16] != ` ` || text[19] != `:` || text[22] != `:`
		|| !text.ends_with(' GMT') {
		panic('iOS: cookie expiry format is not implemented')
	}
	mut month := 0
	for i, name in ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
		'Dec']! {
		if http_borrow(text, 8, 11) == name {
			month = i + 1
			break
		}
	}
	for pair in [[5, 2]!, [12, 4]!, [17, 2]!, [20, 2]!, [23, 2]!]! {
		start := pair[0]
		length := pair[1]
		for b in http_borrow(text, start, start + length) {
			if b < `0` || b > `9` { panic('iOS: invalid cookie expiry digits') }
		}
	}
	year := int(cookie_decimal(http_borrow(text, 12, 16)))
	day := int(cookie_decimal(http_borrow(text, 5, 7)))
	hour := int(cookie_decimal(http_borrow(text, 17, 19)))
	minute := int(cookie_decimal(http_borrow(text, 20, 22)))
	second := int(cookie_decimal(http_borrow(text, 23, 25)))
	max_days := time.days_in_month(month, year) or { 0 }
	if year < 1970 || month == 0 || day < 1 || day > max_days
		|| hour > 23 || minute > 59 || second > 59 {
		panic('iOS: invalid cookie expiry date')
	}
	date := time.Time{ year: year, month: month, day: day, hour: hour, minute: minute, second: second }
	return cf_date_create(0, f64(date.unix()) - 978307200)
}

fn cookie_response_one(text string, url u64, result u64) {
	parts := text.split(';')
	defer {
		unsafe { parts.free() }
	}
	first := parts[0].trim_space()
	defer { unsafe { first.free() } }
	equal := first.index('=') or { return }
	name := http_borrow(first, 0, equal).trim_space()
	defer { unsafe { name.free() } }
	value := http_borrow(first, equal + 1, first.len).trim_space()
	defer { unsafe { value.free() } }
	if name.len == 0 { return }
	properties := objc_allocate(ios_runtime.names['NSDictionary'])
	defer { objc_release(properties) }
	cookie_put_text(properties, 'Name', name)
	cookie_put_text(properties, 'Value', value)
	host := string_text(obj_header(url).fields[3]).to_lower_ascii()
	defer { unsafe { host.free() } }
	cookie_put_text(properties, 'Domain', host)
	path := string_text(obj_header(url).fields[0])
	last := path.last_index('/') or { 0 }
	cookie_put_text(properties, 'Path', if last == 0 { '/' } else { http_borrow(path, 0, last) })
	for j in 1 .. parts.len {
		part := parts[j]
		attribute := part.trim_space()
		defer { unsafe { attribute.free() } }
		position := attribute.index('=') or { attribute.len }
		key := http_borrow(attribute, 0, position).trim_space()
		defer { unsafe { key.free() } }
		lower := key.to_lower_ascii()
		defer { unsafe { lower.free() } }
		content := if position < attribute.len {
			http_borrow(attribute, position + 1, attribute.len).trim_space()
		} else {
			''
		}
		defer { if position < attribute.len { unsafe { content.free() } } }
		match lower {
			'path' { cookie_put_text(properties, 'Path', content) }
			'domain' {
				if content.len != 0 {
					mut bytes := []u8{cap: content.len + 1}
					bytes.flags |= .noslices
					if content[0] != `.` { bytes << u8(`.`) }
					unsafe { bytes.push_many(content.str, content.len) }
					cookie_put_text(properties, 'Domain', unsafe { tos(bytes.data, bytes.len) })
					unsafe { bytes.free() }
				}
			}
			'secure' { cookie_put_text(properties, 'Secure', 'TRUE') }
			'httponly' { cookie_put_text(properties, 'HttpOnly', 'TRUE') }
			'samesite' { cookie_put_text(properties, 'SameSite', content) }
			'version' { cookie_put_text(properties, 'Version', content) }
			'port' { cookie_put_text(properties, 'Port', content) }
			'max-age' { cookie_put_text(properties, 'Max-Age', content) }
			'expires' {
				date := cookie_http_date(content)
				cookie_put(properties, 'Expires', date)
				objc_release(date)
			}
			'comment' { cookie_put_text(properties, 'Comment', content) }
			'commenturl' { cookie_put_text(properties, 'CommentURL', content) }
			'discard' { cookie_put_text(properties, 'Discard', 'TRUE') }
			else {}
		}
	}
	cookie := objc_allocate(ios_runtime.names['NSHTTPCookie'])
	if cookie_initialize(cookie, properties) { array_append(mut obj_header(result), cookie) }
	objc_release(cookie)
}

fn cookie_response(headers u64, url u64) u64 {
	if headers == 0 { return objc_allocate(ios_runtime.names['NSArray']) }
	if !objc_is_kind(headers, ios_runtime.names['NSDictionary']) || obj_header(headers).keys.len > 128 {
		panic('iOS: cookie response requires a bounded dictionary')
	}
	if url == 0 || !objc_is_kind(url, ios_runtime.names['NSURL']) || obj_header(url).number != 1 {
		panic('iOS: cookie response requires an HTTP URL')
	}
	result := objc_allocate(ios_runtime.names['NSArray'])
	header := obj_header(headers)
	for i, key in header.keys {
		lower := cookie_text(key).to_lower_ascii()
		defer { unsafe { lower.free() } }
		if lower != 'set-cookie' { continue }
		text := cookie_text(header.items[i])
		mut start := 0
		mut quoted := false
		mut escaped := false
		for position, b in text {
			if escaped {
				escaped = false
				continue
			}
			if quoted && b == `\\` {
				escaped = true
				continue
			}
			if b == `"` {
				quoted = !quoted
				continue
			}
			if b == `;` && quoted { panic('iOS: quoted cookie semicolons are not implemented') }
			if b != `,` || quoted { continue }
			mut next := position + 1
			for next < text.len && text[next] !in [`=`, `;`, `,`] { next++ }
			// A comma in an Expires date is followed by no assignment.
			if next < text.len && text[next] == `=` {
				cookie_response_one(http_borrow(text, start, position), url, result)
				start = position + 1
				if obj_header(result).items.len > 1024 {
					panic('iOS: response cookie count exceeds limit')
				}
			}
		}
		if quoted { panic('iOS: unterminated quoted cookie header') }
		cookie_response_one(http_borrow(text, start, text.len), url, result)
		if obj_header(result).items.len > 1024 { panic('iOS: response cookie count exceeds limit') }
	}
	return result
}

fn cookie_builtin_types(name string, meta bool, selector string) ?string {
	if name != 'NSHTTPCookie' { return none }
	if meta {
		return match selector {
			'cookieWithProperties:', 'requestHeaderFieldsWithCookies:' { '@24@0:8@16' }
			'cookiesWithResponseHeaderFields:forURL:' { '@32@0:8@16@24' }
			else { return none }
		}
	}
	return match selector {
		'init', 'name', 'value', 'domain', 'path', 'properties', 'comment', 'commentURL',
		'expiresDate', 'portList', 'sameSitePolicy' {
			'@16@0:8'
		}
		'initWithProperties:' { '@24@0:8@16' }
		'isSecure', 'isHTTPOnly', 'isSessionOnly' { 'B16@0:8' }
		'isEqual:' { 'B24@0:8@16' }
		'version', 'hash' { 'Q16@0:8' }
		else { return none }
	}
}

fn cookie_selector(object u64, selector string) bool {
	if object in ios_runtime.classes {
		return object == ios_runtime.names['NSHTTPCookie'] && cookie_builtin_types('NSHTTPCookie', true, selector) != none
	}
	return objc_is_kind(object, ios_runtime.names['NSHTTPCookie']) && cookie_builtin_types('NSHTTPCookie', false, selector) != none
}

fn cookie_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes {
		if object != ios_runtime.names['NSHTTPCookie'] { return false }
		match selector {
			'cookieWithProperties:' {
				cookie := objc_allocate(object)
				if cookie_initialize(cookie, frame.x[2]) {
					frame.x[0] = objc_autorelease(cookie)
				} else {
					objc_release(cookie)
					frame.x[0] = 0
				}
			}
			'new' { frame.x[0] = 0 }
			'requestHeaderFieldsWithCookies:' {
				frame.x[0] = objc_autorelease(cookie_request(frame.x[2]))
			}
			'cookiesWithResponseHeaderFields:forURL:' {
				frame.x[0] = objc_autorelease(cookie_response(frame.x[2], frame.x[3]))
			}
			else { return false }
		}
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['NSHTTPCookie']) { return false }
	if selector == 'init' || selector == 'initWithProperties:' {
		if selector == 'init' || !cookie_initialize(object, frame.x[2]) {
			objc_release(object)
			frame.x[0] = 0
		}
		return true
	}
	if cookie_builtin_types('NSHTTPCookie', false, selector) == none { return false }
	state := cookie_state(object)
	properties := state.fields[0]
	match selector {
		'name' { frame.x[0] = cookie_property(properties, 'Name') }
		'value' { frame.x[0] = cookie_property(properties, 'Value') }
		'domain' { frame.x[0] = cookie_property(properties, 'Domain') }
		'path' { frame.x[0] = cookie_property(properties, 'Path') }
		'comment' { frame.x[0] = cookie_property(properties, 'Comment') }
		'commentURL' { frame.x[0] = state.fields[2] }
		'expiresDate' { frame.x[0] = cookie_property(properties, 'Expires') }
		'sameSitePolicy' { frame.x[0] = cookie_property(properties, 'SameSite') }
		'properties' { frame.x[0] = objc_autorelease(cookie_properties_copy(properties)) }
		'portList' { frame.x[0] = state.fields[1] }
		'version' { frame.x[0] = u64(state.number) }
		'isSecure' { frame.x[0] = u64(state.valid) }
		'isHTTPOnly' { frame.x[0] = u64(state.loaded) }
		'isSessionOnly' { frame.x[0] = u64(state.repeat) }
		'isEqual:' { frame.x[0] = u64(cookie_equal(object, frame.x[2])) }
		'hash' {
			mut hash := u64(14695981039346656037)
			for key in ['Name', 'Value', 'Domain', 'Path']! {
				for b in string_text(cookie_property(properties, key)) {
					hash = (hash ^ u64(b)) * 1099511628211
				}
			}
			frame.x[0] = hash
		}
		else { return false }
	}
	return true
}
