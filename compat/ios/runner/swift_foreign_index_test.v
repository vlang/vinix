// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type ForeignIndexCall = fn (u64, u64, u64) u64
type ForeignIndexBridge = fn (u64) SwiftStringWords
type ForeignIndexRelease = fn (u64)
fn foreign_index_chain(call ForeignIndexCall, owner u64, units u64, expected []u64) {
	for _ in 0 .. 40 {
		for i in 0 .. expected.len - 1 { assert call(expected[i], units, owner | u64(0x5000000000000000)) == expected[i + 1] }
	}
}
fn foreign_index_case(call ForeignIndexCall, text string, units u64, expected []u64) {
	owner := owned_string(text)
	foreign_index_chain(call, owner, units, expected)
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn foreign_index_chain(call, owner, units, expected) }
	workers.wait(); unsafe { workers.free() }
	assert string_text(owner) == text && obj_header(owner).refs == 1
	if _ := swift_foreign_index_after_checked(units << 16 | 9, units, owner | u64(0x5000000000000000)) { assert false }
	if _ := swift_foreign_index_after_checked(~u64(0), units, owner | u64(0x5000000000000000)) { assert false }
	objc_release(owner)
}
fn foreign_index_values(call ForeignIndexCall) {
	a := [u64(15), 0x4008, 0x10009, 0x14008, 0x18008, 0x1c008, 0x30009]
	b := [u64(15), 0x4008, 0x8008, 0x10009]
	c := [u64(15), 0x10009, 0x14008, 0x20009]
	d := [u64(15), 0x10009, 0x20009, 0x24008, 0x30009, 0x34008, 0x38008, 0x3c008, 0x50009]
	foreign_index_case(call, 'π🎮', 3, a); foreign_index_case(call, '€', 1, b)
	foreign_index_case(call, 'é', 2, c); foreign_index_case(call, 'A\x00π🎮', 5, d)
	unsafe { a.free(); b.free(); c.free(); d.free() }
	owner := owned_string('π🎮'); second := owner | u64(0x5000000000000000)
	for raw in [u64(0), 8, 9, 15]! { assert call(raw, 3, second) == 0x4008 }
	for raw in [u64(0x10000), 0x10008, 0x10009, 0x20000, 0x20008]! { assert call(raw, 3, second) == 0x14008 }
	for invalid in [u64(4), 0x8008, 0x10004, 0x20009, 0x24008, 0x30009]! {
		if _ := swift_foreign_index_after_checked(invalid, 3, second) { assert false }
	}
	assert obj_header(owner).refs == 1; objc_release(owner)
	if _ := swift_foreign_index_after_checked(15, 3, second) { assert false }
}
fn foreign_index_constants(call ForeignIndexCall) {
	wide := [u16(0x3c0), 0xd83c, 0xdfae, 0]!
	mut constant := [u64(0), 0x7d0, 0, 3]!
	constant[0] = ios_runtime.names['NSString']; constant[2] = u64(unsafe { &wide[0] })
	owner := u64(unsafe { &constant[0] }); ios_runtime.constants[owner] = true
	metadata := ObjMetadata{ image: macho.Image{ segments: [macho.Segment{ name: '__TEXT', address: 0, filesize: 8, prot: 1 }] }, layout: macho.Layout{ size: 8 }, base: constant[2] }
	metadata.constant_string(owner) or { panic(err) }; unsafe { metadata.image.segments.free() }
	assert call(15, 3, owner | u64(0xd000000000000000)) == 0x4008
	assert call(0x1c008, 3, owner | u64(0xd000000000000000)) == 0x30009
	ios_runtime.constants.delete(owner)
	cached := ios_runtime.constant_utf8[owner] or { panic('missing constant text') }
	ios_runtime.constant_utf8.delete(owner); unsafe { cached.free() }
}
fn foreign_index_invalid() {
	page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert guard != unsafe { voidptr(-1) }
	for owner in [u64(0), 1, u64(guard)]! { if _ := swift_foreign_index_after_checked(15, 1, owner | u64(0x5000000000000000)) { assert false } }
	assert C.munmap(guard, page) == 0
	owner := owned_string('π🎮')
	for second in [owner, owner | u64(0x4000000000000000), owner | u64(0x7000000000000000)]! { if _ := swift_foreign_index_after_checked(15, 3, second) { assert false } }
	if _ := swift_foreign_index_after_checked(15, 4, owner | u64(0x5000000000000000)) { assert false }
	if _ := swift_foreign_index_after_checked(15, u64(3) | u64(1) << 59, owner | u64(0x5000000000000000)) { assert false }
	objc_release(owner)
	empty := owned_string(''); if _ := swift_foreign_index_after_checked(15, 0, empty | u64(0x5000000000000000)) { assert false }; objc_release(empty)
}
fn test_swift_foreign_index_after() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		foundation := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		native := unsafe { ForeignIndexCall(C.dlsym(core, c'$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF')) }
		bridge := unsafe { ForeignIndexBridge(C.dlsym(foundation, c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ')) }
		release := unsafe { ForeignIndexRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
		objc_start()
		for text in ['π🎮', '€é', 'long\x00 embedded NUL unicode π🎮', 'αβγδεζηθικλμνξοπρστυφχψω', '🎮🎮🎮🎮🎮🎮🎮🎮']! {
			source := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false)
			assert source != unsafe { nil }; words := bridge(u64(source)); assert words.second >> 60 == 5
			refs := C.CFGetRetainCount(source); owner := owned_string(text); second := owner | u64(0x5000000000000000)
			mut index := u64(15)
			for _ in 0 .. text.len { next := native(index, words.first, words.second); assert swift_foreign_index_after(index, words.first, second) == next; index = next }
			assert index >> 16 == words.first && C.CFGetRetainCount(source) == refs && obj_header(owner).refs == 1
			objc_release(owner); release(words.second); C.CFRelease(source)
		}
		objc_stop()
		println('IOS-FOREIGN-INDEX-NATIVE: index x0, borrowed UTF8View x1/x2, returned raw index x0; every step matches native across five foreign Strings, all UTF8 widths, Unicode/NUL/combining marks/surrogates and unchanged ownership')
	}
	if _ := swift_foreign_index_after_checked(15, 0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		call := unsafe { ForeignIndexCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF') or { panic(err) })) }
		foreign_index_values(call); foreign_index_constants(call); foreign_index_invalid()
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF') == none
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop(); if _ := swift_foreign_index_after_checked(15, 0, 0) { assert false }
	}
	println('IOS-FOREIGN-INDEX: borrowed UTF16-indexed view, measured transcoding and successor flags, scalar alignment, all UTF8 widths, four readers, decoded constants, guarded/dead/empty/mismatched/bad-index rejection and two drained runtimes')
}
