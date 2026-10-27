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
fn C.object_getClass(voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr
type GetCStringSend = fn (u64, u64, u64, u64, u64) u64
struct GetCStringApi { native bool send u64 }
struct GetCStringCase { input string encoding u64 expected string fails bool }

fn (a GetCStringApi) cls(name &char) u64 {
	$if macos { if a.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (a GetCStringApi) sel(name &char) u64 {
	$if macos { if a.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (a GetCStringApi) msg(object u64, name &char, x u64, y u64, z u64) u64 {
	return unsafe { GetCStringSend(voidptr(a.send))(object, a.sel(name), x, y, z) }
}
fn (a GetCStringApi) pool() u64 {
	$if macos { if a.native { return a.msg(a.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (a GetCStringApi) drain(pool u64) {
	$if macos { if a.native { a.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (a GetCStringApi) string(cls u64, text string) u64 {
	return a.msg(a.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn get_cstring_cases() []GetCStringCase {
	return [
		GetCStringCase{'', 1, '', false}, GetCStringCase{'', 4, '', false},
		GetCStringCase{'', 5, '', false}, GetCStringCase{'ABC', 1, 'ABC', false},
		GetCStringCase{'A\x00B', 1, 'A\x00B', false},
		GetCStringCase{'Café\x00😀', 4, 'Café\x00😀', false},
		GetCStringCase{'e\u0301', 4, 'e\u0301', false},
		GetCStringCase{'e\u0301', 5, '\xe9', false},
		GetCStringCase{'Ae\u0301B', 5, 'A\xe9B', false},
		GetCStringCase{'A\u030aB', 5, '\xc5B', false},
		GetCStringCase{'\u0080ÿ\x00é', 5, '\x80\xff\x00\xe9', false},
		GetCStringCase{'é', 1, '', true}, GetCStringCase{'AéB', 1, '', true},
		GetCStringCase{'A😀B', 1, '', true}, GetCStringCase{'A€B', 5, '', true},
		GetCStringCase{'Ā', 5, '', true}, GetCStringCase{'e\u0301', 1, '', true},
		GetCStringCase{'😀', 5, '', true}, GetCStringCase{'\u212b', 5, '', true},
		GetCStringCase{'\u212a', 5, '', true}, GetCStringCase{'e\u0341', 5, '', true},
		GetCStringCase{'\u0301', 5, '', true}, GetCStringCase{'Ae\u0301\u0300B', 5, '', true},
	]
}
fn get_cstring_check(a GetCStringApi, object u64, imp u64, item GetCStringCase, capacity int) {
	// Foundation 26.5's non-ASCII UTF8 path with capacity=1 can return YES
	// and write a terminator beyond that capacity. Record it in the oracle;
	// the runtime deliberately enforces the documented bound instead.
	if a.native && capacity == 1 && item.encoding == 4 && item.input.bytes().any(it > 0x7f) { return }
	mut receiver_imp := imp
	$if macos { if a.native {
		// NSString is a class cluster: compare the concrete receiver's method.
		method := C.class_getInstanceMethod(C.object_getClass(voidptr(object)), voidptr(a.sel(c'getCString:maxLength:encoding:')))
		assert method != unsafe { nil }
		receiver_imp = u64(C.method_getImplementation(method))
	} }
	for call in [a.send, receiver_imp]! {
		storage := if capacity > item.input.len { capacity } else { item.input.len + 1 }
		mut buffer := []u8{len: storage + 4, init: 0xa5}
		selector := a.sel(c'getCString:maxLength:encoding:')
		result := unsafe { GetCStringSend(voidptr(call))(object, selector, u64(&buffer[2]), u64(capacity), item.encoding) } & 0xff
		success := !item.fails && capacity > item.expected.len
		assert result == u64(success), 'input=${item.input.bytes().hex()} encoding=${item.encoding} capacity=${capacity} result=${result}'
		assert buffer[0] == 0xa5 && buffer[1] == 0xa5
		// Failed native conversion contents are unspecified. Vinix always
		// leaves an empty string and never touches bytes beyond capacity.
		if !a.native || success {
			for i in capacity + 2 .. buffer.len { assert buffer[i] == 0xa5 }
		}
		if success {
			assert unsafe { (&char(&buffer[2])).vstring_with_len(item.expected.len) } == item.expected
			assert buffer[item.expected.len + 2] == 0
			for i in item.expected.len + 3 .. buffer.len { assert buffer[i] == 0xa5 }
		} else if !a.native && capacity != 0 { assert buffer[2] == 0 }
		unsafe { buffer.free() }
	}
}
fn get_cstring_worker(a GetCStringApi, cls u64, imp u64) {
	for _ in 0 .. 64 {
		pool := a.pool()
		item := GetCStringCase{'Café\x00😀', 4, 'Café\x00😀', false}
		object := a.string(cls, item.input)
		get_cstring_check(a, object, imp, item, item.expected.len + 1)
		a.msg(object, c'release', 0, 0, 0)
		a.drain(pool)
	}
}
fn get_cstring_shared(a GetCStringApi) {
	pool := a.pool()
	for name in [c'NSString', c'NSMutableString']! {
		cls := a.cls(name)
		selector := a.sel(c'getCString:maxLength:encoding:')
		mut imp := u64(0)
		$if macos { if a.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == 'B40@0:8*16Q24Q32'
			imp = u64(C.method_getImplementation(method))
		} }
		if !a.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == 'B40@0:8*16Q24Q32'
			assert objc_instance_method(read64(cls), selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0 && a.msg(cls, c'respondsToSelector:', selector, 0, 0) == 0
		for item in get_cstring_cases() {
			object := a.string(cls, item.input)
			assert a.msg(object, c'respondsToSelector:', selector, 0, 0) == 1
			for capacity in 0 .. item.input.len + 3 { get_cstring_check(a, object, imp, item, capacity) }
			a.msg(object, c'release', 0, 0, 0)
		}
		for size in [1023, 1024, 4095, 4096, 8192, 65536]! {
			for item in [GetCStringCase{'a'.repeat(size), 1, 'a'.repeat(size), false},
				GetCStringCase{'é😀'.repeat(size), 4, 'é😀'.repeat(size), false},
				GetCStringCase{'e\u0301'.repeat(size), 5, '\xe9'.repeat(size), false}] {
				object := a.string(cls, item.input)
				for capacity in [0, 1, item.expected.len, item.expected.len + 1, item.expected.len + 2]! {
					get_cstring_check(a, object, imp, item, capacity)
				}
				a.msg(object, c'release', 0, 0, 0)
			}
		}
		object := a.string(cls, 'Café')
		signature := a.msg(object, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && a.msg(signature, c'numberOfArguments', 0, 0, 0) == 5
		assert a.msg(signature, c'methodReturnLength', 0, 0, 0) == 1
		assert ctext(a.msg(signature, c'methodReturnType', 0, 0, 0)) == 'B'
		if unsafe { name.vstring() } == 'NSMutableString' {
			other := a.string(a.cls(c'NSString'), 'changed')
			a.msg(object, c'setString:', other, 0, 0)
			a.msg(other, c'release', 0, 0, 0)
			get_cstring_check(a, object, imp, GetCStringCase{'changed', 1, 'changed', false}, 8)
		}
		if !a.native {
			assert a.msg(object, c'getCString:maxLength:encoding:', 0, 0, 4) == 0
			mut buffer := [u8(0xa5), 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5]!
			assert a.msg(object, c'getCString:maxLength:encoding:', u64(unsafe { &buffer[0] }), ~u64(0), 4) == 1
			assert buffer[if unsafe { name.vstring() } == 'NSMutableString' { 7 } else { 5 }] == 0
		}
		a.msg(object, c'release', 0, 0, 0)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn get_cstring_worker(a, cls, imp) }
		for worker in workers { worker.wait() }
		unsafe { workers.free() }
	}
	a.drain(pool)
}
fn get_cstring_constants(a GetCStringApi) {
	pool := a.pool()
	text := 'é\x00😀'
	mut record := [a.cls(c'NSString'), u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] })
	ios_runtime.constants[address] = true
	imp := objc_method_imp(objc_instance_method(a.cls(c'NSString'), a.sel(c'getCString:maxLength:encoding:')))
	item := GetCStringCase{text, 4, text, false}
	get_cstring_check(a, address, imp, item, text.len + 1)
	wide := [u16(0xe9), 0, 0xd83d, 0xde00, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 4
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 10, prot: 1}]}
		layout: macho.Layout{size: 10}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	get_cstring_check(a, address, imp, item, text.len + 1)
	get_cstring_check(a, address, imp, GetCStringCase{text, 5, '', true}, text.len + 1)
	cache := ios_runtime.constant_utf8[address] or { panic('missing string cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cache.free() }
	ios_runtime.constants.delete(address)
	a.drain(pool)
}
fn test_string_get_cstring_native() {
	$if macos {
		api := GetCStringApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		get_cstring_shared(api)
		println('IOS-STRING-GET-CSTRING-NATIVE: UTF8, ASCII, Latin1, NUL, capacities, conversion failure, long inputs, metadata, IMP, mutation and eight workers PASS')
	}
}
fn test_string_get_cstring_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		api := GetCStringApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		get_cstring_shared(api)
		get_cstring_constants(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-STRING-GET-CSTRING: UTF8, ASCII, Latin1, NUL, capacities, conversion failure, long inputs, metadata, IMP, mutation, constants, eight workers and two balanced lifetimes PASS')
}
