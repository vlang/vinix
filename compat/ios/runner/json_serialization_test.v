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

type JsonTestSend = fn (u64, u64, u64, u64, u64) u64
type JsonTestDouble = fn (u64, u64) f64
type JsonTestPush = fn () u64
type JsonTestPop = fn (u64)

struct JsonTestApi {
	native             bool
	send               u64
	push               u64
	pop                u64
	json               u64
	data               u64
	string             u64
	array              u64
	dictionary         u64
	mutable_array      u64
	mutable_dictionary u64
	error_class        u64
}

fn (api JsonTestApi) selector(name &char) u64 {
	$if macos {
		if api.native { return u64(C.sel_registerName(name)) }
	}
	return u64(name)
}

fn (api JsonTestApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { JsonTestSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}

fn (api JsonTestApi) pool() u64 {
	$if macos {
		if api.native { return unsafe { JsonTestPush(voidptr(api.push))() } }
	}
	return objc_pool_push()
}

fn (api JsonTestApi) drain(pool u64) {
	$if macos {
		if api.native {
			unsafe { JsonTestPop(voidptr(api.pop))(pool) }
			return
		}
	}
	objc_pool_pop(pool)
}

fn (api JsonTestApi) bytes(bytes []u8) u64 {
	return api.message(api.data, c'dataWithBytes:length:', u64(bytes.data), u64(bytes.len), 0)
}

fn (api JsonTestApi) parse(text string, options u64, error_out &u64) u64 {
	return api.message(api.json, c'JSONObjectWithData:options:error:', api.bytes(unsafe { text.str.vbytes(text.len) }), options, u64(error_out))
}

fn (api JsonTestApi) encode(object u64, options u64, error_out &u64) string {
	data := api.message(api.json, c'dataWithJSONObject:options:error:', object, options, u64(error_out))
	assert data != 0
	return unsafe { tos(&u8(api.message(data, c'bytes', 0, 0, 0)), int(api.message(data, c'length', 0, 0, 0))) }
}

fn (api JsonTestApi) key(object u64, name &char) u64 {
	key := api.message(api.string, c'stringWithUTF8String:', u64(name), 0, 0)
	return api.message(object, c'objectForKey:', key, 0, 0)
}

fn (api JsonTestApi) check_error(object u64) {
	assert object != 0 && object != 0xfeed
	assert api.message(object, c'code', 0, 0, 0) == 3840
	domain := api.message(object, c'domain', 0, 0, 0)
	assert ctext(api.message(domain, c'UTF8String', 0, 0, 0)) == 'NSCocoaErrorDomain'
	assert api.message(object, c'userInfo', 0, 0, 0) != 0
	description := api.message(object, c'localizedDescription', 0, 0, 0)
	assert ctext(api.message(description, c'UTF8String', 0, 0, 0)) == 'The data couldn’t be read because it isn’t in the correct format.'
}

fn json_test_cases(api JsonTestApi) {
	pool := api.pool()
	for text in ['{"a":[true,false,null,1,-2,2.5,"hi"]}',
		'[9223372036854775807,9223372036854775808,18446744073709551615,-9223372036854775808]',
		'["😀","\\u0000","x/y\\n"]', '[1.0,-0,1e2,1e-7]', '{}', '[]']! {
		mut error_out := u64(0xfeed)
		object := api.parse(text, 0, &error_out)
		assert object != 0 && error_out == 0xfeed
		assert api.message(api.json, c'isValidJSONObject:', object, 0, 0) != 0
		encoded := api.encode(object, 10, &error_out)
		assert error_out == 0xfeed
		again := api.parse(encoded, 0, &error_out)
		assert again != 0 && api.encode(again, 10, &error_out) == encoded
		if text.starts_with('[9223') {
			assert encoded == text
		}
		if text.starts_with('[9223') {
			unsigned := api.message(object, c'objectAtIndex:', 2, 0, 0)
			assert ctext(api.message(unsigned, c'objCType', 0, 0, 0)) == 'Q'
			assert api.message(unsigned, c'unsignedIntegerValue', 0, 0, 0) == u64(-1)
			assert unsafe { JsonTestDouble(voidptr(api.send))(unsigned, api.selector(c'doubleValue')) } == f64(u64(-1))
		}
		if text.starts_with('[1.0') {
			assert encoded == '[1,0,100,9.9999999999999995e-08]'
		}
	}
	for options in [u64(0), 1]! {
		mut error_out := u64(0xfeed)
		object := api.parse('{"a":1,"a":2,"b":[true,false,null]}', options, &error_out)
		assert error_out == 0xfeed && api.message(api.key(object, c'a'), c'integerValue', 0, 0, 0) == if options == 0 {
			u64(1)
		} else {
			u64(2)
		}
		assert api.message(object, c'isKindOfClass:', if options == 0 {
			api.dictionary
		} else {
			api.mutable_dictionary
		}, 0, 0) != 0
		assert api.message(api.key(object, c'b'), c'isKindOfClass:', if options == 0 {
			api.array
		} else {
			api.mutable_array
		}, 0, 0) != 0
		if options == 1 {
			item := api.parse('7', 4, &error_out)
			api.message(api.key(object, c'b'), c'addObject:', item, 0, 0)
			assert api.message(api.key(object, c'b'), c'count', 0, 0, 0) == 4
		}
	}
	for text in ['123', '"hi"', 'null', 'true']! {
		mut error_out := u64(0xfeed)
		object := api.parse(text, 4, &error_out)
		assert object != 0 && error_out == 0xfeed && api.message(api.json, c'isValidJSONObject:', object, 0, 0) == 0
		assert api.encode(object, 4, &error_out) == text
	}
	for text in ['[1,]', '{"a":1,}']! {
		mut error_out := u64(0xfeed)
		assert api.parse(text, 0, &error_out) != 0 && error_out == 0xfeed
	}
	for text in ['', '[01]', '[1e400]', '["\\uD800"]', '["\\uDC00"]', '["\\uD800x"]', '["\\uD800\\u0000"]',
		'[1] trailing', '/*c*/[1]', '[1,,]', '{"a":}', '[1e]', '[1.]', '["x\n"]', '123', 'true',
		'null', '{"x":[1,2],"bad":[3,']! {
		mut error_out := u64(0xfeed)
		assert api.parse(text, 0, &error_out) == 0
		api.check_error(error_out)
	}
	for bytes in [[u8(0xef), 0xbb, 0xbf, `[`, `1`, `]`], [u8(0xff), 0xfe, `[`, 0, `1`, 0, `]`,
		0], [u8(0xfe), 0xff, 0, `[`, 0, `1`, 0, `]`], [u8(0), `[`, 0, `1`, 0, `]`],
		[u8(`[`), 0, 0, 0, `1`, 0, 0, 0, `]`, 0, 0, 0]] {
		mut error_out := u64(0xfeed)
		object := api.message(api.json, c'JSONObjectWithData:options:error:', api.bytes(bytes), 0, u64(&error_out))
		assert object != 0 && error_out == 0xfeed && api.encode(object, 0, &error_out) == '[1]'
	}
	for bytes in [[u8(`[`), `"`, 0xff, `"`, `]`], [u8(0xff), 0xfe, `[`, 0, `]`],
		[u8(0xff), 0xfe, `[`, 0, `"`, 0, 0, 0xd8, `"`, 0, `]`, 0]] {
		mut error_out := u64(0xfeed)
		assert api.message(api.json, c'JSONObjectWithData:options:error:', api.bytes(bytes), 0, u64(&error_out)) == 0
		api.check_error(error_out)
	}
	mut error_out := u64(0xfeed)
	object := api.parse('{"b":[1,2],"a":"x/y\\n"}', 0, &error_out)
	assert api.encode(object, 3, &error_out) == '{\n  "a" : "x\\/y\\n",\n  "b" : [\n    1,\n    2\n  ]\n}'
	assert api.encode(object, 10, &error_out) == '{"a":"x/y\\n","b":[1,2]}'
	for text in ['{}', '[]']! {
		assert api.encode(api.parse(text, 0, &error_out), 1, &error_out) == text[0..1] + '\n\n' + text[1..2]
	}
	sorted := api.parse('{"b":0,"A":0,"a":0,"10":0,"2":0,"01":0,"1":0,"Z":0,"z":0,"_":0}', 0, &error_out)
	assert api.encode(sorted, 2, &error_out) == '{"_":0,"1":0,"01":0,"2":0,"10":0,"a":0,"A":0,"b":0,"z":0,"Z":0}'
	domain := api.message(api.string, c'stringWithUTF8String:', u64(c'TestDomain'), 0, 0)
	error_object := api.message(api.error_class, c'errorWithDomain:code:userInfo:', domain, 7, 0)
	assert ctext(api.message(api.message(error_object, c'localizedDescription', 0, 0, 0), c'UTF8String', 0, 0, 0)) == 'The operation couldn’t be completed. (TestDomain error 7.)'
	api.drain(pool)
}

fn test_json_native_reference() {
	$if macos {
		lib := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert lib != unsafe { nil }
		api := JsonTestApi{ native: true, send: u64(C.dlsym(lib, c'objc_msgSend')), push: u64(C.dlsym(lib, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(lib, c'objc_autoreleasePoolPop')), json: u64(C.objc_getClass(c'NSJSONSerialization')), data: u64(C.objc_getClass(c'NSData')), string: u64(C.objc_getClass(c'NSString')), array: u64(C.objc_getClass(c'NSArray')), dictionary: u64(C.objc_getClass(c'NSDictionary')), mutable_array: u64(C.objc_getClass(c'NSMutableArray')), mutable_dictionary: u64(C.objc_getClass(c'NSMutableDictionary')), error_class: u64(C.objc_getClass(c'NSError')) }
		assert C.class_getInstanceSize(voidptr(api.json)) == 8 && C.class_getInstanceSize(voidptr(api.error_class)) == 40
		json_test_cases(api)
		assert C.dlclose(lib) == 0
		println('IOS-JSON-NATIVE: data API, duplicate keys, fragments, Unicode encodings, 64-bit boundaries, malformed errors, pretty output and natural ASCII sorting passed')
	}
}

fn json_test_runtime_api() JsonTestApi {
	return JsonTestApi{ send: u64(unsafe { voidptr(C.ios_objc_builtin) }), json: ios_runtime.names['NSJSONSerialization'], data: ios_runtime.names['NSData'], string: ios_runtime.names['NSString'], array: ios_runtime.names['NSArray'], dictionary: ios_runtime.names['NSDictionary'], mutable_array: ios_runtime.names['NSMutableArray'], mutable_dictionary: ios_runtime.names['NSMutableDictionary'], error_class: ios_runtime.names['NSError'] }
}

fn test_json_runtime_abi_and_lifetimes() {
	for _ in 0 .. 2 {
		objc_start()
		api := json_test_runtime_api()
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSJSONSerialization') or { panic(err) } == api.json
		assert objc_class_size(api.error_class) == 40
		for i, name in [c'_reserved', c'_code', c'_domain', c'_userInfo']! {
			assert objc_ivar_offset(objc_find_ivar(api.error_class, name)) == (i + 1) * 8
		}
		method := objc_instance_method(read64(api.json), u64(c'JSONObjectWithData:options:error:'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@40@0:8@16Q24^@32'
		for _ in 0 .. 25 {
			json_test_cases(api)
			// Only NSNull and the two framework Boolean singletons remain cached.
			assert ios_runtime.live == 3 && ios_runtime.objects.len == 3 && ios_runtime.weak.len == 0
		}
		objc_stop()
		assert ios_runtime.live == 0
	}
	println('IOS-JSON: actual message trampoline, NSError layout/metadata, repeated successful and partial-failure cleanup and balanced cached singleton ownership passed')
}

fn test_json_explicit_profile_and_invalid_graphs() {
	objc_start()
	api := json_test_runtime_api()
	pool := objc_pool_push()
	mut error_out := u64(0)
	for text in ['[18446744073709551616]', '[-9223372036854775809]', '[1.2345678901234567890123456789]']! {
		assert api.parse(text, 0, &error_out) == 0
		api.check_error(error_out)
	}
	for options in [u64(2), 8, 16, u64(-1)]! {
		assert api.parse('[]', options, &error_out) == 0
		api.check_error(error_out)
	}
	assert !objc_responds(api.json, c'JSONObjectWithStream:options:error:')
	object := api.parse('{"é":1}', 0, &error_out)
	assert api.message(api.json, c'dataWithJSONObject:options:error:', object, 2, u64(&error_out)) == 0
	api.check_error(error_out)
	array := objc_allocate(api.mutable_array)
	array_append(mut obj_header(array), array)
	assert !json_valid(array)
	assert api.message(api.json, c'dataWithJSONObject:options:error:', array, 0, u64(&error_out)) == 0
	api.check_error(error_out)
	api.message(array, c'removeAllObjects', 0, 0, 0)
	objc_release(array)
	number := objc_allocate(ios_runtime.names['NSNumber'])
	obj_header(number).is_real = true
	obj_header(number).real_number = math.inf(1)
	array2 := objc_allocate(api.array)
	array_append(mut obj_header(array2), number)
	objc_release(number)
	assert !json_valid(array2)
	objc_release(array2)
	large := api.parse('18446744073709551615', 4, &error_out)
	rounded := api.parse('18446744073709551616.0', 4, &error_out)
	assert large != 0 && rounded == 0
	assert objc_responds(large, c'objCType') && ctext(api.message(large, c'objCType', 0, 0, 0)) == 'Q'
	assert ctext(api.message(api.message(large, c'stringValue', 0, 0, 0), c'UTF8String', 0, 0, 0)) == '18446744073709551615'
	floating := objc_allocate(ios_runtime.names['NSNumber'])
	obj_header(floating).is_real = true
	obj_header(floating).real_number = 18446744073709551616.0
	assert !object_equal(large, floating)
	objc_release(floating)
	mut nested := [145]u8{}
	for i in 0 .. 72 {
		nested[i] = `[`
		nested[144 - i] = `]`
	}
	nested[72] = `0`
	assert api.parse(unsafe { tos(&nested[0], nested.len) }, 0, &error_out) == 0
	api.check_error(error_out)
	assert api.parse('{"a":[1,2],"b":', 0, unsafe { nil }) == 0
	// A default result must not silently expose the mutable collection methods.
	immutable := api.parse('[1]', 0, &error_out)
	mut descriptors := [2]i32{}
	assert C.pipe(unsafe { &descriptors[0] }) == 0
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		C.close(descriptors[0])
		assert C.dup2(descriptors[1], 2) == 2
		C.close(descriptors[1])
		api.message(immutable, c'addObject:', large, 0, 0)
		C._exit(0)
	}
	C.close(descriptors[1])
	mut message := [16384]u8{}
	mut length := 0
	for {
		assert length < message.len
		count := C.read(descriptors[0], unsafe { &message[length] }, usize(message.len - length))
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0
		length += int(count)
	}
	C.close(descriptors[0])
	mut status := i32(0)
	assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
	diagnostic := unsafe { tos(&message[0], length) }
	assert diagnostic.contains('mutation of an immutable JSON collection') && !diagnostic.contains('AddressSanitizer') && !diagnostic.contains('runtime error:')
	objc_pool_pop(pool)
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-JSON-PROFILE: unsupported leaves/extended flags, decimal precision and non-ASCII sorting reject explicitly; cycles and non-finite numbers reject; unsigned values keep exact equality and spelling')
}
