// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <dlfcn.h>
	fn C.objc_getClass(&char) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
	fn C.method_getTypeEncoding(voidptr) &char
	fn C.method_getImplementation(voidptr) voidptr
	fn C.dlopen(&char, int) voidptr
	fn C.dlsym(voidptr, &char) voidptr
}
type ErrorDescriptionSend = fn (u64, u64, u64, u64, u64) u64
type ErrorDescriptionPush = fn () u64
type ErrorDescriptionPop = fn (u64)
type ErrorDescriptionImp = fn (u64, u64) u64

struct ErrorDescriptionApi {
	native bool
	send u64
	push u64
	pop u64
	strings u64
	mutable_strings u64
	dictionaries u64
	errors u64
}
fn (api ErrorDescriptionApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { ErrorDescriptionSend(voidptr(api.send))(object, selector, a, b, c) }
}
fn (api ErrorDescriptionApi) pool() u64 {
	$if macos { if api.native { return unsafe { ErrorDescriptionPush(voidptr(api.push))() } } }
	return objc_pool_push()
}
fn (api ErrorDescriptionApi) drain(pool u64) {
	$if macos { if api.native { unsafe { ErrorDescriptionPop(voidptr(api.pop))(pool) }; return } }
	objc_pool_pop(pool)
}
fn (api ErrorDescriptionApi) text(value string) u64 {
	if !api.native { return objc_autorelease(owned_string(value)) }
	return api.msg(api.strings, c'stringWithBytes:length:encoding:', u64(value.str), u64(value.len), 4)
}
fn (api ErrorDescriptionApi) value(object u64) string {
	length := api.msg(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
	return unsafe { tos(&u8(api.msg(object, c'UTF8String', 0, 0, 0)), int(length)) }
}
fn (api ErrorDescriptionApi) make(domain string, code i64, info u64) u64 {
	return api.msg(api.errors, c'errorWithDomain:code:userInfo:', api.text(domain), u64(code), info)
}
fn (api ErrorDescriptionApi) describe(object u64) string {
	return api.value(api.msg(object, c'description', 0, 0, 0))
}
fn error_description_cases(api ErrorDescriptionApi) {
	pool := api.pool()
	for domain in ['TestDomain', '', 'é"\\\n', 'A\x00B'] {
		for code in [i64(0), 7, -50, i64(-9223372036854775807) - 1, 9223372036854775807] {
			object := api.make(domain, code, 0)
			assert api.describe(object) == 'Error Domain=' + domain + ' Code=' + code.str() + ' "(null)"'
		}
	}
	for i, domain in ['NSOSStatusErrorDomain', 'NSOSStatusErrorDomain', 'NSCocoaErrorDomain']! {
		code := [i64(561145203), -50, 3840]![i]
		detail := ['(null)', 'paramErr: error in user parameter list', 'The data couldn’t be read because it isn’t in the correct format.']![i]
		assert api.describe(api.make(domain, code, 0)) == 'Error Domain=' + domain + ' Code=' + code.str() + ' "' + detail + '"'
	}
	for key in ['NSLocalizedDescription', 'NSLocalizedFailureReason', 'NSDebugDescription', 'NSDescription', 'NSLocalizedRecoverySuggestion', 'other'] {
		for detail in ['', 'é"\\\n', 'a\x00b'] {
			info := api.msg(api.dictionaries, c'dictionary', 0, 0, 0)
			api.msg(info, c'setObject:forKey:', api.text(detail), api.text(key), 0)
			object := api.make('TestDomain', 7, info)
			selected := if key in ['NSLocalizedRecoverySuggestion', 'other'] { '(null)' } else { detail }
			assert api.describe(object) == 'Error Domain=TestDomain Code=7 "' + selected + '" UserInfo={' + key + '=' + detail + '}'
		}
	}
	// Dictionary enumeration order is unspecified. Check diagnostic precedence
	// and every entry without requiring native hash-table ordering.
	for mask in [3, 7, 15] {
		info := api.msg(api.dictionaries, c'dictionary', 0, 0, 0)
		for i, key in ['NSLocalizedDescription', 'NSLocalizedFailureReason', 'NSDebugDescription', 'NSDescription']! {
			if mask & (1 << i) != 0 { api.msg(info, c'setObject:forKey:', api.text(key), api.text(key), 0) }
		}
		result := api.describe(api.make('TestDomain', 7, info))
		selected := match mask { 3 { '"NSLocalizedDescription"' } 7 { '"NSDebugDescription"' } else { '"NSDescription" (NSDebugDescription)' } }
		assert result.starts_with('Error Domain=TestDomain Code=7 ' + selected + ' UserInfo={') && result.ends_with('}')
		for i, key in ['NSLocalizedDescription', 'NSLocalizedFailureReason', 'NSDebugDescription', 'NSDescription']! {
			if mask & (1 << i) != 0 { assert result.contains(key + '=' + key) }
		}
	}
	// NSError copies the dictionary and domain, but shares its values.
	value := api.msg(api.mutable_strings, c'stringWithString:', api.text('before'), 0, 0)
	domain := api.msg(api.mutable_strings, c'stringWithString:', api.text('MutableDomain'), 0, 0)
	info := api.msg(api.dictionaries, c'dictionary', 0, 0, 0)
	api.msg(info, c'setObject:forKey:', value, api.text('NSLocalizedDescription'), 0)
	object := api.msg(api.errors, c'errorWithDomain:code:userInfo:', domain, 9, info)
	previous := api.msg(object, c'description', 0, 0, 0)
	api.msg(value, c'appendString:', api.text(' after'), 0, 0)
	api.msg(domain, c'appendString:', api.text(' changed'), 0, 0)
	api.msg(info, c'setObject:forKey:', api.text('extra'), api.text('other'), 0)
	assert api.value(previous) == 'Error Domain=MutableDomain Code=9 "before" UserInfo={NSLocalizedDescription=before}'
	assert api.describe(object) == 'Error Domain=MutableDomain Code=9 "before after" UserInfo={NSLocalizedDescription=before after}'
	api.drain(pool)
}
fn error_description_worker(object u64) {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		mut frame := RegisterFrame{}
		frame.x[0] = object; frame.x[1] = u64(c'description')
		assert objc_dispatch(mut frame, 0) == 0
		assert string_text(frame.x[0]) == 'Error Domain=NSOSStatusErrorDomain Code=561145203 "(null)"'
		objc_pool_pop(pool)
	}
}
fn error_description_rejections(api ErrorDescriptionApi) {
	pool := api.pool()
	info := api.msg(api.dictionaries, c'dictionary', 0, 0, 0)
	value := objc_autorelease(objc_allocate(ios_runtime.names['NSObject']))
	api.msg(info, c'setObject:forKey:', value, api.text('other'), 0)
	object := api.make('TestDomain', 1, info)
	mut rejected := false
	ns_error_description(object) or {
		assert err.msg() == 'iOS: NSError description supports string userInfo values'
		rejected = true
	}
	assert rejected
	text := 'x'.repeat(1024 * 1024)
	large := api.make(text, 1, 0)
	unsafe { text.free() }
	live := ios_runtime.live
	rejected = false
	ns_error_description(large) or {
		assert err.msg() == 'iOS: excessive NSError description'
		rejected = true
	}
	assert rejected && ios_runtime.live == live
	api.drain(pool)
}
fn test_ns_error_description() {
	$if macos {
		library := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		assert library != unsafe { nil }
		api := ErrorDescriptionApi{native: true
			send: u64(C.dlsym(library, c'objc_msgSend')), push: u64(C.dlsym(library, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(library, c'objc_autoreleasePoolPop'))
			strings: u64(C.objc_getClass(c'NSString')), mutable_strings: u64(C.objc_getClass(c'NSMutableString'))
			dictionaries: u64(C.objc_getClass(c'NSMutableDictionary')), errors: u64(C.objc_getClass(c'NSError'))}
		method := C.class_getInstanceMethod(voidptr(api.errors), C.sel_registerName(c'description'))
		assert method != unsafe { nil } && C.method_getImplementation(method) != unsafe { nil }
		assert ctext(u64(C.method_getTypeEncoding(method))) == '@16@0:8'
		error_description_cases(api)
		println('IOS-ERROR-DESCRIPTION-NATIVE: diagnostic format, 64-bit codes, Unicode and NULs, string userInfo precedence and shallow-copy mutation PASS')
	}
	for _ in 0 .. 2 {
		objc_start()
		api := ErrorDescriptionApi{send:u64(unsafe { voidptr(C.ios_objc_builtin) })
			strings:ios_runtime.names['NSString'], mutable_strings:ios_runtime.names['NSMutableString']
			dictionaries:ios_runtime.names['NSMutableDictionary'], errors:ios_runtime.names['NSError']}
		error_description_cases(api)
		error_description_rejections(api)
		pool := objc_pool_push()
		name := owned_string('NSOSStatusErrorDomain')
		object := ns_error_create(name, 561145203, 0)
		objc_release(name)
		method := objc_instance_method(api.errors, u64(c'description'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
		assert objc_responds(object, c'description') && !objc_responds(object, c'vinixMissingErrorDescription')
		result := unsafe { ErrorDescriptionImp(voidptr(objc_method_imp(method)))(object, u64(c'description')) }
		assert string_text(result) == api.describe(object)
		retained := objc_retain(result)
		objc_pool_pop(pool)
		live := ios_runtime.live
		refs := obj_header(object).refs
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn error_description_worker(object) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == live && obj_header(object).refs == refs
		objc_release(object)
		assert string_text(retained) == 'Error Domain=NSOSStatusErrorDomain Code=561145203 "(null)"'
		objc_release(retained)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-ERROR-DESCRIPTION: diagnostic format, string userInfo, independent results, direct IMP, retained lifetime, eight workers and two drained runtimes PASS')
}
