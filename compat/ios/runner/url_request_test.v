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
type RequestSend = fn (u64, u64, u64, u64) u64
type RequestTimed = fn (u64, u64, u64, u64, f64) u64
type RequestNumber = fn (u64, u64) f64
type RequestSetNumber = fn (u64, u64, f64)

struct RequestApi {
	native bool
	send u64
	request u64
	mutable_request u64
	url u64
	string_class u64
	dictionary u64
}
fn (api RequestApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api RequestApi) message(object u64, name &char, a u64, b u64) u64 { return unsafe { RequestSend(voidptr(api.send))(object, api.selector(name), a, b) } }
fn (api RequestApi) timed(object u64, name &char, url u64, policy u64, timeout f64) u64 { return unsafe { RequestTimed(voidptr(api.send))(object, api.selector(name), url, policy, timeout) } }
fn (api RequestApi) number(object u64) f64 { return unsafe { RequestNumber(voidptr(api.send))(object, api.selector(c'timeoutInterval')) } }
fn (api RequestApi) set_number(object u64, timeout f64) { unsafe { RequestSetNumber(voidptr(api.send))(object, api.selector(c'setTimeoutInterval:'), timeout) } }
fn (api RequestApi) string(value &char) u64 { return api.message(api.string_class, c'stringWithUTF8String:', u64(value), 0) }
fn (api RequestApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0)) }
fn (api RequestApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0) }
fn (api RequestApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api RequestApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api RequestApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}
fn (api RequestApi) mutable_string(value &char) u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(value), 0) } }
	return objc_autorelease(owned_string(ctext(u64(value))))
}
fn (api RequestApi) change_string(object u64, value &char) {
	$if macos { if api.native { api.message(object, c'setString:', api.string(value), 0); return } }
	text := ctext(u64(value)); mut header := obj_header(object)
	C.free(header.text); header.text = unsafe { &char(C.malloc(usize(text.len + 1))) }; assert header.text != unsafe { nil }
	unsafe { C.memcpy(header.text, text.str, usize(text.len)); header.text[text.len] = 0 }; header.text_length = text.len
}
fn (api RequestApi) body() u64 {
	bytes := [u8(1), 0, 3]!
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSMutableData')), c'dataWithBytes:length:', u64(unsafe { &bytes[0] }), 3) } }
	data := cf_data_mutable(0, 3); cf_data_set_length(data, 3); unsafe { C.memcpy(voidptr(data_pointer(data)), &bytes[0], 3) }; return objc_autorelease(data)
}
fn (api RequestApi) change_body(data u64) {
	$if macos { if api.native { unsafe { *(&u8(api.message(data, c'mutableBytes', 0, 0))) = 9 }; return } }
	unsafe { *(&u8(data_pointer(data))) = 9 }
}

