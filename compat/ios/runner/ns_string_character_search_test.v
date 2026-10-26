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
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

struct CharacterSearchRange { location u64 length u64 }
type CharacterSearchSend = fn (u64, u64, u64, u64) u64
type CharacterSearchBytes = fn (u64, u64, u64, u64, u64) u64
type CharacterSearchCall = fn (u64, u64, u64) CharacterSearchRange

struct CharacterSearchApi { native bool entry u64 }

fn (api CharacterSearchApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}

fn (api CharacterSearchApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}

fn (api CharacterSearchApi) send(object u64, name &char, a u64, b u64) u64 {
	return unsafe { CharacterSearchSend(voidptr(api.entry))(object, api.selector(name), a, b) }
}

fn (api CharacterSearchApi) string(text string, mutable bool) u64 {
	object := api.send(api.cls(if mutable { 'NSMutableString' } else { 'NSString' }), c'alloc', 0, 0)
	return unsafe { CharacterSearchBytes(voidptr(api.entry))(object, api.selector(c'initWithBytes:length:encoding:'), u64(text.str), u64(text.len), 4) }
}

fn (api CharacterSearchApi) range(object u64, set u64) CharacterSearchRange {
	return unsafe { CharacterSearchCall(voidptr(api.entry))(object, api.selector(c'rangeOfCharacterFromSet:'), set) }
}

fn (api CharacterSearchApi) check(object u64, set u64, location u64, length u64) {
	actual := api.range(object, set)
	assert actual.location == location && actual.length == length, 'native=${api.native} text=' + ctext(api.send(object, c'UTF8String', 0, 0)) + ' ${actual.location},${actual.length} != ${location},${length}'
}

// Public range factories remain unsupported in the compatibility runtime. Use
// its existing bitmap constructor to compare full-domain searches to Apple.
fn (api CharacterSearchApi) set(point u32) u64 {
	$if macos {
		if api.native { return api.send(api.cls('NSCharacterSet'), c'characterSetWithRange:', point, 1) }
	}
	bits := ns_character_set_bitmap()
	ns_character_set_set_range(bits, point, 1, true)
	object := ns_character_set_create(api.cls('NSCharacterSet'), bits)
	C.free(bits)
	return api.send(object, c'autorelease', 0, 0)
}

fn character_search_shared(api CharacterSearchApi) {
	for name in ['NSString', 'NSMutableString']! {
		mut types := ''
		$if macos {
			if api.native {
				method := C.class_getInstanceMethod(voidptr(api.cls(name)), voidptr(api.selector(c'rangeOfCharacterFromSet:')))
				assert method != unsafe { nil }
				types = unsafe { C.method_getTypeEncoding(method).vstring() }
			}
		}
		if !api.native {
			method := objc_instance_method(api.cls(name), u64(c'rangeOfCharacterFromSet:'))
			assert method != 0
			types = ctext(u64(objc_method_types(method)))
		}
		assert types == '{_NSRange=QQ}24@0:8@16'
	}
	texts := ['', 'abc', 'A\x00π', 'a🎮π', '😀🎮π', 'é', '🎮🎮', '\U0010ffff']!
	points := [u32(0), 0x61, 0x3c0, 0x301, 0xd83c, 0xdfae, 0xd83d, 0xde00, 0x1f3ae, 0x1f600, 0x10ffff]!
	// Independent expected positions from the Apple oracle, in UTF-16 units.
	locations := [
		[-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]!,
		[-1, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1]!,
		[1, -1, 2, -1, -1, -1, -1, -1, -1, -1, -1]!,
		[-1, 0, 3, -1, -1, -1, -1, -1, 1, -1, -1]!,
		[-1, -1, 4, -1, -1, -1, -1, -1, 2, 0, -1]!,
		[-1, -1, -1, 1, -1, -1, -1, -1, -1, -1, -1]!,
		[-1, -1, -1, -1, -1, -1, -1, -1, 0, -1, -1]!,
		[-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0]!,
	]!
	for i, text in texts {
		for mutable in [false, true]! {
			object := api.string(text, mutable)
			for j, point in points {
				expected := locations[i][j]
				api.check(object, api.set(point), if expected < 0 { u64(0x7fffffffffffffff) } else { u64(expected) }, if expected < 0 { u64(0) } else if point > 0xffff { u64(2) } else { u64(1) })
			}
			api.send(object, c'release', 0, 0)
		}
	}
	object := api.string('A🎮π', true)
	set_text := api.string('πA', false)
	set := api.send(api.cls('NSMutableCharacterSet'), c'characterSetWithCharactersInString:', set_text, 0)
	api.check(object, set, 0, 1)
	api.send(set, c'removeCharactersInString:', set_text, 0)
	api.check(object, set, 0x7fffffffffffffff, 0)
	api.check(object, api.send(set, c'invertedSet', 0, 0), 0, 1)
	api.send(set, c'addCharactersInString:', set_text, 0)
	api.send(object, c'setString:', set_text, 0)
	api.check(object, set, 0, 1)
	api.send(object, c'release', 0, 0)
	api.send(set_text, c'release', 0, 0)
	api.check(0, set, 0, 0) // objc_msgSend nil clears both result registers.
}

