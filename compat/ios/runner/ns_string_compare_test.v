// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <dlfcn.h>
	fn C.objc_getClass(&char) voidptr
	fn C.object_getClass(voidptr) voidptr
	fn C.sel_registerName(&char) voidptr
	fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
	fn C.class_getClassMethod(voidptr, voidptr) voidptr
	fn C.method_getTypeEncoding(voidptr) &char
	fn C.method_getImplementation(voidptr) voidptr
	fn C.dlsym(voidptr, &char) voidptr
}
type NSStringOrderSend = fn (u64, u64, u64, u64, u64) u64
type NSStringOrderImp = fn (u64, u64, u64) i64
struct NSStringOrderApi { native bool send u64 }
struct NSStringOrderCase { a string b string order i64 }

fn (api NSStringOrderApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api NSStringOrderApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api NSStringOrderApi) msg(object u64, selector &char, a u64, b u64, c u64) u64 {
	return unsafe { NSStringOrderSend(voidptr(api.send))(object, api.sel(selector), a, b, c) }
}
fn (api NSStringOrderApi) string(cls u64, text string) u64 {
	object := api.msg(api.msg(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
	assert object != 0
	return object
}
fn (api NSStringOrderApi) imp(object u64) u64 {
	$if macos { if api.native {
		method := C.class_getInstanceMethod(C.object_getClass(voidptr(object)), voidptr(api.sel(c'compare:')))
		assert method != unsafe { nil }
		return u64(C.method_getImplementation(method))
	} }
	return objc_method_imp(objc_instance_method(read64(object), api.sel(c'compare:')))
}
fn (api NSStringOrderApi) order(a u64, b u64) i64 { return i64(api.msg(a, c'compare:', b, 0, 0)) }

fn ns_order_cases() []NSStringOrderCase {
	return [NSStringOrderCase{'', '', 0}, NSStringOrderCase{'', 'a', -1},
		NSStringOrderCase{'a', 'ab', -1}, NSStringOrderCase{'A', 'a', -1},
		NSStringOrderCase{'10', '2', -1}, NSStringOrderCase{'1.10', '1.2', -1},
		NSStringOrderCase{'a\x00b', 'a\x00c', -1}, NSStringOrderCase{'a\x00', 'a', 1},
		NSStringOrderCase{'é', 'e\u0301', 0}, NSStringOrderCase{'é', 'f', -1},
		NSStringOrderCase{'é', 'e', 1}, NSStringOrderCase{'é', 'e\u0302', -1},
		NSStringOrderCase{'e\u0301x', 'éy', -1}, NSStringOrderCase{'é', 'e\u0301x', -1},
		NSStringOrderCase{'Å', 'Å', 0}, NSStringOrderCase{'각', '각', 0},
		NSStringOrderCase{'각', '각', 0}, NSStringOrderCase{'ﬁ', 'fi', 1},
		NSStringOrderCase{'😀', '\ue000', 1}, NSStringOrderCase{'Ａ', 'A', 1},
		NSStringOrderCase{'A\u0315\u0300', 'À\u0315', 0},
		NSStringOrderCase{'\u0301\u0327A', '\u0327\u0301A', 0},
		NSStringOrderCase{'\u0344', '\u0308\u0301', 0},
		NSStringOrderCase{'𝅗𝅥', '𝅗𝅥', 1}, NSStringOrderCase{'\U0001109a', '\U00011099\U000110ba', 1},
		NSStringOrderCase{'\U0002f800', '丽', 0}, NSStringOrderCase{'é각😀', 'e\u0301각😀', 0}]
}

fn ns_order_matrix(api NSStringOrderApi) []i64 {
	mut strings := []u64{}
	for text in ['', 'a', 'ab', 'A', '10', '2', 'é', 'e\u0301', 'e', 'f', 'e\u0302',
		'éx', 'e\u0301y', 'Å', 'Å', 'A\u030a', '가', '가', '각', '각', '각',
		'ﬁ', 'fi', '😀', '\ue000', 'a\x00b', 'a\x00c', 'A\u0315\u0300', 'À\u0315',
		'\u0301\u0327A', '\u0327\u0301A', 'Ａ', '\u0344', '\u0308\u0301',
		'𝅗𝅥', '𝅗𝅥', '\U0001109a', '\U00011099\U000110ba', '\U0002f800', '丽',
		'a\u0301\u0327', 'a\u0301\u0300', 'é𝅗𝅥', 'e\u0301𝅗𝅥',
		'\U00010000', '\U00010001', 'é\U00010000', 'e\u0301\U00010000',
		'a\u034f\u0301', 'a\u0301\u034f', 'a\u0301\u0327\u0300', 'a\u0301\u0300\u0327'] {
		strings << api.string(api.cls(c'NSString'), text)
	}
	mut result := []i64{cap: strings.len * strings.len}
	for a in strings { for b in strings { result << api.order(a, b) } }
	for object in strings { api.msg(object, c'release', 0, 0, 0) }
	unsafe { strings.free() }
	return result
}

fn ns_order_shared(api NSStringOrderApi) {
	for name in [c'NSString', c'NSMutableString']! {
		cls := api.cls(name)
		selector := api.sel(c'compare:')
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert ctext(u64(C.method_getTypeEncoding(method))) == 'q24@0:8@16'
			assert C.class_getClassMethod(voidptr(cls), voidptr(selector)) == unsafe { nil }
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == 'q24@0:8@16'
			assert objc_instance_method(read64(cls), selector) == 0
		}
		assert api.msg(cls, c'respondsToSelector:', selector, 0, 0) == 0
		for item in ns_order_cases() {
			a := api.string(cls, item.a); b := api.string(cls, item.b)
			assert api.msg(a, c'respondsToSelector:', selector, 0, 0) == 1
			forward := api.order(a, b); reverse := api.order(b, a)
			assert forward == item.order && reverse == -item.order, '${item.a.bytes()} / ${item.b.bytes()}: ${forward}, ${reverse}, expected ${item.order}; native=${api.native}'
			assert api.order(a, a) == 0
			imp := api.imp(a)
			assert imp != 0 && unsafe { NSStringOrderImp(voidptr(imp))(a, selector, b) } == item.order
			api.msg(a, c'release', 0, 0, 0); api.msg(b, c'release', 0, 0, 0)
		}
		a := api.string(cls, 'e\u0301'); b := api.string(api.cls(c'NSString'), 'é')
		assert api.order(a, b) == 0
		if unsafe { name.vstring() } == 'NSMutableString' {
			other := api.string(api.cls(c'NSString'), 'f')
			api.msg(a, c'setString:', other, 0, 0)
			assert api.order(a, b) == 1
			api.msg(other, c'release', 0, 0, 0)
		}
		api.msg(a, c'release', 0, 0, 0); api.msg(b, c'release', 0, 0, 0)
	}
}

fn ns_order_worker(object u64, other u64, original u64, writer bool) {
	api := NSStringOrderApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for i in 0 .. 128 {
		if writer { api.msg(object, c'setString:', if i % 2 == 0 { original } else { other }, 0, 0) }
		else {
			assert (ns_string_compare(object, object) or { panic(err) }) == 0
			assert (ns_string_compare(object, other) or { panic(err) }) in [i64(-1), 0]!
		}
	}
}

fn ns_order_constants(api NSStringOrderApi) {
	text := 'e\u0301\x00😀'
	mut record := [api.cls(c'NSString'), u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] })
	ios_runtime.constants[address] = true
	other := owned_string('é\x00😀')
	assert api.order(address, other) == 0
	wide := [u16(0x65), 0x301, 0, 0xd83d, 0xde00, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 5
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 12, prot: 1}]}
		layout: macho.Layout{size: 12} base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	assert api.order(address, other) == 0
	cache := ios_runtime.constant_utf8[address] or { panic('missing decoded constant') }
	ios_runtime.constant_utf8.delete(address); unsafe { cache.free() }
	ios_runtime.constants.delete(address); objc_release(other)
}