fn request_cases(api RequestApi) {
	pool := api.pool()
	url := api.message(api.url, c'URLWithString:', api.string(c'https://example.test/path'), 0)
	for cls in [api.request, api.mutable_request]! {
		empty := api.message(cls, c'new', 0, 0)
		assert api.message(empty, c'URL', 0, 0) == 0 && api.text(api.message(empty, c'HTTPMethod', 0, 0)) == 'GET' && api.number(empty) == 60
		api.release(empty)
		r := api.message(cls, c'requestWithURL:', url, 0)
		assert api.message(r, c'URL', 0, 0) == url && api.number(r) == 60
		for selector in [c'cachePolicy', c'networkServiceType', c'attribution', c'HTTPShouldUsePipelining', c'assumesHTTP3Capable', c'requiresDNSSECValidation', c'HTTPBody', c'HTTPBodyStream', c'allHTTPHeaderFields', c'mainDocumentURL', c'cookiePartitionIdentifier']! { assert api.message(r, selector, 0, 0) == 0 }
		for selector in [c'allowsCellularAccess', c'allowsExpensiveNetworkAccess', c'allowsConstrainedNetworkAccess', c'HTTPShouldHandleCookies']! { assert api.message(r, selector, 0, 0) == 1 }
		copied := api.message(r, c'copy', 0, 0)
		assert (copied == r) == (cls == api.request)
		if cls == api.mutable_request { assert api.message(copied, c'isKindOfClass:', api.mutable_request, 0) == 1 }
		api.release(copied)
		mc := api.message(r, c'mutableCopyWithZone:', 0, 0)
		assert mc != r && api.message(mc, c'isKindOfClass:', api.mutable_request, 0) == 1
		api.message(mc, c'setHTTPMethod:', api.string(c'post'), 0)
		assert api.text(api.message(mc, c'HTTPMethod', 0, 0)) == 'POST' && api.text(api.message(r, c'HTTPMethod', 0, 0)) == 'GET'
		api.release(mc)
	}
	initialized := api.timed(api.message(api.request, c'alloc', 0, 0), c'initWithURL:cachePolicy:timeoutInterval:', url, 3, 2.5)
	assert api.number(initialized) == 2.5 && api.message(initialized, c'cachePolicy', 0, 0) == 3
	api.release(initialized)
	factory := api.timed(api.request, c'requestWithURL:cachePolicy:timeoutInterval:', url, 4, 0)
	assert api.number(factory) == 0 && api.message(factory, c'cachePolicy', 0, 0) == 4
	assert api.message(api.message(api.request, c'requestWithURL:', 0, 0), c'URL', 0, 0) == 0
	r := api.message(api.mutable_request, c'requestWithURL:', url, 0)
	api.set_number(r, -1); assert api.number(r) == -1
	api.message(r, c'setMainDocumentURL:', url, 0); assert api.message(r, c'mainDocumentURL', 0, 0) == url
	api.message(r, c'setURL:', 0, 0); assert api.message(r, c'URL', 0, 0) == 0
	api.message(r, c'setURL:', url, 0)
	for pair in [[c'setAllowsCellularAccess:', c'allowsCellularAccess']!, [c'setAllowsExpensiveNetworkAccess:', c'allowsExpensiveNetworkAccess']!, [c'setAllowsConstrainedNetworkAccess:', c'allowsConstrainedNetworkAccess']!, [c'setHTTPShouldHandleCookies:', c'HTTPShouldHandleCookies']!]! { api.message(r, pair[0], 0, 0); assert api.message(r, pair[1], 0, 0) == 0 }
	for pair in [[c'setHTTPShouldUsePipelining:', c'HTTPShouldUsePipelining']!, [c'setAssumesHTTP3Capable:', c'assumesHTTP3Capable']!, [c'setRequiresDNSSECValidation:', c'requiresDNSSECValidation']!]! { api.message(r, pair[0], 1, 0); assert api.message(r, pair[1], 0, 0) == 1 }
	api.message(r, c'setNetworkServiceType:', 8, 0); assert api.message(r, c'networkServiceType', 0, 0) == 8
	api.message(r, c'setAttribution:', 1, 0); assert api.message(r, c'attribution', 0, 0) == 1
	api.message(r, c'setCachePolicy:', 5, 0); assert api.message(r, c'cachePolicy', 0, 0) == 5
	for verb in [c'options', c'trace', c'custom']! { api.message(r, c'setHTTPMethod:', api.string(verb), 0); assert api.text(api.message(r, c'HTTPMethod', 0, 0)) == ctext(u64(verb)) }
	custom := api.mutable_string(c'custom'); api.message(r, c'setHTTPMethod:', custom, 0); api.change_string(custom, c'changed'); assert api.text(api.message(r, c'HTTPMethod', 0, 0)) == 'changed'
	api.message(r, c'setHTTPMethod:', 0, 0); assert api.message(r, c'HTTPMethod', 0, 0) == 0
	partition := api.mutable_string(c'partition'); api.message(r, c'setCookiePartitionIdentifier:', partition, 0); api.change_string(partition, c'changed'); assert api.text(api.message(r, c'cookiePartitionIdentifier', 0, 0)) == 'changed'
	value := api.mutable_string(c'before'); key := api.string(c'x-field')
	api.message(r, c'setValue:forHTTPHeaderField:', value, key)
	api.change_string(value, c'changed'); assert api.text(api.message(r, c'valueForHTTPHeaderField:', api.string(c'X-FIELD'), 0)) == 'changed'
	snapshot := api.message(r, c'allHTTPHeaderFields', 0, 0)
	api.message(snapshot, c'setObject:forKey:', api.string(c'snapshot'), key)
	assert api.text(api.message(r, c'valueForHTTPHeaderField:', key, 0)) == 'changed'
	api.message(r, c'addValue:forHTTPHeaderField:', api.string(c'two'), api.string(c'X-FIELD'))
	assert api.text(api.message(r, c'valueForHTTPHeaderField:', key, 0)) == 'changed,two'
	assert api.text(api.message(snapshot, c'objectForKey:', key, 0)) == 'snapshot'
	copy := api.message(r, c'copyWithZone:', 0, 0)
	api.message(copy, c'setValue:forHTTPHeaderField:', api.string(c'copy'), key)
	assert api.text(api.message(r, c'valueForHTTPHeaderField:', key, 0)) == 'changed,two'
	api.release(copy)
	api.message(r, c'setValue:forHTTPHeaderField:', 0, key)
	assert api.message(r, c'valueForHTTPHeaderField:', key, 0) == 0 && api.message(api.message(r, c'allHTTPHeaderFields', 0, 0), c'count', 0, 0) == 0
	api.message(r, c'setAllHTTPHeaderFields:', 0, 0)
	assert api.message(r, c'allHTTPHeaderFields', 0, 0) != 0
	bulk := api.message(api.dictionary, c'dictionary', 0, 0)
	api.message(bulk, c'setObject:forKey:', api.string(c'bulk'), key)
	api.message(r, c'setAllHTTPHeaderFields:', bulk, 0)
	api.message(bulk, c'removeAllObjects', 0, 0)
	assert api.text(api.message(r, c'valueForHTTPHeaderField:', key, 0)) == 'bulk'
	body := api.body(); api.message(r, c'setHTTPBody:', body, 0); api.change_body(body)
	got := api.message(r, c'HTTPBody', 0, 0)
	assert api.message(got, c'length', 0, 0) == 3 && unsafe { *(&u8(api.message(got, c'bytes', 0, 0))) } == 1
	api.message(r, c'setHTTPBody:', got, 0); assert api.message(r, c'HTTPBody', 0, 0) == got
	api.message(r, c'setHTTPBodyStream:', 0, 0); assert api.message(r, c'HTTPBody', 0, 0) == 0
	api.drain(pool)
}

