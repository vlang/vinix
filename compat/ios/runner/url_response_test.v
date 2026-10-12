// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type ResponseSend = fn (u64, u64, u64, u64, u64, u64) u64

struct ResponseApi {
	native bool
	send u64
	base u64
	http u64
	url u64
	strings u64
	dictionary u64
}
fn (api ResponseApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ResponseApi) message(object u64, name &char, a u64, b u64) u64 { return unsafe { ResponseSend(voidptr(api.send))(object, api.selector(name), a, b, 0, 0) } }
fn (api ResponseApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0) }
fn (api ResponseApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0)) }
fn (api ResponseApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api ResponseApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api ResponseApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}
fn (api ResponseApi) initialized(object u64, url u64, code i64, headers u64) u64 { return unsafe { ResponseSend(voidptr(api.send))(object, api.selector(c'initWithURL:statusCode:HTTPVersion:headerFields:'), url, u64(code), 0, headers) } }
fn (api ResponseApi) response(url u64, code i64, headers u64) u64 { return api.initialized(api.message(api.http, c'alloc', 0, 0), url, code, headers) }
fn (api ResponseApi) base_response(url u64, mime u64, length i64, encoding u64) u64 { return unsafe { ResponseSend(voidptr(api.send))(api.message(api.base, c'alloc', 0, 0), api.selector(c'initWithURL:MIMEType:expectedContentLength:textEncodingName:'), url, mime, u64(length), encoding) } }
fn (api ResponseApi) put(headers u64, name &char, value &char) { api.message(headers, c'setObject:forKey:', api.string(value), api.string(name)) }
fn (api ResponseApi) mutable_string(value &char) u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(value), 0) } }
	return objc_autorelease(owned_string(ctext(u64(value))))
}
fn (api ResponseApi) change_string(object u64, value &char) {
	$if macos { if api.native { api.message(object, c'setString:', api.string(value), 0); return } }
	text := ctext(u64(value)); mut header := obj_header(object)
	C.free(header.text); header.text = unsafe { &char(C.malloc(usize(text.len + 1))) }; assert header.text != unsafe { nil }
	unsafe { C.memcpy(header.text, text.str, usize(text.len)); header.text[text.len] = 0 }; header.text_length = text.len
}