fn test_ns_string_compare() {
	mut native_orders := []i64{}
	$if macos {
		api := NSStringOrderApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		pool := api.msg(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0)
		ns_order_shared(api)
		native_orders = ns_order_matrix(api)
		api.msg(pool, c'drain', 0, 0, 0)
		println('IOS-STRING-COMPARE-NATIVE: canonical scalar ordering, case, prefixes, NUL, Hangul, metadata, concrete IMP and mutation PASS')
	}
	for _ in 0 .. 2 {
		objc_start()
		api := NSStringOrderApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		pool := objc_pool_push()
		ns_order_shared(api); ns_order_constants(api)
		orders := ns_order_matrix(api)
		if native_orders.len != 0 {
			assert orders.len == native_orders.len
			for i, order in orders { assert order == native_orders[i], 'matrix index ${i}: ${order}, expected ${native_orders[i]}' }
		}
		unsafe { orders.free() }
		object := api.string(api.cls(c'NSMutableString'), 'e\u0301'); other := owned_string('f')
		original := owned_string('é')
		before := ios_runtime.live; refs := obj_header(object).refs
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn ns_order_worker(object, other, original, i == 0) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == before && obj_header(object).refs == refs
		signature := api.msg(object, c'methodSignatureForSelector:', u64(c'compare:'), 0, 0)
		assert signature != 0 && api.msg(signature, c'numberOfArguments', 0, 0, 0) == 3
		assert api.msg(signature, c'methodReturnLength', 0, 0, 0) == 8
		assert ctext(api.msg(signature, c'methodReturnType', 0, 0, 0)) == 'q'
		assert api.msg(object, c'respondsToSelector:', u64(c'compare:options:'), 0, 0) == 0
		for invalid in [u64(0), u64(1), ios_runtime.names['NSString'], objc_new(ios_runtime.names['NSObject'])]! {
			if _ := ns_string_compare(object, invalid) { assert false }
			if invalid in ios_runtime.objects { objc_release(invalid) }
		}
		bad := owned_string('valid'); unsafe { *(&u8(obj_header(bad).text)) = 0xff }
		if _ := ns_string_compare(bad, other) { assert false }
		objc_release(bad); objc_release(object); objc_release(other); objc_release(original)
		objc_pool_pop(pool)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	unsafe { native_orders.free() }
	println('IOS-STRING-COMPARE: canonical scalar order, signed ABI, concrete IMP, mutation, constants, rejected invalid inputs, eight workers and two drained runtimes PASS')
}