fn test_request_native_data() {
	$if macos {
		api := RequestApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), request: u64(C.objc_getClass(c'NSURLRequest')), mutable_request: u64(C.objc_getClass(c'NSMutableURLRequest')), url: u64(C.objc_getClass(c'NSURL')), string_class: u64(C.objc_getClass(c'NSString')), dictionary: u64(C.objc_getClass(c'NSMutableDictionary'))}
		request_cases(api)
		println('IOS-REQUEST-NATIVE: defaults, mixed FP factory/initializer, mutable-preserving copies, retained strings, mutable header snapshots, case folding and copied body passed')
	}
}

fn request_runtime_api() RequestApi { return RequestApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), request: ios_runtime.names['NSURLRequest'], mutable_request: ios_runtime.names['NSMutableURLRequest'], url: ios_runtime.names['NSURL'], string_class: ios_runtime.names['NSString'], dictionary: ios_runtime.names['NSMutableDictionary']} }
fn test_request_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start(); api := request_runtime_api()
		assert objc_class_size(api.request) == 24 && objc_class_size(api.mutable_request) == 24 && objc_class_parent(api.mutable_request) == api.request
		assert objc_ivar_offset(objc_find_ivar(api.request, c'_internal')) == 8 && objc_ivar_offset(objc_find_ivar(api.request, c'_cookiePartitionIdentifier')) == 16
		assert ctext(u64(objc_method_types(objc_class_method(api.request, u64(c'requestWithURL:cachePolicy:timeoutInterval:'))))) == '@40@0:8@16Q24d32'
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSURLRequest') or { panic(err) } == api.request
		request_cases(api); assert ios_runtime.live == 0
		alias := objc_new(api.mutable_request)
		key := owned_string('x-alias'); value := owned_string('old')
		api.message(alias, c'setValue:forHTTPHeaderField:', value, key); objc_release(key); objc_release(value)
		headers := obj_header(alias).request.refs[4]
		borrowed_key := obj_header(headers).keys[0]
		new_key := owned_string('X-ALIAS')
		request_header_put(headers, new_key, borrowed_key, false); objc_release(new_key)
		assert string_text(obj_header(headers).keys[0]) == 'X-ALIAS' && string_text(obj_header(headers).items[0]) == 'x-alias'
		objc_release(alias); assert ios_runtime.live == 0
		for _ in 0 .. 100 {
			pool := api.pool(); r := objc_new(api.mutable_request)
			api.message(r, c'setValue:forHTTPHeaderField:', api.string(c'one'), api.string(c'x-test'))
			api.message(r, c'setCookiePartitionIdentifier:', api.string(c'partition'), 0)
			api.message(r, c'setHTTPBody:', api.body(), 0)
			copy := objc_copy_value(r, false)
			objc_set_class(r, ios_runtime.names['NSObject']); api.release(r)
			assert api.text(api.message(copy, c'valueForHTTPHeaderField:', api.string(c'X-TEST'), 0)) == 'one'
			objc_set_class(copy, ios_runtime.names['NSObject']); api.release(copy)
			api.drain(pool); assert ios_runtime.live == 0
		}
		storage := u64(C.calloc(1, 24)); assert objc_construct_instance(api.request, storage) == storage
		assert api.message(storage, c'init', 0, 0) == storage
		assert read64(storage + 8) == 0 && read64(storage + 16) == 0
		assert objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) }); assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-REQUEST: shared native data fixtures, measured layouts/types, copied bodies, independent headers, 100 isa-change releases, association copying and caller storage passed')
}