fn response_cases(api ResponseApi) {
	pool := api.pool()
	url := api.message(api.url, c'URLWithString:', api.string(c'https://example.test/path'), 0)
	for cls in [api.base, api.http]! {
		empty := api.message(cls, c'new', 0, 0)
		assert empty != 0 && api.message(empty, c'URL', 0, 0) == 0 && i64(api.message(empty, c'expectedContentLength', 0, 0)) == -1
		assert api.text(api.message(empty, c'MIMEType', 0, 0)) == 'application/octet-stream' && api.message(empty, c'textEncodingName', 0, 0) == 0
		if cls == api.http { assert api.message(empty, c'statusCode', 0, 0) == 200 && api.message(api.message(empty, c'allHeaderFields', 0, 0), c'count', 0, 0) == 0 }
		copy := api.message(empty, c'copyWithZone:', 0, 0); assert copy == empty; api.release(copy); api.release(empty)
	}
	mime := api.mutable_string(c'TEXT/PLAIN'); encoding := api.mutable_string(c'UTF-8')
	base := api.base_response(url, mime, -10, encoding)
	api.change_string(mime, c'application/json'); api.change_string(encoding, c'latin1')
	assert api.text(api.message(base, c'MIMEType', 0, 0)) == 'TEXT/PLAIN' && api.text(api.message(base, c'textEncodingName', 0, 0)) == 'UTF-8'
	assert i64(api.message(base, c'expectedContentLength', 0, 0)) == -10 && api.message(base, c'URL', 0, 0) == url
	copy := api.message(base, c'copy', 0, 0); assert copy == base; api.release(copy); api.release(base)
	headers := api.message(api.dictionary, c'dictionary', 0, 0)
	api.put(headers, c'content-type', c'Text/Plain; charset="UTF-8"'); api.put(headers, c'content-length', c'123'); api.put(headers, c'x-mixed-case', c'one')
	r := api.response(url, 201, headers)
	assert api.message(r, c'statusCode', 0, 0) == 201 && api.message(r, c'expectedContentLength', 0, 0) == 123
	assert api.text(api.message(r, c'MIMEType', 0, 0)) == 'text/plain' && api.text(api.message(r, c'textEncodingName', 0, 0)) == '"utf-8"'
	snapshot := api.message(r, c'allHeaderFields', 0, 0)
	assert snapshot != api.message(r, c'allHeaderFields', 0, 0) && api.message(snapshot, c'isKindOfClass:', api.dictionary, 0) == 1
	assert api.text(api.message(snapshot, c'objectForKey:', api.string(c'Content-Type'), 0)) == 'Text/Plain; charset="UTF-8"'
	api.put(headers, c'x-mixed-case', c'changed'); api.message(headers, c'removeAllObjects', 0, 0)
	assert api.text(api.message(r, c'valueForHTTPHeaderField:', api.string(c'X-MIXED-CASE'), 0)) == 'one'
	assert api.message(r, c'valueForHTTPHeaderField:', api.string(c'x-missing'), 0) == 0
	api.release(r)
	for index, value in [c'-10', c'bad', c'12junk', c' 42 ', c'9223372036854775808']! {
		h := api.message(api.dictionary, c'dictionary', 0, 0); api.put(h, c'Content-Length', value); response := api.response(url, 200, h)
		assert i64(api.message(response, c'expectedContentLength', 0, 0)) == [i64(-1), 0, 12, 42, 9223372036854775807]![index]
		api.release(response)
	}
	for index, value in [c'application/json; charset=UTF-8', c'text/plain; CHARSET=ISO-8859-1', c'text/plain; charset=', c'text/plain ; foo=bar; charset=UTF-8', c' Text/HTML ', c'text/plain; charset=utf-8; charset=latin1']! {
		h := api.message(api.dictionary, c'dictionary', 0, 0); api.put(h, c'Content-Type', value); response := api.response(url, 200, h)
		assert api.text(api.message(response, c'MIMEType', 0, 0)) == ['application/json', 'text/plain', 'text/plain', 'text/plain', 'text/html', 'text/plain']![index]
		enc := api.message(response, c'textEncodingName', 0, 0)
		if index in [2, 4] { assert enc == 0 } else { assert api.text(enc) == ['utf-8', 'iso-8859-1', '', 'utf-8', '', 'utf-8']![index] }
		api.release(response)
	}
	h := api.message(api.dictionary, c'dictionary', 0, 0); changing_type := api.mutable_string(c'text/plain; charset=utf-8'); changing_length := api.mutable_string(c'12')
	api.message(h, c'setObject:forKey:', changing_type, api.string(c'content-type')); api.message(h, c'setObject:forKey:', changing_length, api.string(c'content-length'))
	changed := api.response(url, 200, h); api.change_string(changing_type, c'application/json'); api.change_string(changing_length, c'99')
	assert api.message(changed, c'expectedContentLength', 0, 0) == 99 && api.text(api.message(changed, c'MIMEType', 0, 0)) == 'application/json' && api.message(changed, c'textEncodingName', 0, 0) == 0
	api.release(changed)
	for index, code in [i64(-1), 0, 1023, 1024, 1200]! { response := api.response(0, code, 0); assert api.message(response, c'statusCode', 0, 0) == [u64(1023), 0, 1023, 0, 176]![index]; api.release(response) }
	for index, code in [i64(0), 100, 199, 200, 299, 307, 404, 500, 599, 1200]! { assert api.text(api.message(api.http, c'localizedStringForStatusCode:', u64(code), 0)) == ['server error', 'continue', 'informational', 'no error', 'success', 'temporarily redirected', 'not found', 'internal server error', 'server error', 'server error']![index] }
	api.drain(pool)
}

fn test_response_native_data() {
	$if macos {
		api := ResponseApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), base: u64(C.objc_getClass(c'NSURLResponse')), http: u64(C.objc_getClass(c'NSHTTPURLResponse')), url: u64(C.objc_getClass(c'NSURL')), strings: u64(C.objc_getClass(c'NSString')), dictionary: u64(C.objc_getClass(c'NSMutableDictionary'))}
		response_cases(api)
		pool := api.pool(); for code in i64(0) .. 600 { assert api.text(api.message(api.http, c'localizedStringForStatusCode:', u64(code), 0)) == response_status_text(code) }; api.drain(pool)
		println('IOS-RESPONSE-NATIVE: defaults, copied base strings, retained/live HTTP values, canonical fields, snapshot identity, permissive length parsing, ten-bit status and 600 English status strings passed')
	}
}

