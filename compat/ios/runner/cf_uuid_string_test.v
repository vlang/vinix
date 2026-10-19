// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

$if macos {
	#include <CoreFoundation/CFUUID.h>
	@[typedef]
	struct C.CFUUIDBytes {
		byte0 u8 byte1 u8 byte2 u8 byte3 u8 byte4 u8 byte5 u8 byte6 u8 byte7 u8
		byte8 u8 byte9 u8 byte10 u8 byte11 u8 byte12 u8 byte13 u8 byte14 u8 byte15 u8
	}
	fn C.CFUUIDCreateFromString(voidptr, voidptr) voidptr
	fn C.CFUUIDGetUUIDBytes(voidptr) C.CFUUIDBytes
	fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
	fn C.CFAllocatorGetDefault() voidptr
}

type UUIDStringCall = fn (u64, u64) u64
type UUIDStringProbe = fn (u64, u64, u64, u64, u64, &u64)

struct UUIDStringCase {
	text string
	hex string
}

fn uuid_string_cases() []UUIDStringCase {
	c := '00010203-0405-0607-0809-0A0B0C0D0E0F'
	h := '000102030405060708090a0b0c0d0e0f'
	z := '00000000000000000000000000000000'
	t := '000102030405060708090a0b0c0d0e00'
	return [UUIDStringCase{'', 'nil'}, UUIDStringCase{'a', z}, UUIDStringCase{c, h},
		UUIDStringCase{c.to_lower(), h}, UUIDStringCase{'00000000-0000-0000-0000-000000000000', z},
		UUIDStringCase{'000102030405060708090A0B0C0D0E0F', '000102034050070890a00c0d0e0f0000'},
		UUIDStringCase{'{' + c + '}', h}, UUIDStringCase{'urn:uuid:' + c, '00000102000400060008000a0b0c0d0e'},
		UUIDStringCase{'zz' + c, h}, UUIDStringCase{'D' + c, 'd000102000400060008000a0b0c0d0e0'},
		UUIDStringCase{c + 'trailing', h}, UUIDStringCase{'\x00' + c, h},
		UUIDStringCase{'00010203_0405_0607_0809_0A0B0C0D0E0F', h},
		UUIDStringCase{'00010203G0405G0607G0809G0A0B0C0D0E0F', h},
		UUIDStringCase{'0G010203-0405-0607-0809-0A0B0C0D0E0F', h},
		UUIDStringCase{'00GG0203-0405-0607-0809-0A0B0C0D0E0F', '000002030405060708090a0b0c0d0e0f'},
		UUIDStringCase{'00\x000203-0405-0607-0809-0A0B0C0D0E0F', '00002000400060008000a0b0c0d0e000'},
		UUIDStringCase{'0π010203-0405-0607-0809-0A0B0C0D0E0F', h},
		UUIDStringCase{'π' + c, h}, UUIDStringCase{'🎮' + c, h},
		UUIDStringCase{c[..35], t}, UUIDStringCase{c[..34], t},
		UUIDStringCase{'x'.repeat(64) + c, h}, UUIDStringCase{'x'.repeat(65) + c, t},
		UUIDStringCase{'x'.repeat(100) + c, z}, UUIDStringCase{'🎮'.repeat(32) + c, h},
		UUIDStringCase{'🎮'.repeat(33) + c, t}, UUIDStringCase{c + 'x'.repeat(200), h},
		UUIDStringCase{'zzzz', z}, UUIDStringCase{'F', z},
		UUIDStringCase{'FA', 'fa000000000000000000000000000000'}, UUIDStringCase{'FG', z},
		UUIDStringCase{'1G', z}, UUIDStringCase{'G1', z},
		UUIDStringCase{'AF', 'af000000000000000000000000000000'}, UUIDStringCase{'AG', z},
		UUIDStringCase{'A\x00', z}, UUIDStringCase{'Aπ', z}, UUIDStringCase{'AŁ', z},
		UUIDStringCase{'Ł' + c, h}, UUIDStringCase{'00010203π0405π0607π0809π0A0B0C0D0E0F', h},
		UUIDStringCase{'  ' + c + '  ', h}]
}

