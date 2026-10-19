// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

$if macos {
	#include <CoreFoundation/CFString.h>
	fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
	fn C.CFStringCompare(voidptr, voidptr, u64) i64
}

type StringCompareCall = fn (u64, u64, u64) i64
type StringCompareProbe = fn (u64, u64, u64, u64, u64, &u64)

struct StringCompareCase {
	a string
	b string
	result i64
}

const string_compare_cases = [
	StringCompareCase{'', '', 0}, StringCompareCase{'', 'a', -1},
	StringCompareCase{'a', 'aa', -1}, StringCompareCase{'a', 'b', -1},
	StringCompareCase{'A', 'a', -1}, StringCompareCase{'same', 'same', 0},
	StringCompareCase{'a\x00b', 'a\x00c', -1}, StringCompareCase{'a', 'a\x00', -1},
	StringCompareCase{'\x00', '', 1}, StringCompareCase{'π\x00🎮', 'π\x00🎮', 0},
	StringCompareCase{'é', 'e\u0301', 1}, StringCompareCase{'ß', 'ss', 1},
	StringCompareCase{'z', 'ä', -1}, StringCompareCase{'ø', 'o', 1},
	StringCompareCase{'file2', 'file10', 1}, StringCompareCase{'😀', '\ue000', -1},
	StringCompareCase{'\ufffd', '😀', 1}, StringCompareCase{'\U00010000', '\ue000', -1},
	StringCompareCase{'\U00010000', '\U00010001', -1},
	StringCompareCase{'\U000103ff', '\U00010400', -1},
	StringCompareCase{'\U0001ffff', '\U00020000', -1},
	StringCompareCase{'\U0010ffff', '\uffff', -1},
	StringCompareCase{'😀a', '😀b', -1}, StringCompareCase{'😀', '😀\x00', -1},
	StringCompareCase{'🎮🎮', '🎮🎮', 0}, StringCompareCase{'中文', '中文a', -1},
]!

