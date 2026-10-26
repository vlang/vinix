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

type NormalizationSend = fn (u64, u64, u64, u64, u64) u64
struct NormalizationApi { native bool send u64 }
struct NormalizationCase { input string expected string }

fn (api NormalizationApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api NormalizationApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api NormalizationApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { NormalizationSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api NormalizationApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api NormalizationApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api NormalizationApi) string(cls u64, text string) u64 {
	return api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn (api NormalizationApi) check(object u64, expected string) {
	assert object != 0
	assert api.message(object, c'isKindOfClass:', api.cls(c'NSString'), 0, 0) == 1
	// Foundation may return a private mutable subclass; the public contract is
	// its normalized contents and independence from subsequent source mutation.
	if !api.native { assert api.message(object, c'isKindOfClass:', api.cls(c'NSMutableString'), 0, 0) == 0 }
	length := api.message(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0)
	assert length == u64(expected.len)
	bytes := api.message(object, c'UTF8String', 0, 0, 0)
	assert bytes != 0
	assert unsafe { (&char(voidptr(bytes))).vstring_with_len(int(length)) } == expected
	mut units := u64(0)
	for scalar in expected.runes() { units += if scalar > 0xffff { u64(2) } else { u64(1) } }
	assert api.message(object, c'length', 0, 0, 0) == units
}
fn normalization_cases() []NormalizationCase {
	return [
		NormalizationCase{'', ''}, NormalizationCase{'ASCII', 'ASCII'},
		NormalizationCase{'Cafe\u0301', 'Café'},
		NormalizationCase{'A\u0315\u0300', 'À\u0315'},
		NormalizationCase{'\u0301\u0327A', '\u0327\u0301A'},
		NormalizationCase{'A\u0305\u0301', 'A\u0305\u0301'},
		NormalizationCase{'\u0344', '\u0308\u0301'},
		NormalizationCase{'Å', 'Å'},
		NormalizationCase{'각', '각'},
		NormalizationCase{'𝅗𝅥', '𝅗𝅥'},
		NormalizationCase{'e\u0301\x00a\u030a😀', 'é\x00å😀'},
		NormalizationCase{'ﬁＡ①', 'ﬁＡ①'}, NormalizationCase{'é각😀', 'é각😀'},
	]
}
fn normalization_worker(api NormalizationApi, cls u64, imp u64) {
	for _ in 0 .. 64 {
		pool := api.pool()
		object := api.string(cls, 'A\u0315\u0300\x00가😀')
		result := unsafe { NormalizationSend(voidptr(imp))(object, api.sel(c'precomposedStringWithCanonicalMapping'), 0, 0, 0) }
		api.message(result, c'retain', 0, 0, 0)
		api.message(object, c'release', 0, 0, 0)
		api.drain(pool)
		api.check(result, 'À\u0315\x00가😀')
		api.message(result, c'release', 0, 0, 0)
	}
}
fn normalization_shared(api NormalizationApi) {
	pool := api.pool()
	for name in [c'NSString', c'NSMutableString']! {
		cls := api.cls(name)
		selector := api.sel(c'precomposedStringWithCanonicalMapping')
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8'
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
			assert objc_instance_method(read64(cls), selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0 && api.message(cls, c'respondsToSelector:', selector, 0, 0) == 0
		for item in normalization_cases() {
			object := api.string(cls, item.input)
			assert api.message(object, c'respondsToSelector:', selector, 0, 0) == 1
			result := api.message(object, c'precomposedStringWithCanonicalMapping', 0, 0, 0)
			api.check(result, item.expected)
			api.check(unsafe { NormalizationSend(voidptr(imp))(object, selector, 0, 0, 0) }, item.expected)
			api.check(api.message(result, c'precomposedStringWithCanonicalMapping', 0, 0, 0), item.expected)
			api.message(object, c'release', 0, 0, 0)
		}
		// The host Foundation fast path leaves an already composed Hangul LV
		// followed by T unchanged. Keep its observed result separate from the
		// runtime's complete NFC composition (also used by Swift strings).
		hangul_source := api.string(cls, '각')
		hangul_expected := if api.native { '각' } else { '각' }
		api.check(api.message(hangul_source, c'precomposedStringWithCanonicalMapping', 0, 0, 0), hangul_expected)
		api.check(unsafe { NormalizationSend(voidptr(imp))(hangul_source, selector, 0, 0, 0) }, hangul_expected)
		api.message(hangul_source, c'release', 0, 0, 0)
		object := api.string(cls, 'e\u0301')
		signature := api.message(object, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && api.message(signature, c'numberOfArguments', 0, 0, 0) == 2
		assert api.message(signature, c'methodReturnLength', 0, 0, 0) == 8
		assert ctext(api.message(signature, c'methodReturnType', 0, 0, 0)) == '@'
		result := api.message(object, c'precomposedStringWithCanonicalMapping', 0, 0, 0)
		if unsafe { name.vstring() } == 'NSMutableString' {
			other := api.string(api.cls(c'NSString'), 'changed')
			api.message(object, c'setString:', other, 0, 0)
			api.message(other, c'release', 0, 0, 0)
		}
		api.message(object, c'release', 0, 0, 0)
		api.check(result, 'é')
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn normalization_worker(api, cls, imp) }
		for worker in workers { worker.wait() }
	}
	api.drain(pool)
}
fn normalization_constants(api NormalizationApi) {
	pool := api.pool()
	text := 'e\u0301\x00😀'
	mut record := [api.cls(c'NSString'), u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] })
	ios_runtime.constants[address] = true
	api.check(api.message(address, c'precomposedStringWithCanonicalMapping', 0, 0, 0), 'é\x00😀')
	wide := [u16(0x65), 0x301, 0, 0xd83d, 0xde00, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 5
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 12, prot: 1}]}
		layout: macho.Layout{size: 12}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	api.check(api.message(address, c'precomposedStringWithCanonicalMapping', 0, 0, 0), 'é\x00😀')
	cache := ios_runtime.constant_utf8[address] or { panic('missing string cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cache.free() }
	ios_runtime.constants.delete(address)
	api.drain(pool)
}
fn test_string_normalization_native() {
	$if macos {
		api := NormalizationApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		normalization_shared(api)
		println('IOS-STRING-NORMALIZATION-NATIVE: NFC, Hangul, exclusions, NUL, metadata, IMP, mutation, lifetime and eight workers PASS')
	}
}
fn test_string_normalization_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		api := NormalizationApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		normalization_shared(api)
		normalization_constants(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-STRING-NORMALIZATION: NFC, Hangul, exclusions, NUL, metadata, IMP, mutation, constants, eight workers and two balanced lifetimes PASS')
}