fn response_runtime_api() ResponseApi { return ResponseApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), base: ios_runtime.names['NSURLResponse'], http: ios_runtime.names['NSHTTPURLResponse'], url: ios_runtime.names['NSURL'], strings: ios_runtime.names['NSString'], dictionary: ios_runtime.names['NSMutableDictionary']} }
fn test_response_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start(); api := response_runtime_api()
		assert objc_class_size(api.base) == 24 && objc_class_size(api.http) == 32 && objc_class_parent(api.http) == api.base
		assert objc_ivar_offset(objc_find_ivar(api.base, c'_internal')) == 8 && objc_ivar_offset(objc_find_ivar(api.base, c'__cf_resp_data')) == 16 && objc_ivar_offset(objc_find_ivar(api.http, c'_httpInternal')) == 24
		assert ctext(u64(objc_method_types(objc_instance_method(api.http, u64(c'initWithURL:statusCode:HTTPVersion:headerFields:'))))) == '@48@0:8@16q24@32@40'
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSHTTPURLResponse') or { panic(err) } == api.http
		response_cases(api); assert ios_runtime.live == 0
		for _ in 0 .. 100 {
			pool := api.pool(); h := api.message(api.dictionary, c'dictionary', 0, 0); api.put(h, c'content-type', c'text/plain'); api.put(h, c'content-length', c'12')
			r := api.response(0, 200, h); assert objc_copy_value(r, false) == r; objc_release(r)
			owner := objc_new(ios_runtime.names['NSObject']); objc_set_associated(owner, 7, r, 3); assert objc_get_associated(owner, 7) == r; objc_release(owner)
			api.message(r, c'MIMEType', 0, 0); api.message(r, c'allHeaderFields', 0, 0)
			objc_set_class(r, ios_runtime.names['NSObject']); api.release(r); api.drain(pool); assert ios_runtime.live == 0
		}
		storage := u64(C.calloc(1, 32)); assert objc_construct_instance(api.http, storage) == storage && api.initialized(storage, 0, 201, 0) == storage
		assert read64(storage + 8) == 0 && read64(storage + 16) == 0 && read64(storage + 24) == 0
		assert objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) }); assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-RESPONSE: shared native fixtures, layouts/types, live parsed fields, immutable snapshots, copy associations, 100 isa-change releases, caller storage and two clean cycles passed')
}

fn test_response_rejections() {
	objc_start(); api := response_runtime_api(); wrong := objc_new(ios_runtime.names['NSNumber'])
	for operation in 0 .. 13 {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			r := api.response(0, 200, 0); h := api.message(r, c'allHeaderFields', 0, 0)
			match operation {
				0 { api.response(wrong, 200, 0) }
				1 { api.response(0, 200, wrong) }
				2 { api.message(h, c'setObject:forKey:', api.string(c'one'), api.string(c'x')) }
				3 { api.message(h, c'setObject:forKeyedSubscript:', api.string(c'one'), api.string(c'x')) }
				4 { api.message(h, c'removeAllObjects', 0, 0) }
				5 { cf_dictionary_set(h, api.string(c'x'), api.string(c'one')) }
				6 { cf_dictionary_add(h, api.string(c'x'), api.string(c'one')) }
				7 { api.message(r, c'suggestedFilename', 0, 0) }
				8 { api.message(r, c'_CFURLResponse', 0, 0) }
				9 { api.message(r, c'init', 0, 0) }
				10 { input := api.message(api.dictionary, c'dictionary', 0, 0); api.put(input, c'x', c'one'); api.put(input, c'X', c'two'); api.response(0, 200, input) }
				11 { input := api.message(api.dictionary, c'dictionary', 0, 0); api.message(input, c'setObject:forKey:', wrong, api.string(c'x')); api.response(0, 200, input) }
				else { api.message(r, c'valueForHTTPHeaderField:', 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains(['request URL must be a URL', 'response headers require a dictionary', 'mutation of immutable response headers', 'mutation of immutable response headers', 'mutation of immutable response headers', 'mutation of immutable response headers', 'mutation of immutable response headers', 'unimplemented Objective-C method NSHTTPURLResponse suggestedFilename', 'unimplemented Objective-C method NSHTTPURLResponse _CFURLResponse', 'response reinitialization is not implemented', 'duplicate case-folded response fields are not implemented', 'request header and method values must be strings', 'request header and method values must be strings']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(wrong); assert ios_runtime.live == 0; objc_stop()
	println('IOS-RESPONSE-REJECT: invalid inputs, ObjC/subscript/remove and CF snapshot mutation, filename/private API, reinitialization and duplicate fields fail explicitly')
}