fn string_compare_emit(code u64) {
	// Strings/options in x0–x2, protected x3–x8, preserved x20/x21.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xaa0303e4, 0xaa0303e5,
		0xaa0303e6, 0xaa0303e7, 0xaa0303e8, 0xaa0303f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn string_compare_raw(entry u64, a u64, b u64, code u64, guard u64) i64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { StringCompareProbe(voidptr(code))(entry, a, b, 0, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return i64(capture[1])
}

fn string_compare_native(a u64, b u64, flags u64) i64 {
	$if macos { return C.CFStringCompare(voidptr(a), voidptr(b), flags) }
	return 0
}

fn string_compare_worker(call StringCompareCall, a u64, b u64) {
	for _ in 0 .. 200 {
		assert call(a, b, 0) == -1 && call(b, a, 0) == 1 && call(a, a, 0) == 0
	}
}

fn string_compare_cases_run(entry u64, code u64, guard u64, native bool) {
	call := unsafe { StringCompareCall(voidptr(entry)) }
	for item in string_compare_cases {
		mut a := u64(0)
		mut b := u64(0)
		if native {
			$if macos {
				a = u64(C.CFStringCreateWithBytes(unsafe { nil }, item.a.str, item.a.len, 0x08000100, false))
				b = u64(C.CFStringCreateWithBytes(unsafe { nil }, item.b.str, item.b.len, 0x08000100, false))
			}
		} else { a = owned_string(item.a); b = owned_string(item.b) }
		assert a != 0 && b != 0
		assert string_compare_raw(entry, a, b, code, guard) == item.result
		assert string_compare_raw(entry, b, a, code, guard) == -item.result
		assert call(a, a, 0) == 0 && call(b, b, 0) == 0
		if native {
			$if macos { C.CFRelease(voidptr(a)); C.CFRelease(voidptr(b)) }
		} else {
			assert obj_header(a).refs == 1 && obj_header(b).refs == 1
			assert string_text(a) == item.a && string_text(b) == item.b
			objc_release(a); objc_release(b)
		}
	}
}

fn string_compare_constants(entry u64, code u64, guard u64) {
	text := 'A\x00🎮π'
	allocated := owned_string(text)
	mut record := [ios_runtime.names['NSString'], u64(0x7c8), u64(text.str), u64(text.len)]!
	address := u64(unsafe { &record[0] }); ios_runtime.constants[address] = true
	assert string_compare_raw(entry, address, allocated, code, guard) == 0
	assert string_compare_raw(entry, allocated, address, code, guard) == 0
	wide := [u16(0x41), 0, 0xd83c, 0xdfae, 0x3c0, 0]!
	record[1] = 0x7d0; record[2] = u64(unsafe { &wide[0] }); record[3] = 5
	metadata := ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__TEXT', address: 0, filesize: 12, prot: 1}]}
		layout: macho.Layout{size: 12}
		base: record[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	assert string_compare_raw(entry, address, allocated, code, guard) == 0
	assert string_compare_raw(entry, allocated, address, code, guard) == 0
	cached := ios_runtime.constant_utf8[address] or { panic('missing UTF-16 constant cache') }
	ios_runtime.constant_utf8.delete(address); unsafe { cached.free() }
	if _ := cf_string_compare_checked(address, allocated, 0) { assert false }
	record[1] = 0x1234
	if _ := cf_string_compare_checked(address, allocated, 0) { assert false }
	record[1] = 0x7c8; record[2] = 0
	if _ := cf_string_compare_checked(address, allocated, 0) { assert false }
	record[2] = guard; record[3] = 16777217
	if _ := cf_string_compare_checked(address, allocated, 0) { assert false }
	record[3] = 0
	assert string_compare_raw(entry, address, allocated, code, guard) == -1
	ios_runtime.constants.delete(address); objc_release(allocated)
}

fn string_compare_rejections(guard u64) {
	valid := owned_string('valid')
	other := objc_allocate(ios_runtime.names['NSObject'])
	stale := owned_string('freed'); objc_release(stale)
	baseline := ios_runtime.live
	for pointer in [u64(0), 1, guard, ios_runtime.names['NSString'], other, stale]! {
		if _ := cf_string_compare_checked(pointer, valid, 0) { assert false }
		if _ := cf_string_compare_checked(valid, pointer, 0) { assert false }
		if _ := cf_string_compare_checked(pointer, pointer, 0) { assert false }
	}
	for flags in [u64(1), 4, 8, 16, 32, 64, 128, 256, 512, u64(1) << 32, u64(1) << 63, ~u64(0)]! {
		if _ := cf_string_compare_checked(valid, valid, flags) { assert false }
	}
	for invalid in ['\xff', '\xc0\x80', '\x80', '\xf0\x90', '\xed\xa0\x80', '\xf4\x90\x80\x80']! {
		object := owned_string(invalid)
		if _ := cf_string_compare_checked(object, valid, 0) { assert false }
		if _ := cf_string_compare_checked(valid, object, 0) { assert false }
		if _ := cf_string_compare_checked(object, object, 0) { assert false }
		objc_release(object)
	}
	mut header := obj_header(valid)
	for length in [i64(-1), 16777217]! {
		header.text_length = int(length)
		if _ := cf_string_compare_checked(valid, valid, 0) { assert false }
	}
	header.text_length = 5
	pointer := header.text; header.text = unsafe { nil }
	if _ := cf_string_compare_checked(valid, valid, 0) { assert false }
	header.text = pointer
	assert ios_runtime.live == baseline && obj_header(valid).refs == 1 && string_text(valid) == 'valid'
	objc_release(other); objc_release(valid)
}

fn test_cf_string_compare() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }; defer { assert C.munmap(code, page * 2) == 0 }
	string_compare_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page); assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		string_compare_cases_run(u64(unsafe { voidptr(string_compare_native) }), u64(code), guard, true)
		println('NATIVE-CF-STRING-COMPARE: zero-option literal UTF-16 order, signed 64-bit -1/0/1, embedded NULs, prefixes, case/normalization distinctions, BMP/surrogate boundaries and protected unused registers')
	}
	if _ := cf_string_compare_checked(0, 0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFStringCompare') or { panic(err) }
		call := unsafe { StringCompareCall(voidptr(entry)) }
		pool := objc_pool_push()
		string_compare_cases_run(entry, u64(code), guard, false)
		string_compare_constants(entry, u64(code), guard)
		string_compare_rejections(guard)
		assert ios_runtime.live == 0 && objc_pool().objects.len == 0
		a := owned_string('😀'); b := owned_string('\ue000')
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn string_compare_worker(call, a, b) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == 2 && obj_header(a).refs == 1 && obj_header(b).refs == 1
		objc_release(a); objc_release(b)
		long := 'π\x00🎮'.repeat(4096)
		first := owned_string(long); second := owned_string(long)
		assert call(first, second, 0) == 0
		objc_release(first); objc_release(second); unsafe { long.free() }
		objc_pool_pop(pool)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFStringCompare') { assert false }
		}
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_concurrency_retired
		if _ := cf_string_compare_checked(0, 0, 0) { assert false }
	}
	println('IOS-CF-STRING-COMPARE: scoped three-register signed-64 ABI, protected x3–x8 and preserved x20/x21, literal UTF-16 streaming order, embedded NULs, allocated/UTF-8/decoded UTF-16 constants, rejected options/provenance/invalid UTF-8, eight concurrent readers, unchanged references, no autoreleases and two drained runtimes')
}
