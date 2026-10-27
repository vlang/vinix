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

type StringPathSend = fn (u64, u64, u64, u64, u64) u64
struct StringPathApi { native bool send u64 }
struct StringPathCase { input string expected string }
struct StringAppendPathCase { input string component string expected string nil_result bool }

fn (api StringPathApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api StringPathApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api StringPathApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { StringPathSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api StringPathApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api StringPathApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api StringPathApi) string(cls u64, text string) u64 {
	return api.message(api.message(cls, c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn (api StringPathApi) check(object u64, expected string) {
	assert object != 0
	assert api.message(object, c'isKindOfClass:', api.cls(c'NSString'), 0, 0) == 1
	// Contents and independence from subsequent mutable source changes are public contracts.
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
fn string_path_cases() []StringPathCase {
	return [
		StringPathCase{'', ''}, StringPathCase{'/', '/'},
		StringPathCase{'//', '/'}, StringPathCase{'////', '/'},
		StringPathCase{'a', 'a'}, StringPathCase{'a/', 'a'},
		StringPathCase{'/a///', 'a'}, StringPathCase{'a//b///', 'b'},
		StringPathCase{'.', '.'}, StringPathCase{'..', '..'},
		StringPathCase{'a/..', '..'}, StringPathCase{'a/.', '.'},
		StringPathCase{'~', '~'}, StringPathCase{'~/file', 'file'},
		StringPathCase{'\\a\\b', '\\a\\b'}, StringPathCase{'C:\\a\\b', 'C:\\a\\b'},
		StringPathCase{'https://host/a?b', 'a?b'},
		StringPathCase{'a/é😀', 'é😀'}, StringPathCase{'a/e\u0301', 'e\u0301'},
		StringPathCase{'a\x00/b', 'b'}, StringPathCase{'a/b\x00c', 'b\x00c'},
		StringPathCase{'\x00', '\x00'}, StringPathCase{'a/\x00/b', 'b'},
		StringPathCase{'a/∕b', '∕b'}, StringPathCase{'a/／b', '／b'},
		StringPathCase{'/prefix/' + 'é😀'.repeat(2048) + '///', 'é😀'.repeat(2048)},
		StringPathCase{'/'.repeat(4096), '/'},
	]
}
fn string_path_worker(api StringPathApi, cls u64, imp u64) {
	for _ in 0 .. 64 {
		pool := api.pool()
		object := api.string(cls, 'dir/name\x00é😀///')
		result := unsafe { StringPathSend(voidptr(imp))(object, api.sel(c'lastPathComponent'), 0, 0, 0) }
		api.message(result, c'retain', 0, 0, 0)
		api.message(object, c'release', 0, 0, 0)
		api.drain(pool)
		api.check(result, 'name\x00é😀')
		api.message(result, c'release', 0, 0, 0)
	}
}
fn string_path_shared(api StringPathApi) {
	pool := api.pool()
	for name in [c'NSString', c'NSMutableString']! {
		cls := api.cls(name)
		selector := api.sel(c'lastPathComponent')
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
		for item in string_path_cases() {
			object := api.string(cls, item.input)
			assert api.message(object, c'respondsToSelector:', selector, 0, 0) == 1
			result := api.message(object, c'lastPathComponent', 0, 0, 0)
			api.check(result, item.expected)
			api.check(unsafe { StringPathSend(voidptr(imp))(object, selector, 0, 0, 0) }, item.expected)
			api.check(api.message(result, c'lastPathComponent', 0, 0, 0), item.expected)
			api.message(object, c'release', 0, 0, 0)
		}
		object := api.string(cls, 'dir/e\u0301///')
		signature := api.message(object, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && api.message(signature, c'numberOfArguments', 0, 0, 0) == 2
		assert api.message(signature, c'methodReturnLength', 0, 0, 0) == 8
		assert ctext(api.message(signature, c'methodReturnType', 0, 0, 0)) == '@'
		result := api.message(object, c'lastPathComponent', 0, 0, 0)
		if unsafe { name.vstring() } == 'NSMutableString' {
			other := api.string(api.cls(c'NSString'), 'changed')
			api.message(object, c'setString:', other, 0, 0)
			api.message(other, c'release', 0, 0, 0)
		}
		api.message(object, c'release', 0, 0, 0)
		api.check(result, 'e\u0301')
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn string_path_worker(api, cls, imp) }
		for worker in workers { worker.wait() }
	}
	api.drain(pool)
}

fn string_append_path_cases() []StringAppendPathCase {
	return [
		StringAppendPathCase{'', '', '', false},
		StringAppendPathCase{'', '/', '/', false},
		StringAppendPathCase{'', '///b//c///', '/b/c', false},
		StringAppendPathCase{'/', '', '/', false},
		StringAppendPathCase{'////', '///', '/', false},
		StringAppendPathCase{'a', '', 'a', false},
		StringAppendPathCase{'a', '/', 'a', false},
		StringAppendPathCase{'a', 'b', 'a/b', false},
		StringAppendPathCase{'a', '/b', 'a/b', false},
		StringAppendPathCase{'a/', '/b//c///', 'a/b/c', false},
		StringAppendPathCase{'a//b///', '', 'a/b', false},
		StringAppendPathCase{'a//b///', '///c//d/', 'a/b/c/d', false},
		StringAppendPathCase{'/a///', '/b', '/a/b', false},
		StringAppendPathCase{'/', 'b', '/b', false},
		StringAppendPathCase{'//a//b', '//c', '/a/b/c', false},
		StringAppendPathCase{'.', '.', './.', false},
		StringAppendPathCase{'..', '../b', '../../b', false},
		StringAppendPathCase{'a/.', '..', 'a/./..', false},
		StringAppendPathCase{'a/..', '.', 'a/../.', false},
		StringAppendPathCase{'~', '~/file', '~/~/file', false},
		StringAppendPathCase{'\\a\\b', '\\c', '\\a\\b/\\c', false},
		StringAppendPathCase{'C:\\a\\b', 'D:\\c', 'C:\\a\\b/D:\\c', false},
		StringAppendPathCase{'https://host/a?b', '/c', 'https:/host/a?b/c', false},
		StringAppendPathCase{'a/é😀', 'e\u0301', 'a/é😀/e\u0301', false},
		StringAppendPathCase{'a/e\u0301', '/é😀', 'a/e\u0301/é😀', false},
		StringAppendPathCase{'a/∕b', '／c', 'a/∕b/／c', false},
		StringAppendPathCase{'a\x00/b', 'c', '', true},
		StringAppendPathCase{'a/b\x00c', '', '', true},
		StringAppendPathCase{'\x00', '/', '', true},
		StringAppendPathCase{'a', '\x00', '', true},
		StringAppendPathCase{'', 'b\x00c', '', true},
		StringAppendPathCase{'/prefix/' + 'é😀'.repeat(2048) + '///', '/b//c/', '/prefix/' + 'é😀'.repeat(2048) + '/b/c', false},
		StringAppendPathCase{'/'.repeat(65536), '/b//c/', '/b/c', false},
		StringAppendPathCase{'a', 'é😀'.repeat(65536), 'a/' + 'é😀'.repeat(65536), false},
	]
}

fn string_append_path_worker(api StringPathApi, cls u64, imp u64) {
	for _ in 0 .. 64 {
		pool := api.pool()
		object := api.string(cls, '//dir///e\u0301/')
		component := api.string(cls, '/é😀//name///')
		result := unsafe { StringPathSend(voidptr(imp))(object, api.sel(c'stringByAppendingPathComponent:'), component, 0, 0) }
		api.message(result, c'retain', 0, 0, 0)
		api.message(object, c'release', 0, 0, 0)
		api.message(component, c'release', 0, 0, 0)
		api.drain(pool)
		api.check(result, '/dir/e\u0301/é😀/name')
		api.message(result, c'release', 0, 0, 0)
	}
}

fn string_append_path_shared(api StringPathApi) {
	pool := api.pool()
	for name in [c'NSString', c'NSMutableString']! {
		cls := api.cls(name)
		selector := api.sel(c'stringByAppendingPathComponent:')
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@24@0:8@16'
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == '@24@0:8@16'
			assert objc_instance_method(read64(cls), selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0 && api.message(cls, c'respondsToSelector:', selector, 0, 0) == 0
		for item in string_append_path_cases() {
			object := api.string(cls, item.input)
			component := api.string(cls, item.component)
			assert api.message(object, c'respondsToSelector:', selector, 0, 0) == 1
			for result in [api.message(object, c'stringByAppendingPathComponent:', component, 0, 0),
				unsafe { StringPathSend(voidptr(imp))(object, selector, component, 0, 0) }]! {
				if item.nil_result { assert result == 0 } else { api.check(result, item.expected) }
			}
			api.message(object, c'release', 0, 0, 0)
			api.message(component, c'release', 0, 0, 0)
		}
		object := api.string(cls, 'dir/e\u0301///')
		component := api.string(cls, '//é😀///')
		signature := api.message(object, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && api.message(signature, c'numberOfArguments', 0, 0, 0) == 3
		assert api.message(signature, c'methodReturnLength', 0, 0, 0) == 8
		assert ctext(api.message(signature, c'methodReturnType', 0, 0, 0)) == '@'
		assert ctext(api.message(signature, c'getArgumentTypeAtIndex:', 2, 0, 0)) == '@'
		result := api.message(object, c'stringByAppendingPathComponent:', component, 0, 0)
		api.check(api.message(object, c'stringByAppendingPathComponent:', object, 0, 0), 'dir/e\u0301/dir/e\u0301')
		if unsafe { name.vstring() } == 'NSMutableString' {
			other := api.string(api.cls(c'NSString'), 'changed')
			api.message(object, c'setString:', other, 0, 0)
			api.message(component, c'setString:', other, 0, 0)
			api.message(other, c'release', 0, 0, 0)
		}
		api.message(object, c'release', 0, 0, 0)
		api.message(component, c'release', 0, 0, 0)
		api.check(result, 'dir/e\u0301/é😀')
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn string_append_path_worker(api, cls, imp) }
		for worker in workers { worker.wait() }
	}
	api.drain(pool)
}
fn string_path_constants(api StringPathApi) {
	pool := api.pool()
	text := 'a/e\u0301\x00😀///'
	mut record := [api.cls(c'NSString'), u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] })
	ios_runtime.constants[address] = true
	api.check(api.message(address, c'lastPathComponent', 0, 0, 0), 'e\u0301\x00😀')
	wide := [u16(0x61), 0x2f, 0x65, 0x301, 0, 0xd83d, 0xde00, 0x2f, 0x2f, 0x2f, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 10
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 22, prot: 1}]}
		layout: macho.Layout{size: 22}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	api.check(api.message(address, c'lastPathComponent', 0, 0, 0), 'e\u0301\x00😀')
	cache := ios_runtime.constant_utf8[address] or { panic('missing string cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cache.free() }
	ios_runtime.constants.delete(address)
	api.drain(pool)
}
fn test_string_path_native() {
	$if macos {
		api := StringPathApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		string_path_shared(api)
		string_append_path_shared(api)
		println('IOS-STRING-APPEND-PATH-NATIVE: separators, roots, dots, Unicode, NUL, long inputs, metadata, IMP, mutation, eight workers and pool drain PASS')
		println('IOS-STRING-PATH-NATIVE: components, root, separators, Unicode, NUL, metadata, IMP, mutation, lifetime and eight workers PASS')
	}
}
fn test_string_path_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		api := StringPathApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		string_path_shared(api)
		string_append_path_shared(api)
		string_path_constants(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-STRING-PATH: components, root, separators, Unicode, NUL, metadata, IMP, mutation, constants, eight workers and two balanced lifetimes PASS')
	println('IOS-STRING-APPEND-PATH: separators, roots, dots, Unicode, NUL, long inputs, metadata, IMP, mutation, eight workers and two balanced lifetimes PASS')
}
