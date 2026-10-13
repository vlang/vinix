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
fn C.CFStringCreateWithCharacters(voidptr, &u16, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type ForeignCountCall = fn (u64, u64) i64
type ForeignCountBridge = fn (u64) SwiftStringWords
type ForeignCountRelease = fn (u64)
fn foreign_count_worker(call ForeignCountCall, first u64, second u64, count int) {
	for _ in 0 .. 400 { assert call(first, second) == count }
}
fn foreign_count_values(call ForeignCountCall) {
	counts := [u64(0), 8, 3, 3, 30, 24, 16]!
	for i, text in ['', 'Fortnite', 'a\x00b', 'π🎮', 'long\x00 embedded NUL unicode π🎮',
		'αβγδεζηθικλμνξοπρστυφχψω', '🎮🎮🎮🎮🎮🎮🎮🎮']! {
		owner := owned_string(text)
		units := counts[i]
		second := owner | u64(0x5000000000000000)
		assert call(units, second) == text.len && obj_header(owner).refs == 1
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn foreign_count_worker(call, units, second, text.len) }
		workers.wait(); unsafe { workers.free() }
		assert string_text(owner) == text && obj_header(owner).refs == 1
		if _ := swift_foreign_count_checked(units + 1, second) { assert false }
		assert call(units | u64(0x4000000000000000), second) == text.len
		objc_release(owner)
	}
}
fn foreign_count_constants(call ForeignCountCall) {
	text := 'Constant\x00NSString 🎮'; mut constant := [4]u64{}
	constant[0] = ios_runtime.names['NSString']; constant[1] = 0x7c8
	constant[2] = u64(text.str); constant[3] = u64(text.len)
	address := u64(unsafe { &constant[0] }); ios_runtime.constants[address] = true
	assert call(20, address | u64(0xd000000000000000)) == text.len
	ios_runtime.constants.delete(address)
	wide := [u16(0x41), 0, 0xd83c, 0xdfae, 0x3c0, 0]!
	constant[1] = 0x7d0; constant[2] = u64(unsafe { &wide[0] }); constant[3] = 5
	ios_runtime.constants[address] = true
	metadata := ObjMetadata{
		image: macho.Image{ segments: [macho.Segment{ name: '__TEXT', address: 0, filesize: 12, prot: 1 }] }
		layout: macho.Layout{ size: 12 }
		base: constant[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	assert call(5, address | u64(0xd000000000000000)) == 8
	ios_runtime.constants.delete(address)
	cached := ios_runtime.constant_utf8[address] or { panic('missing decoded constant') }
	ios_runtime.constant_utf8.delete(address); unsafe { cached.free() }
	ios_runtime.constants[address] = true
	if _ := swift_foreign_count_checked(5, address | u64(0xd000000000000000)) { assert false }
	ios_runtime.constants.delete(address)
}
fn foreign_count_invalid() {
	page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert guard != unsafe { voidptr(-1) }
	for owner in [u64(0), 1, u64(guard)]! {
		if _ := swift_foreign_count_checked(1, owner | u64(0x5000000000000000)) { assert false }
	}
	assert C.munmap(guard, page) == 0
	owner := owned_string('π🎮')
	for discriminator in [u64(0), 4, 6, 7, 8, 9, 12, 14, 15]! {
		if _ := swift_foreign_count_checked(3, owner | (discriminator << 60)) { assert false }
	}
	for first in [u64(3) | (u64(1) << 59), u64(3) | (u64(1) << 60), u64(3) | (u64(1) << 48)]! {
		if _ := swift_foreign_count_checked(first, owner | u64(0x5000000000000000)) { assert false }
	}
	objc_release(owner)
	if _ := swift_foreign_count_checked(3, owner | u64(0x5000000000000000)) { assert false }
	object := objc_allocate(ios_runtime.names['NSObject'])
	if _ := swift_foreign_count_checked(0, object | u64(0x5000000000000000)) { assert false }
	objc_release(object)
	invalid := owned_string('\xc0\x80')
	if _ := swift_foreign_count_checked(1, invalid | u64(0x5000000000000000)) { assert false }
	objc_release(invalid)
	broken := objc_allocate(ios_runtime.names['NSString']); mut header := obj_header(broken)
	header.text = unsafe { &char(1) }; header.text_length = 1048577
	if _ := swift_foreign_count_checked(1, broken | u64(0x5000000000000000)) { assert false }
	header.text_length = -1
	if _ := swift_foreign_count_checked(0, broken | u64(0x5000000000000000)) { assert false }
	header.text = unsafe { nil }; header.text_length = 1
	if _ := swift_foreign_count_checked(1, broken | u64(0x5000000000000000)) { assert false }
	header.text_length = 0; objc_release(broken)
}
fn test_swift_foreign_utf8_count() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		foundation := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		call := unsafe { ForeignCountCall(C.dlsym(core, c'$sSS8UTF8ViewV13_foreignCountSiyF')) }
		bridge := unsafe { ForeignCountBridge(C.dlsym(foundation, c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ')) }
		release := unsafe { ForeignCountRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
		for text in ['π🎮', 'long\x00 embedded NUL unicode π🎮', 'αβγδεζηθικλμνξοπρστυφχψω', '🎮🎮🎮🎮🎮🎮🎮🎮']! {
			owner := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false)
			assert owner != unsafe { nil }; words := bridge(u64(owner)); assert words.second >> 60 == 5
			before := C.CFGetRetainCount(owner)
			assert call(words.first, words.second) == text.len && C.CFGetRetainCount(owner) == before
			foreign_count_worker(call, words.first, words.second, text.len)
			release(words.second); C.CFRelease(owner)
		}
		wide := [u16(0x41), 0, 0xd83c, 0xdfae, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0, 0x3c0]!
		owner := C.CFStringCreateWithCharacters(unsafe { nil }, unsafe { &wide[0] }, wide.len)
		words := bridge(u64(owner)); assert words.first == 20 && words.second >> 60 == 5
		before := C.CFGetRetainCount(owner); assert call(words.first, words.second) == 38 && C.CFGetRetainCount(owner) == before
		release(words.second); C.CFRelease(owner)
		println('IOS-FOREIGN-COUNT-NATIVE: borrowed x0/x1 UTF16-backed view, signed UTF8 byte count in x0, five real NSString-backed inputs, Unicode/NUL/surrogates and unchanged native ownership')
	}
	if _ := swift_foreign_count_checked(0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		call := unsafe { ForeignCountCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS8UTF8ViewV13_foreignCountSiyF') or { panic(err) })) }
		foreign_count_values(call); foreign_count_constants(call); foreign_count_invalid()
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$sSS8UTF8ViewV13_foreignCountSiyF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS8UTF8ViewV13_foreignCountSiyF') == none
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		if _ := swift_foreign_count_checked(0, 0) { assert false }
	}
	println('IOS-FOREIGN-COUNT: borrowed registered NSString/decoded constants, full UTF16 extent to UTF8 byte count, Unicode/NUL preservation, four readers, invalid flags/count/owner/type/bytes/bounds rejection and two drained runtimes without retained storage')
}
