// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type CStringOutputSend = fn (u64, u64, u64, u64, u64) u64
struct CStringOutputApi { native bool send u64 }
struct CStringOutputCase { input string encoding u64 expected string fails bool }

fn (api CStringOutputApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api CStringOutputApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api CStringOutputApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { CStringOutputSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api CStringOutputApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api CStringOutputApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api CStringOutputApi) string(cls u64, text string) u64 {
	return api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn cstring_output_check(pointer u64, expected string) {
	assert pointer != 0
	assert unsafe { (&char(voidptr(pointer))).vstring_with_len(expected.len) } == expected
	assert unsafe { (&u8(voidptr(pointer)))[expected.len] } == 0
}
fn cstring_output_cases() []CStringOutputCase {
	return [
		CStringOutputCase{'', 4, '', false}, CStringOutputCase{'', 1, '', false},
		CStringOutputCase{'', 5, '', false}, CStringOutputCase{'ASCII', 1, 'ASCII', false},
		CStringOutputCase{'A\x00B', 1, 'A\x00B', false},
		CStringOutputCase{'Café\x00😀', 4, 'Café\x00😀', false},
		CStringOutputCase{'e\u0301', 4, 'e\u0301', false},
		CStringOutputCase{'e\u0301', 5, '\xe9', false},
		CStringOutputCase{'A\u030a', 5, '\xc5', false},
		CStringOutputCase{'\u0080ÿ\x00é', 5, '\x80\xff\x00\xe9', false},
		CStringOutputCase{'é', 1, '', true}, CStringOutputCase{'😀', 1, '', true},
		CStringOutputCase{'€', 5, '', true}, CStringOutputCase{'Ā', 5, '', true},
		CStringOutputCase{'e\u0301', 1, '', true}, CStringOutputCase{'😀', 5, '', true},
		CStringOutputCase{'\u212b', 5, '', true}, CStringOutputCase{'\u212a', 5, '', true},
		CStringOutputCase{'e\u0341', 5, '', true}, CStringOutputCase{'\u0301', 5, '', true},
		CStringOutputCase{'e\u0301\u0300', 5, '', true},
	]
}
fn cstring_output_worker(api CStringOutputApi, cls u64, imp u64) {
	for _ in 0 .. 64 {
		pool := api.pool()
		object := api.string(cls, 'Café\x00😀')
		pointer := unsafe { CStringOutputSend(voidptr(imp))(object, api.sel(c'cStringUsingEncoding:'), 4, 0, 0) }
		cstring_output_check(pointer, 'Café\x00😀')
		api.message(object, c'release', 0, 0, 0)
		api.drain(pool)
	}
}
fn cstring_output_shared(api CStringOutputApi) {
	pool := api.pool()
	for name in [c'NSString', c'NSMutableString']! {
		cls := api.cls(name)
		selector := api.sel(c'cStringUsingEncoding:')
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == 'r*24@0:8Q16'
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == 'r*24@0:8Q16'
			assert objc_instance_method(read64(cls), selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0 && api.message(cls, c'respondsToSelector:', selector, 0, 0) == 0
		for item in cstring_output_cases() {
			object := api.string(cls, item.input)
			assert api.message(object, c'respondsToSelector:', selector, 0, 0) == 1
			pointer := api.message(object, c'cStringUsingEncoding:', item.encoding, 0, 0)
			direct := unsafe { CStringOutputSend(voidptr(imp))(object, selector, item.encoding, 0, 0) }
			if item.fails {
				assert pointer == 0 && direct == 0, 'encoding=${item.encoding} input=${item.input.bytes().hex()} pointer=${pointer} direct=${direct}'
			}
			else {
				assert pointer != 0 && direct != 0, 'encoding=${item.encoding} input=${item.input.bytes().hex()} pointer=${pointer} direct=${direct}'
				cstring_output_check(pointer, item.expected); cstring_output_check(direct, item.expected)
			}
			api.message(object, c'release', 0, 0, 0)
		}
		object := api.string(cls, 'Café')
		signature := api.message(object, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && api.message(signature, c'numberOfArguments', 0, 0, 0) == 3
		assert api.message(signature, c'methodReturnLength', 0, 0, 0) == 8
		assert ctext(api.message(signature, c'methodReturnType', 0, 0, 0)) == 'r*'
		pointer := api.message(object, c'cStringUsingEncoding:', 4, 0, 0)
		cstring_output_check(api.message(object, c'cStringUsingEncoding:', 5, 0, 0), 'Caf\xe9')
		cstring_output_check(pointer, 'Café')
		if !api.native {
			// Our autoreleased snapshot also survives receiver mutation/release;
			// native Foundation only promises the shorter receiver/pool lifetime.
			if unsafe { name.vstring() } == 'NSMutableString' {
				other := api.string(api.cls(c'NSString'), 'changed')
				api.message(object, c'setString:', other, 0, 0)
				api.message(other, c'release', 0, 0, 0)
				cstring_output_check(api.message(object, c'cStringUsingEncoding:', 1, 0, 0), 'changed')
			}
			api.message(object, c'release', 0, 0, 0)
			cstring_output_check(pointer, 'Café')
		} else { api.message(object, c'release', 0, 0, 0) }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn cstring_output_worker(api, cls, imp) }
		for worker in workers { worker.wait() }
	}
	api.drain(pool)
}
fn cstring_output_constants(api CStringOutputApi) {
	pool := api.pool()
	text := 'é\x00😀'
	mut record := [api.cls(c'NSString'), u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] })
	ios_runtime.constants[address] = true
	cstring_output_check(api.message(address, c'cStringUsingEncoding:', 4, 0, 0), text)
	assert api.message(address, c'cStringUsingEncoding:', 1, 0, 0) == 0
	wide := [u16(0xe9), 0, 0xd83d, 0xde00, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 4
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 10, prot: 1}]}
		layout: macho.Layout{size: 10}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	cstring_output_check(api.message(address, c'cStringUsingEncoding:', 4, 0, 0), text)
	assert api.message(address, c'cStringUsingEncoding:', 5, 0, 0) == 0
	cache := ios_runtime.constant_utf8[address] or { panic('missing string cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cache.free() }
	ios_runtime.constants.delete(address)
	api.drain(pool)
}
fn test_string_cstring_output_native() {
	$if macos {
		api := CStringOutputApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		cstring_output_shared(api)
		println('IOS-STRING-CSTRING-OUTPUT-NATIVE: UTF8, ASCII, Latin1, NUL, conversion failure, metadata, IMP and eight workers PASS')
	}
}
fn test_string_cstring_output_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		api := CStringOutputApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		cstring_output_shared(api)
		cstring_output_constants(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-STRING-CSTRING-OUTPUT: UTF8, ASCII, Latin1, NUL, conversion failure, metadata, IMP, mutation, constants, eight workers and two balanced lifetimes PASS')
}