fn character_search_constants(api CharacterSearchApi) {
	text := 'A\x00🎮π'
	mut record := [api.cls('NSString'), u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] })
	ios_runtime.constants[address] = true
	api.check(address, api.set(0), 1, 1)
	api.check(address, api.set(0x1f3ae), 2, 2)
	api.check(address, api.set(0x3c0), 4, 1)
	wide := [u16(0x41), 0, 0xd83c, 0xdfae, 0x3c0, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 5
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 12, prot: 1}]}
		layout: macho.Layout{size: 12}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	api.check(address, api.set(0x3c0), 4, 1)
	api.check(address, api.set(0x1f3ae), 2, 2)
	cache := ios_runtime.constant_utf8[address] or { panic('missing string cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cache.free() }
	record[1] = 0x7c8; record[2] = 0; record[3] = 0
	api.check(address, api.set(0), 0x7fffffffffffffff, 0)
	ios_runtime.constants.delete(address)
}

fn test_character_search_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		api := CharacterSearchApi{false, u64(voidptr(C.ios_objc_msgsend))}
		character_search_shared(api)
		character_search_constants(api)
		// Exercise the accepted byte limit and a match after a long prefix.
		text := 'a'.repeat(16777215) + 'z'
		object := owned_string(text)
		api.check(object, api.set(0x7a), 16777215, 1)
		objc_release(object)
		unsafe { text.free() }
		objc_pool_pop(pool)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-STRING-CHARACTER-SEARCH: UTF16 range ABI, full Unicode/NUL/combining input, first match, mutable inputs, nil receiver, image UTF8/UTF16 constants, 16MiB boundary and two drained runtimes')
}

fn test_character_search_native() {
	$if macos {
		api := CharacterSearchApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.entry != 0
		pool := api.send(api.cls('NSAutoreleasePool'), c'new', 0, 0)
		character_search_shared(api)
		api.send(pool, c'drain', 0, 0)
		println('IOS-STRING-CHARACTER-SEARCH-NATIVE: identical metadata and 176 Unicode searches plus mutable sets/strings and nil receiver')
	}
}

fn test_character_search_rejections() {
	objc_start()
	api := CharacterSearchApi{false, u64(voidptr(C.ios_objc_msgsend))}
	modes := ['receiver-nil', 'receiver-unknown', 'receiver-class', 'receiver-type', 'receiver-custom',
		'receiver-isa', 'receiver-raw', 'receiver-dead', 'receiver-destroying', 'receiver-utf8', 'receiver-limit',
		'constant-flags', 'constant-cache', 'constant-null', 'constant-limit', 'constant-utf8',
		'set-nil', 'set-unknown', 'set-class', 'set-type', 'set-raw', 'set-isa', 'set-dead']!
	for mode in modes {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			mut object := owned_string('valid')
			mut set := api.set(0x61)
			mut record := [api.cls('NSString'), u64(0x7c8), u64(c'valid'), u64(5)]!
			bad_utf8 := [u8(0xff)]!
			if mode.starts_with('constant-') {
				object = u64(unsafe { &record[0] }); ios_runtime.constants[object] = true
			}
			match mode {
				'receiver-nil' { object = 0 }
				'receiver-unknown' { object = 1 }
				'receiver-class' { object = api.cls('NSString') }
				'receiver-type' { object = objc_new(api.cls('NSObject')) }
				'receiver-custom' {
					cls := objc_allocate_class(api.cls('NSString'), c'UnsupportedSearchString', 0)
					objc_register_class(cls); object = objc_allocate(cls)
				}
				'receiver-isa' { objc_set_class(object, api.cls('NSObject')) }
				'receiver-raw' { object = objc_allocate(api.cls('NSMutableString')) }
				'receiver-dead' { objc_release(object) }
				'receiver-destroying' { obj_header(object).destroying = true }
				'receiver-utf8' { object = owned_string('\xed\xa0\x80') }
				'receiver-limit' { obj_header(object).text_length = 16777217 }
				'constant-flags' { record[1] = 0x1234 }
				'constant-cache' { record[1] = 0x7d0 }
				'constant-null' { record[2] = 0 }
				'constant-limit' { record[2] = 1; record[3] = 16777217 }
				'constant-utf8' { record[2] = u64(unsafe { &bad_utf8[0] }); record[3] = 1 }
				'set-nil' { set = 0 }
				'set-unknown' { set = 1 }
				'set-class' { set = api.cls('NSCharacterSet') }
				'set-type' { set = object }
				'set-raw' { set = objc_allocate(api.cls('NSCharacterSet')) }
				'set-isa' { objc_set_class(set, api.cls('NSObject')) }
				'set-dead' { set = objc_new(api.cls('NSCharacterSet')); objc_release(set) }
				else {}
			}
			// Direct checked entry exercises unknown pointers without dispatch's
			// general Objective-C requirement that the receiver have a valid isa.
			mut frame := RegisterFrame{}
			ns_string_character_search(object, set, mut frame)
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0; length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-STRING-CHARACTER-SEARCH-REJECT: ${modes.len} invalid receiver, constant, UTF8, size and character set inputs fail explicitly')
}
