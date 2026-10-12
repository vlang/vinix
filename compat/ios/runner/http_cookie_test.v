// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}

#include <dlfcn.h>

fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int

@[c_extern]
fn C.CFDateCreate(voidptr, f64) voidptr

@[c_extern]
fn C.CFDateGetAbsoluteTime(voidptr) f64

@[c_extern]
fn C.CFAbsoluteTimeGetCurrent() f64

type CookieSend = fn (u64, u64, u64, u64, u64) u64
type CookiePush = fn () u64
type CookiePop = fn (u64)

struct CookieApi {
	native     bool
	send       u64
	push       u64
	pop        u64
	cookie     u64
	url        u64
	string     u64
	dictionary u64
	array      u64
}

fn (api CookieApi) selector(name &char) u64 {
	$if macos {
		if api.native { return u64(C.sel_registerName(name)) }
	}
	return u64(name)
}

fn (api CookieApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { CookieSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}

fn (api CookieApi) pool() u64 {
	$if macos {
		if api.native { return unsafe { CookiePush(voidptr(api.push))() } }
	}
	return objc_pool_push()
}

fn (api CookieApi) drain(pool u64) {
	$if macos {
		if api.native {
			unsafe { CookiePop(voidptr(api.pop))(pool) }
			return
		}
	}
	objc_pool_pop(pool)
}

fn (api CookieApi) string_value(value string) u64 {
	return api.message(api.string, c'stringWithUTF8String:', u64(value.str), 0, 0)
}

fn (api CookieApi) text(object u64) string {
	assert object != 0
	return ctext(api.message(object, c'UTF8String', 0, 0, 0))
}

fn (api CookieApi) dict(pairs []string) u64 {
	assert pairs.len % 2 == 0
	result := api.message(api.dictionary, c'dictionary', 0, 0, 0)
	for i := 0; i < pairs.len; i += 2 {
		api.message(result, c'setObject:forKey:', api.string_value(pairs[i + 1]), api.string_value(pairs[i]), 0)
	}
	return result
}

fn (api CookieApi) key(dictionary u64, key string) u64 {
	return api.message(dictionary, c'objectForKey:', api.string_value(key), 0, 0)
}

fn (api CookieApi) create(pairs []string) u64 {
	return api.message(api.cookie, c'cookieWithProperties:', api.dict(pairs), 0, 0)
}

fn (api CookieApi) date(absolute f64) u64 {
	$if macos {
		if api.native { return u64(C.CFDateCreate(unsafe { nil }, absolute)) }
	}
	return cf_date_create(0, absolute)
}

fn (api CookieApi) absolute(date u64) f64 {
	$if macos {
		if api.native { return C.CFDateGetAbsoluteTime(unsafe { voidptr(date) }) }
	}
	return cf_date_absolute(date)
}

fn (api CookieApi) now() f64 {
	$if macos {
		if api.native { return C.CFAbsoluteTimeGetCurrent() }
	}
	return cf_absolute_time()
}

fn cookie_cases(api CookieApi) {
	pool := api.pool()
	base := ['Name', 'sid', 'Value', 'abc', 'Domain', 'Example.COM', 'Path', '/']
	defer {
		unsafe { base.free() }
		api.drain(pool)
	}
	object := api.create(base)
	assert object != 0
	for i, selector in [c'name', c'value', c'domain', c'path']! {
		assert api.text(api.message(object, selector, 0, 0, 0)) == ['sid', 'abc', 'example.com',
			'/']![i]
	}
	assert api.message(object, c'version', 0, 0, 0) == 0
	assert api.message(object, c'isSecure', 0, 0, 0) == 0
	assert api.message(object, c'isHTTPOnly', 0, 0, 0) == 0
	assert api.message(object, c'isSessionOnly', 0, 0, 0) == 1
	assert api.message(object, c'expiresDate', 0, 0, 0) == 0
	assert api.message(api.message(object, c'portList', 0, 0, 0), c'count', 0, 0, 0) == 0
	properties := api.message(object, c'properties', 0, 0, 0)
	assert api.text(api.key(properties, 'Discard')) == 'TRUE'
	assert api.key(properties, 'Created') != 0
	api.message(properties, c'setObject:forKey:', api.string_value('changed'), api.string_value('Value'), 0)
	assert api.text(api.message(object, c'value', 0, 0, 0)) == 'abc'
	duplicate := api.create(base)
	assert api.message(object, c'isEqual:', duplicate, 0, 0) == 1
	assert api.message(object, c'hash', 0, 0, 0) == api.message(duplicate, c'hash', 0, 0, 0)
	for created in [u64(0), 42, 813000000]! {
		input := api.dict(base)
		mut number_class := u64(0)
		if !api.native { number_class = ios_runtime.names['NSNumber'] }
		$if macos {
			if api.native { number_class = u64(C.objc_getClass(c'NSNumber')) }
		}
		number := api.message(number_class, c'numberWithInteger:', created, 0, 0)
		api.message(input, c'setObject:forKey:', number, api.string_value('Created'), 0)
		cookie := api.message(api.cookie, c'cookieWithProperties:', input, 0, 0)
		stamp := api.key(api.message(cookie, c'properties', 0, 0, 0), 'Created')
		if created == 0 {
			assert stamp == 0
		} else {
			assert api.message(stamp, c'integerValue', 0, 0, 0) == created
		}
		assert api.message(object, c'isEqual:', cookie, 0, 0) == 1
		api.message(input, c'setObject:forKey:', api.string_value('60'), api.string_value('Max-Age'), 0)
		before := api.now()
		aged := api.message(api.cookie, c'cookieWithProperties:', input, 0, 0)
		expiry := api.absolute(api.message(aged, c'expiresDate', 0, 0, 0))
		assert expiry >= before + 59 && expiry <= api.now() + 60
	}
	assert api.message(api.message(api.cookie, c'alloc', 0, 0, 0), c'init', 0, 0, 0) == 0
	assert api.message(api.cookie, c'cookieWithProperties:', 0, 0, 0) == 0
	for pairs in [['Value', 'x', 'Domain', 'example.com', 'Path', '/'],
		['Name', '', 'Value', 'x', 'Domain', 'example.com', 'Path', '/'],
		['Name', 'x', 'Value', 'v', 'Domain', 'example.com'], ['Name', 'x', 'Value', 'v', 'Path',
			'/']] {
		assert api.create(pairs) == 0
	}
	empty := api.create(['Name', 'x', 'Value', '', 'Domain', '', 'Path', 'relative'])
	assert empty != 0 && api.text(api.message(empty, c'value', 0, 0, 0)) == ''
	assert api.text(api.message(empty, c'domain', 0, 0, 0)) == ''
	for extra in [['Secure', 'TRUE'], ['Secure', 'FALSE'], ['Secure', ''], ['HttpOnly', 'TRUE']] {
		mut pairs := base.clone()
		pairs << extra
		cookie := api.create(pairs)
		unsafe { pairs.free() }
		assert api.message(cookie, if extra[0] == 'Secure' { c'isSecure' } else { c'isHTTPOnly' }, 0, 0, 0) == 1
		assert api.message(object, c'isEqual:', cookie, 0, 0) == 0
	}
	for same_site in ['Lax', 'Strict', 'None', 'wrong', '😃']! {
		properties_input := api.dict(base)
		api.message(properties_input, c'setObject:forKey:', api.string_value(same_site), api.string_value('SameSite'), 0)
		cookie := api.message(api.cookie, c'cookieWithProperties:', properties_input, 0, 0)
		policy := api.message(cookie, c'sameSitePolicy', 0, 0, 0)
		if same_site in ['Lax', 'Strict'] {
			assert api.text(policy) == if same_site == 'Lax' { 'lax' } else { 'strict' }
		} else {
			assert policy == 0
		}
	}
	for discard in ['', 'TRUE', 'FALSE']! {
		input := api.dict(base)
		date := api.date(1234567)
		api.message(input, c'setObject:forKey:', date, api.string_value('Expires'), 0)
		api.message(date, c'release', 0, 0, 0)
		if discard.len != 0 {
			api.message(input, c'setObject:forKey:', api.string_value(discard), api.string_value('Discard'), 0)
		}
		cookie := api.message(api.cookie, c'cookieWithProperties:', input, 0, 0)
		if discard == '' {
			assert api.absolute(api.message(cookie, c'expiresDate', 0, 0, 0)) == 1234567
		} else {
			assert api.message(cookie, c'expiresDate', 0, 0, 0) == 0
		}
		assert api.message(cookie, c'isSessionOnly', 0, 0, 0) == u64(discard != '')
	}
	versioned := api.create(['Name', 'vers', 'Value', '"x y"', 'Domain', '.EXAMPLE.COM', 'Path',
		'/', 'Version', '1', 'Port', '80,443', 'Comment', 'hello', 'CommentURL',
		'https://example.com/info', 'Unknown', 'ignored'])
	assert api.message(versioned, c'version', 0, 0, 0) == 1
	assert api.text(api.message(versioned, c'domain', 0, 0, 0)) == '.example.com'
	assert api.text(api.message(versioned, c'comment', 0, 0, 0)) == 'hello'
	assert api.text(api.message(api.message(versioned, c'commentURL', 0, 0, 0), c'absoluteString', 0, 0, 0)) == 'https://example.com/info'
	ports := api.message(versioned, c'portList', 0, 0, 0)
	assert api.message(ports, c'count', 0, 0, 0) == 1
	assert api.message(api.message(ports, c'objectAtIndex:', 0, 0, 0), c'integerValue', 0, 0, 0) == 80
	assert api.key(api.message(versioned, c'properties', 0, 0, 0), 'Unknown') == 0
	items := api.message(api.array, c'array', 0, 0, 0)
	assert api.message(api.message(api.cookie, c'requestHeaderFieldsWithCookies:', items, 0, 0), c'count', 0, 0, 0) == 0
	for cookie in [object, duplicate, versioned]! {
		api.message(items, c'addObject:', cookie, 0, 0)
	}
	request := api.message(api.cookie, c'requestHeaderFieldsWithCookies:', items, 0, 0)
	assert api.text(api.key(request, 'Cookie')) == 'sid=abc; sid=abc; vers="x y"'
	url := api.message(api.url, c'URLWithString:', api.string_value('https://Example.COM/a/b?x=y#z'), 0, 0)
	assert url != 0
	for i, selector in [c'absoluteString', c'scheme', c'host', c'path', c'query', c'fragment']! {
		assert api.text(api.message(url, selector, 0, 0, 0)) == [
			'https://Example.COM/a/b?x=y#z',
			'https',
			'Example.COM',
			'/a/b',
			'x=y',
			'z',
		]![i]
	}
	assert api.message(url, c'isFileURL', 0, 0, 0) == 0
	assert api.message(url, c'port', 0, 0, 0) == 0
	decoded := api.message(api.message(api.url, c'alloc', 0, 0, 0), c'initWithString:', api.string_value('HTTP://EXAMPLE.COM:443/a%20b/'), 0, 0)
	assert api.text(api.message(decoded, c'path', 0, 0, 0)) == '/a b'
	assert api.text(api.message(decoded, c'scheme', 0, 0, 0)) == 'HTTP'
	assert api.message(api.message(decoded, c'port', 0, 0, 0), c'integerValue', 0, 0, 0) == 443
	api.message(decoded, c'release', 0, 0, 0)
	file := api.message(api.url, c'fileURLWithPath:', api.string_value('/tmp/cookie test'), 0, 0)
	assert api.message(file, c'isFileURL', 0, 0, 0) == 1
	assert api.text(api.message(file, c'absoluteString', 0, 0, 0)) == 'file:///tmp/cookie%20test'
	origin_properties := api.dict(['Name', 'origin', 'Value', 'v', 'Path', '/'])
	api.message(origin_properties, c'setObject:forKey:', url, api.string_value('OriginURL'), 0)
	assert api.text(api.message(api.message(api.cookie, c'cookieWithProperties:', origin_properties, 0, 0), c'domain', 0, 0, 0)) == 'Example.COM'
	for raw in ['sid=v', 'sid=v; Path=/a; Domain=.EXAMPLE.COM; Secure; HttpOnly; SameSite=Lax',
		'sid=v; Expires=Wed, 09 Jun 2027 10:18:14 GMT', 'a=1, b=2',
		'sid="v x"; Version=1; Port="80,443"', 'bad', '=v', 'sid=; path=/', 'sid=v; Domain=evil.test',
		'sid=v; Path=abc', 'sid=v; Max-Age=60']! {
		response := api.message(api.cookie, c'cookiesWithResponseHeaderFields:forURL:', api.dict([
			'Set-Cookie',
			raw,
		]), url, 0)
		assert api.message(response, c'count', 0, 0, 0) == if raw in ['bad', '=v'] {
			u64(0)
		} else if raw == 'a=1, b=2' {
			u64(2)
		} else {
			u64(1)
		}
		if raw in ['bad', '=v'] { continue }
		cookie := api.message(response, c'objectAtIndex:', 0, 0, 0)
		if raw == 'sid=v' {
			assert api.text(api.message(cookie, c'path', 0, 0, 0)) == '/a'
		}
		if raw.contains('Secure; HttpOnly') {
			assert api.message(cookie, c'isSecure', 0, 0, 0) == 1 && api.message(cookie, c'isHTTPOnly', 0, 0, 0) == 1
			assert api.text(api.message(cookie, c'sameSitePolicy', 0, 0, 0)) == 'lax'
		}
		if raw.contains('Domain=evil') {
			assert api.text(api.message(cookie, c'domain', 0, 0, 0)) == '.evil.test'
		}
		if raw.contains('Path=abc') {
			assert api.text(api.message(cookie, c'path', 0, 0, 0)) == 'abc'
		}
		if raw.contains('Expires=') {
			assert api.absolute(api.message(cookie, c'expiresDate', 0, 0, 0)) == 834229094
		}
		if raw.contains('Max-Age=') {
			created := api.message(api.key(api.message(cookie, c'properties', 0, 0, 0), 'Created'), c'integerValue', 0, 0, 0)
			assert math.abs(api.absolute(api.message(cookie, c'expiresDate', 0, 0, 0)) - f64(created) - 60) < 1
			assert api.message(cookie, c'isSessionOnly', 0, 0, 0) == 0
		}
	}
}

fn test_cookie_native_foundation() {
	$if macos {
		library := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		assert library != unsafe { nil }
		api := CookieApi{ native: true, send: u64(C.dlsym(library, c'objc_msgSend')), push: u64(C.dlsym(library, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(library, c'objc_autoreleasePoolPop')), cookie: u64(C.objc_getClass(c'NSHTTPCookie')), url: u64(C.objc_getClass(c'NSURL')), string: u64(C.objc_getClass(c'NSString')), dictionary: u64(C.objc_getClass(c'NSMutableDictionary')), array: u64(C.objc_getClass(c'NSMutableArray')) }
		assert C.class_getInstanceSize(voidptr(api.cookie)) == 16
		assert C.class_getInstanceSize(C.objc_getClass(c'NSHTTPCookieInternal')) == 8
		cookie_cases(api)
		assert C.dlclose(library) == 0
		println('IOS-COOKIE-NATIVE: Foundation construction, normalization, snapshot properties, equality, headers, dates and HTTP/file URL fixtures passed')
	}
}

fn test_cookie_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start()
		cls := ios_runtime.names['NSHTTPCookie']
		api := CookieApi{ send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cookie: cls, url: ios_runtime.names['NSURL'], string: ios_runtime.names['NSString'], dictionary: ios_runtime.names['NSMutableDictionary'], array: ios_runtime.names['NSMutableArray'] }
		assert objc_class_size(cls) == 16 && objc_class_size(ios_runtime.names['NSHTTPCookieInternal']) == 8
		assert objc_ivar_offset(objc_find_ivar(cls, c'_cookiePrivate')) == 8
		assert ctext(u64(objc_method_types(objc_instance_method(cls, u64(c'initWithProperties:'))))) == '@24@0:8@16'
		cookie_cases(api)
		assert ios_runtime.live == 0
		// The initializer argument may be owned only by this same URL.
		url := objc_allocate(api.url)
		initial := owned_string('https://example.com/alias')
		assert api.message(url, c'initWithString:', initial, 0, 0) == url
		objc_release(initial)
		for _ in 0 .. 100 {
			argument := api.message(url, c'absoluteString', 0, 0, 0)
			assert api.message(url, c'initWithString:', argument, 0, 0) == url
			assert api.text(api.message(url, c'path', 0, 0, 0)) == '/alias'
		}
		objc_release(url)
		assert ios_runtime.live == 0
		for _ in 0 .. 100 {
			pool := api.pool()
			input := api.dict(['Name', 'copy', 'Value', 'abc', 'Domain', 'EXAMPLE.COM', 'Path',
				'/'])
			object := api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithProperties:', input, 0, 0)
			original := api.key(input, 'Value')
			unsafe { obj_header(original).text[0] = char(`z`) }
			assert api.text(api.message(object, c'value', 0, 0, 0)) == 'abc'
			api.drain(pool)
			assert read64(object + 8) != 0
			objc_set_class(object, ios_runtime.names['NSObject'])
			objc_release(object)
			assert ios_runtime.live == 0
		}
		pool := api.pool()
		input := api.dict(['Name', 'storage', 'Value', 'v', 'Domain', 'example.com', 'Path', '/'])
		storage := u64(C.calloc(1, 16))
		assert objc_construct_instance(cls, storage) == storage && read64(storage + 8) == 0
		assert api.message(storage, c'initWithProperties:', input, 0, 0) == storage
		assert objc_destruct_instance(storage) == storage && read64(storage + 8) == 0
		C.free(unsafe { voidptr(storage) })
		api.drain(pool)
		assert ios_runtime.live == 0
		assert !objc_responds(cls, c'cookiesWithResponseHeaderFields:forURL:extra:')
		objc_stop()
	}
	println('IOS-COOKIE: shared trampoline fixtures, 16/8-byte metadata, copied strings, headers, dates and balanced repeated release/isa change/caller storage passed')
}