fn test_request_rejections() {
	objc_start(); api := request_runtime_api(); wrong := objc_new(ios_runtime.names['NSNumber'])
	for operation in 0 .. 9 {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			r := objc_new(api.mutable_request)
			match operation {
				0 { api.message(r, c'setURL:', wrong, 0) }
				1 { api.message(r, c'setHTTPBody:', wrong, 0) }
				2 { api.message(r, c'setHTTPMethod:', wrong, 0) }
				3 { api.message(r, c'setAllHTTPHeaderFields:', wrong, 0) }
				4 { api.message(r, c'setValue:forHTTPHeaderField:', api.string(c'value'), api.string(c'bad field')) }
				5 { api.message(r, c'setHTTPBodyStream:', wrong, 0) }
				6 { api.message(r, c'setCachePolicy:', 6, 0) }
				7 { api.message(objc_new(api.request), c'setHTTPMethod:', api.string(c'GET'), 0) }
				else { api.message(r, c'_CFURLRequest', 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		assert output.contains(['request URL must be a URL', 'request body must be data', 'request header and method values must be strings', 'request headers require a dictionary', 'request field name requires an ASCII token', 'nonnil request body streams are not implemented', 'request cache policy is not implemented', 'unimplemented Objective-C method NSURLRequest setHTTPMethod:', 'unimplemented Objective-C method NSMutableURLRequest _CFURLRequest']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(wrong); assert ios_runtime.live == 0; objc_stop()
	println('IOS-REQUEST-REJECT: invalid URL/body/string/dictionary/token, unsupported stream/policy, immutable setter and private CF engine API fail explicitly')
}
