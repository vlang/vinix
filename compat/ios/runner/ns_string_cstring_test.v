// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type CStringSend = fn (u64, u64, u64, u64) u64
struct CStringApi { native bool send u64 }

fn (api CStringApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api CStringApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api CStringApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { CStringSend(voidptr(api.send))(object, api.sel(name), a, b) }
}
fn (api CStringApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls(c'NSAutoreleasePool'), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api CStringApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0); return } }
	objc_pool_pop(pool)
}
fn cstring_expect(api CStringApi, object u64, expected string, units u64) {
	assert object != 0
	assert api.message(object, c'length', 0, 0) == units
	assert api.message(object, c'lengthOfBytesUsingEncoding:', 4, 0) == u64(expected.len)
	address := api.message(object, c'UTF8String', 0, 0)
	assert address != 0
	assert unsafe { tos(&u8(voidptr(address)), expected.len) } == expected
}
fn cstring_worker(api CStringApi, cls u64, imp u64) {
	pool := api.pool()
	worker := c'worker'
	cafe := c'caf\xc3\xa9'
	for _ in 0 .. 128 {
		cstring_expect(api, api.message(cls, c'stringWithCString:encoding:', u64(worker), 4), 'worker', 6)
		result := unsafe { CStringSend(voidptr(imp))(cls, api.sel(c'stringWithCString:encoding:'), u64(cafe), 4) }
		cstring_expect(api, result, 'café', 4)
	}
	api.drain(pool)
}
fn cstring_shared(api CStringApi) {
	pool := api.pool()
	for name in [c'NSString', c'NSMutableString']! {
		cls := api.cls(name)
		sel := api.sel(c'stringWithCString:encoding:')
		assert api.message(cls, c'respondsToSelector:', sel, 0) == 1
		assert api.message(cls, c'respondsToSelector:', api.sel(c'vinixMissingCStringSelector'), 0) == 0
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(C.object_getClass(voidptr(cls)), voidptr(sel))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@32@0:8r*16Q24'
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(read64(cls), sel)
			assert method != 0 && ctext(u64(objc_method_types(method))) == '@32@0:8r*16Q24'
			assert objc_instance_method(cls, sel) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0
		signature := api.message(cls, c'methodSignatureForSelector:', sel, 0)
		assert signature != 0 && api.message(signature, c'numberOfArguments', 0, 0) == 4
		assert api.message(signature, c'methodReturnLength', 0, 0) == 8
		assert unsafe { (&char(voidptr(api.message(signature, c'methodReturnType', 0, 0)))).vstring() } == '@'
		assert unsafe { (&char(voidptr(api.message(signature, c'getArgumentTypeAtIndex:', 2, 0)))).vstring() } == 'r*'
		assert unsafe { (&char(voidptr(api.message(signature, c'getArgumentTypeAtIndex:', 3, 0)))).vstring() } == 'Q'
		for encoding in [u64(1), 4]! {
			empty := c''
			cstring_expect(api, api.message(cls, c'stringWithCString:encoding:', u64(empty), encoding), '', 0)
			for value in 1 .. 256 {
				bytes := [u8(value), 0]!
				result := api.message(cls, c'stringWithCString:encoding:', u64(unsafe { &bytes[0] }), encoding)
				if encoding == 4 && value >= 128 {
					if value == 0xa9 { cstring_expect(api, result, '\xef\xbf\xbd', 1) } else { assert result == 0 }
					continue
				}
				cstring_expect(api, result, rune(value).str(), 1)
			}
		}
		for input in ['café😀', '\xef\xbb\xbfA', '\xef\xbb\xbf\xef\xbb\xbfA', 'A\xef\xbb\xbfB']! {
			expected := if input.starts_with('\xef\xbb\xbf') { input[3..] } else { input }
			units := if input == 'café😀' { u64(6) } else if input == '\xef\xbb\xbfA' { u64(1) } else if input == 'A\xef\xbb\xbfB' { u64(3) } else { u64(2) }
			cstring_expect(api, api.message(cls, c'stringWithCString:encoding:', u64(input.str), 4), expected, units)
		}
		for input in ['\xc0\x80', '\xed\xa0\x80', '\xf4\x90\x80\x80', '\xe2\x82', '\x80', '\xff']! {
			assert api.message(cls, c'stringWithCString:encoding:', u64(input.str), 4) == 0
		}
		for input in ['\xa9\xa9', 'A\xa9', '\xa9A', '\xef\xbb\xbf\xa9', '\xc2\xa9\xa9', '\xa9\xc2\xa9']! {
			expected := match input {
				'\xa9\xa9' { '��' }
				'A\xa9' { 'A�' }
				'\xa9A' { '�A' }
				'\xef\xbb\xbf\xa9' { '�' }
				'\xc2\xa9\xa9' { '©�' }
				else { '�©' }
			}
			cstring_expect(api, api.message(cls, c'stringWithCString:encoding:', u64(input.str), 4), expected, u64(expected.runes().len))
		}
		for input in ['\xc2', '\xa9\x80', '\xc3\xa9\xff']! {
			assert api.message(cls, c'stringWithCString:encoding:', u64(input.str), 4) == 0
		}
		mut bytes := [u8(`A`), 0, 0xff, 0]!
		result := api.message(cls, c'stringWithCString:encoding:', u64(unsafe { &bytes[0] }), 4)
		bytes[0] = `B`
		cstring_expect(api, result, 'A', 1)
		assert api.message(result, c'respondsToSelector:', sel, 0) == 0
		if unsafe { name.vstring() } == 'NSMutableString' {
			exclamation := c'!'
			suffix := api.message(api.cls(c'NSString'), c'stringWithCString:encoding:', u64(exclamation), 1)
			api.message(result, c'appendString:', suffix, 0)
			cstring_expect(api, result, 'A!', 2)
		}
		cstring_worker(api, cls, imp)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn cstring_worker(api, cls, imp) }
		for worker in workers { worker.wait() }
	}
	api.drain(pool)
}
fn test_string_cstring_native() {
	$if macos {
		api := CStringApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		cstring_shared(api)
		println('IOS-STRING-CSTRING-NATIVE: ASCII 255-byte matrix, UTF8, BOM, invalid input, copy, mutable factory, metadata, direct IMP and eight workers PASS')
	}
}
fn test_string_cstring_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		cstring_shared(CStringApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-STRING-CSTRING: ASCII 255-byte matrix, UTF8, BOM, invalid input, copy, mutable factory, metadata, direct IMP, eight workers and two balanced lifetimes PASS')
}