fn test_cookie_profile_rejections() {
	objc_start()
	api := CookieApi{ send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cookie: ios_runtime.names['NSHTTPCookie'], url: ios_runtime.names['NSURL'], string: ios_runtime.names['NSString'], dictionary: ios_runtime.names['NSMutableDictionary'] }
	pool := api.pool()
	wrong := objc_allocate(ios_runtime.names['NSNumber'])
	for operation in 0 .. 4 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0])
			assert C.dup2(descriptors[1], 2) == 2
			C.close(descriptors[1])
			match operation {
				0 { api.message(api.cookie, c'cookieWithProperties:', wrong, 0, 0) }
				1 {
					api.message(api.url, c'URLWithString:', api.string_value('https://user:pass@example.com/'), 0, 0)
				}
				2 {
					api.create(['Name', 'sid', 'Value', 'bad\r\nvalue', 'Domain', 'example.com',
						'Path', '/'])
				}
				else {
					url := api.message(api.url, c'URLWithString:', api.string_value('https://example.com/'), 0, 0)
					api.message(api.cookie, c'cookiesWithResponseHeaderFields:forURL:', api.dict([
						'Set-Cookie',
						'sid=v; Expires=tomorrow',
					]), url, 0)
				}
			}
			C._exit(0)
		}
		C.close(descriptors[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(descriptors[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains(['cookie properties require a dictionary',
			'HTTP URL user information and IPv6 are not implemented',
			'cookie property contains a control byte', 'cookie expiry format is not implemented']![operation])
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(wrong)
	api.drain(pool)
	assert ios_runtime.live == 0
	objc_stop()
	println('IOS-COOKIE-REJECT: wrong property types, unsupported URL authority, header control bytes and unmeasured expiry formats reject explicitly')
}