fn uuid_string_emit(code u64) {
	// Allocator/string in x0/x1; protected x2–x8, preserved x20/x21.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0303e4, 0xaa0303e5,
		0xaa0303e6, 0xaa0303e7, 0xaa0303e8, 0xaa0303f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn uuid_string_raw(entry u64, allocator u64, text u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { UUIDStringProbe(voidptr(code))(entry, allocator, text, guard, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn uuid_string_native(allocator u64, text u64) u64 {
	$if macos { return u64(C.CFUUIDCreateFromString(voidptr(allocator), voidptr(text))) }
	return 0
}

fn uuid_string_cases_run(entry u64, allocator u64, code u64, guard u64, native bool) {
	cases := uuid_string_cases()
	for i, item in cases {
		mut text := u64(0)
		if native {
			$if macos { text = u64(C.CFStringCreateWithBytes(unsafe { nil }, item.text.str, item.text.len, 0x08000100, false)) }
		} else { text = owned_string(item.text) }
		assert text != 0
		object := uuid_string_raw(entry, if i & 1 == 0 { u64(0) } else { allocator }, text, code, guard)
		if item.hex == 'nil' { assert object == 0 } else {
			assert object != 0
			mut bytes := [16]u8{}
			if native {
				$if macos { raw := C.CFUUIDGetUUIDBytes(voidptr(object)); unsafe { C.memcpy(&bytes[0], &raw, 16) } }
			} else {
				header := obj_header(object)
				assert header.refs == 1 && !header.uuid_owned && header.cls == ios_runtime.names['VinixCFUUID']
				unsafe { C.memcpy(&bytes[0], &header.uuid_bytes[0], 16) }
			}
			actual := bytes[..].hex(); assert actual == item.hex, 'case ' + i.str() + ': ' + actual
			unsafe { actual.free() }
			if native { $if macos { C.CFRelease(voidptr(object)) } } else { objc_release(object) }
		}
		if native { $if macos { C.CFRelease(voidptr(text)) } } else { assert obj_header(text).refs == 1; objc_release(text) }
	}
	unsafe { cases.free() }
}

fn uuid_string_constants(entry u64, code u64, guard u64) {
	text := '🎮00010203-0405-0607-0809-0A0B0C0D0E0F'
	mut record := [ios_runtime.names['NSString'], u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] }); ios_runtime.constants[address] = true
	first := uuid_string_raw(entry, 0, address, code, guard)
	mut wide := [40]u16{}
	wide[0] = 0xd83c; wide[1] = 0xdfae
	for i, byte in text[4..] { wide[i + 2] = u16(byte) }
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 38
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 80, prot: 1}]}
		layout: macho.Layout{size: 80}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	second := uuid_string_raw(entry, 0, address, code, guard)
	assert object_equal(first, second) && cf_hash(first) == cf_hash(second)
	cached := ios_runtime.constant_utf8[address] or { panic('missing UTF-16 constant cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cached.free() }
	if _ := cf_uuid_create_from_string_checked(0, address) { assert false }
	record[1] = 0x1234
	if _ := cf_uuid_create_from_string_checked(0, address) { assert false }
	record[1] = 0x7c8; record[2] = 0
	if _ := cf_uuid_create_from_string_checked(0, address) { assert false }
	record[2] = guard; record[3] = 16777217
	if _ := cf_uuid_create_from_string_checked(0, address) { assert false }
	record[3] = 0
	assert uuid_string_raw(entry, 0, address, code, guard) == 0
	ios_runtime.constants.delete(address); objc_release(first); objc_release(second)
}

fn uuid_string_rejections(guard u64, allocator u64) {
	text := owned_string('FA')
	other := objc_allocate(ios_runtime.names['NSObject'])
	stale := owned_string('freed'); objc_release(stale)
	baseline := ios_runtime.live
	for invalid in [u64(0), 1, guard, ios_runtime.names['NSString'], other, stale]! {
		if _ := cf_uuid_create_from_string_checked(0, invalid) { assert false }
	}
	for invalid in [u64(1), guard, allocator, ios_runtime.names['NSObject']]! {
		if _ := cf_uuid_create_from_string_checked(invalid, text) { assert false }
	}
	for invalid in ['\xff', '\xc0\x80', '\x80', '\xf0\x90', '\xed\xa0\x80', '\xf4\x90\x80\x80']! {
		input := owned_string(invalid)
		if _ := cf_uuid_create_from_string_checked(0, input) { assert false }
		objc_release(input)
	}
	mut header := obj_header(text)
	for length in [-1, 16777217]! {
		header.text_length = length
		if _ := cf_uuid_create_from_string_checked(0, text) { assert false }
	}
	header.text_length = 2
	pointer := header.text; header.text = unsafe { nil }
	if _ := cf_uuid_create_from_string_checked(0, text) { assert false }
	header.text = pointer
	assert ios_runtime.live == baseline && obj_header(text).refs == 1
	objc_release(text); objc_release(other)
}

fn uuid_string_lifetime(entry u64, code u64, guard u64) {
	pool := objc_pool_push()
	text := owned_string('00010203-0405-0607-0809-0A0B0C0D0E0F')
	first := uuid_string_raw(entry, 0, text, code, guard)
	unsafe { *(&u8(obj_header(text).text)) = `F` }; objc_release(text)
	lower := owned_string('00010203-0405-0607-0809-0a0b0c0d0e0f')
	second := uuid_string_raw(entry, 0, lower, code, guard); objc_release(lower)
	assert first != second && object_equal(first, second) && cf_hash(first) == cf_hash(second)
	objc_pool_pop(pool)
	assert obj_header(first).refs == 1 && obj_header(second).refs == 1
	assert objc_retain(first) == first && obj_header(first).refs == 2; objc_release(first)
	other_text := owned_string('FF010203-0405-0607-0809-0A0B0C0D0E0F')
	other := uuid_string_raw(entry, 0, other_text, code, guard); objc_release(other_text)
	assert !object_equal(first, other)
	ns := objc_allocate(ios_runtime.names['NSUUID'])
	unsafe { C.memcpy(&obj_header(ns).uuid_bytes[0], &obj_header(first).uuid_bytes[0], 16) }
	assert !object_equal(first, ns) && !object_equal(ns, first); objc_release(ns)
	dictionary := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	cf_dictionary_set(dictionary, first, other)
	assert cf_dictionary_value(dictionary, second) == other
	cf_dictionary_set(dictionary, second, first)
	assert obj_header(dictionary).items.len == 1 && cf_dictionary_value(dictionary, second) == first
	mut weak := u64(0); objc_store_weak(unsafe { &weak }, first)
	objc_release(first); objc_release(second); objc_release(other)
	assert weak != 0
	objc_release(dictionary); assert weak == 0
}

fn uuid_string_worker(call UUIDStringCall, allocator u64, text u64) {
	for _ in 0 .. 200 {
		object := call(allocator, text)
		header := obj_header(object)
		assert header.refs == 1 && header.uuid_bytes[0] == 0xfa && header.uuid_bytes[1] == 0
		assert header.uuid_bytes[6] == 0 && header.uuid_bytes[8] == 0
		objc_release(object)
	}
}

fn test_cf_uuid_string() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }; defer { assert C.munmap(code, page * 2) == 0 }
	uuid_string_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		uuid_string_cases_run(u64(unsafe { voidptr(uuid_string_native) }), u64(C.CFAllocatorGetDefault()), u64(code), guard, true)
		println('NATIVE-CF-UUID-STRING: 42 parsing cases, 100 UTF-16 unit limit, prefixes, ignored separator slots, invalid/incomplete pairs, preserved bits, nil empty input and protected unused registers')
	}
	if _ := cf_uuid_create_from_string_checked(0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
		entry := runtime_symbol(lib, '_CFUUIDCreateFromString') or { panic(err) }
		call := unsafe { UUIDStringCall(voidptr(entry)) }
		allocator := read64(runtime_symbol(lib, '_kCFAllocatorSystemDefault') or { panic(err) })
		null_allocator := read64(runtime_symbol(lib, '_kCFAllocatorNull') or { panic(err) })
		baseline := ios_runtime.live
		uuid_string_cases_run(entry, allocator, u64(code), guard, false)
		uuid_string_constants(entry, u64(code), guard)
		uuid_string_rejections(guard, null_allocator)
		uuid_string_lifetime(entry, u64(code), guard)
		assert ios_runtime.live == baseline && objc_pool().objects.len == 0
		text := owned_string('FA')
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn uuid_string_worker(call, if i & 1 == 0 { u64(0) } else { allocator }, text) }
		workers.wait(); unsafe { workers.free() }
		assert obj_header(text).refs == 1 && ios_runtime.live == baseline + 1
		objc_release(text)
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFUUIDCreateFromString') { assert false }
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_concurrency_retired
		if _ := cf_uuid_create_from_string_checked(0, 0) { assert false }
	}
	println('IOS-CF-UUID-STRING: scoped two-pointer owned ABI, protected x2–x8 and preserved x20/x21, 42 native-matched parsing cases, UTF-8/UTF-16 constants, explicit input/allocator rejection, value equality/hash, collection/weak lifetime, source independence, eight concurrent readers, balanced references, no autoreleases and two zero-live-object teardowns')
}
