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
// Native Swift leaves packed scalar bits above its UInt8 result. Read w0 and
// mask its low byte instead of assuming C's uint8_t zero-extension convention.
type ForeignSubscriptCall = fn (u64, u64, u64) u32
type ForeignSubscriptBridge = fn (u64) SwiftStringWords
type ForeignSubscriptRelease = fn (u64)
type ForeignSubscriptAdvance = fn (u64, u64, u64) u64
fn foreign_subscript_bytes(call ForeignSubscriptCall, owner u64, tag u64) {
	positions := [u64(15), 0x4008, 0x10009, 0x14008, 0x18008, 0x1c008]!
	text := 'π🎮'
	for _ in 0 .. 100 { for i, index in positions {
		for raw in [index, index & ~u64(1), index & ~u64(7)]! {
			assert call(raw, 3, owner | tag) == u32(text[i])
		}
	} }
}
fn foreign_subscript_values(call ForeignSubscriptCall) {
	owner := owned_string('π🎮'); second := owner | u64(0x5000000000000000)
	foreign_subscript_bytes(call, owner, u64(0x5000000000000000))
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn foreign_subscript_bytes(call, owner, u64(0x5000000000000000)) }
	workers.wait(); unsafe { workers.free() }
	assert obj_header(owner).refs == 1 && string_text(owner) == 'π🎮'
	for index in [u64(4), 0x8008, 0x20000, 0x20008, 0x20009, 0x24008, 0x30009, 0x34008, ~u64(0)]! {
		if _ := swift_foreign_subscript_checked(index, 3, second) { assert false }
	}
	if _ := swift_foreign_subscript_checked(15, 4, second) { assert false }
	objc_release(owner); if _ := swift_foreign_subscript_checked(15, 3, second) { assert false }
	empty := owned_string(''); if _ := swift_foreign_subscript_checked(15, 0, empty | u64(0x5000000000000000)) { assert false }; objc_release(empty)
}
fn foreign_subscript_constants(call ForeignSubscriptCall) {
	wide := [u16(0x3c0), 0xd83c, 0xdfae, 0]!
	mut constant := [u64(0), 0x7d0, 0, 3]!
	constant[0] = ios_runtime.names['NSString']; constant[2] = u64(unsafe { &wide[0] })
	owner := u64(unsafe { &constant[0] }); ios_runtime.constants[owner] = true
	metadata := ObjMetadata{ image: macho.Image{ segments: [macho.Segment{ name: '__TEXT', address: 0, filesize: 8, prot: 1 }] }, layout: macho.Layout{ size: 8 }, base: constant[2] }
	metadata.constant_string(owner) or { panic(err) }; unsafe { metadata.image.segments.free() }
	foreign_subscript_bytes(call, owner, u64(0xd000000000000000))
	ios_runtime.constants.delete(owner); cached := ios_runtime.constant_utf8[owner] or { panic('missing constant text') }
	ios_runtime.constant_utf8.delete(owner); unsafe { cached.free() }
}
fn test_swift_foreign_subscript() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); foundation := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		native := unsafe { ForeignSubscriptCall(C.dlsym(core, c'$sSS8UTF8ViewV17_foreignSubscript8positions5UInt8VSS5IndexV_tF')) }
		advance := unsafe { ForeignSubscriptAdvance(C.dlsym(core, c'$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF')) }
		bridge := unsafe { ForeignSubscriptBridge(C.dlsym(foundation, c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ')) }
		release := unsafe { ForeignSubscriptRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
		objc_start(); mut checks := 0
		for text in ['π🎮', '€é', 'long\x00 embedded NUL unicode π🎮', 'αβγδεζηθικλμνξοπρστυφχψω', '🎮🎮🎮🎮🎮🎮🎮🎮']! {
			source := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false); assert source != unsafe { nil }
			words := bridge(u64(source)); assert words.second >> 60 == 5; refs := C.CFGetRetainCount(source)
			owner := owned_string(text); mut index := u64(15)
			for expected in text {
				for raw in [index, index & ~u64(1), index & ~u64(7)]! {
					observed := native(raw, words.first, words.second) & 255; assert observed == u32(expected)
					assert swift_foreign_subscript(raw, words.first, owner | u64(0x5000000000000000)) == observed; checks++
				}
				index = advance(index, words.first, words.second)
			}
			assert C.CFGetRetainCount(source) == refs && obj_header(owner).refs == 1
			objc_release(owner); release(words.second); C.CFRelease(source)
		}
		assert checks == 375; objc_stop()
		println('IOS-FOREIGN-SUBSCRIPT-NATIVE: index x0/view x1-x2/UInt8 low w0; 375 exact byte matches across Unicode/NUL/combining marks/surrogates and canonical/directional/unmarked indices, unchanged ownership')
	}
	if _ := swift_foreign_subscript_checked(15, 0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		call := unsafe { ForeignSubscriptCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS8UTF8ViewV17_foreignSubscript8positions5UInt8VSS5IndexV_tF') or { panic(err) })) }
		foreign_subscript_values(call); foreign_subscript_constants(call)
		page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert guard != unsafe { voidptr(-1) }
		if _ := swift_foreign_subscript_checked(15, 1, u64(guard) | u64(0x5000000000000000)) { assert false }
		assert C.munmap(guard, page) == 0
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$sSS8UTF8ViewV17_foreignSubscript8positions5UInt8VSS5IndexV_tF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS8UTF8ViewV17_foreignSubscript8positions5UInt8VSS5IndexV_tF') == none
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop(); if _ := swift_foreign_subscript_checked(15, 0, 0) { assert false }
	}
	println('IOS-FOREIGN-SUBSCRIPT: checked scalar/transcoding byte reads, four readers, decoded constants, guarded/dead/empty/mismatched/end/past-end/UTF8-only/bad-transcoding/surrogate-interior rejection and two drained lifetimes without retained storage')
}
