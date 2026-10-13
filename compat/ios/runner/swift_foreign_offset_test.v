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
type ForeignOffsetCall = fn (u64, i64, u64, u64) u64
type ForeignOffsetBridge = fn (u64) SwiftStringWords
type ForeignOffsetRelease = fn (u64)
type ForeignOffsetAdvance = fn (u64, u64, u64) u64
fn foreign_offset_matrix(call ForeignOffsetCall, owner u64, units u64, positions []u64) {
	for _ in 0 .. 20 { for start in 0 .. positions.len { for target in 0 .. positions.len {
		distance := i64(target - start)
		expected := if distance == 0 { positions[start] } else if distance < 0 { positions[target] & ~u64(7) } else { positions[target] }
		assert call(positions[start], distance, units, owner | u64(0x5000000000000000)) == expected
	} } }
}
fn foreign_offset_values(call ForeignOffsetCall) {
	positions := [u64(15), 0x4008, 0x10009, 0x14008, 0x18008, 0x1c008, 0x30009]
	owner := owned_string('π🎮'); second := owner | u64(0x5000000000000000)
	foreign_offset_matrix(call, owner, 3, positions)
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn foreign_offset_matrix(call, owner, 3, positions) }
	workers.wait(); unsafe { workers.free(); positions.free() }
	assert obj_header(owner).refs == 1 && string_text(owner) == 'π🎮'
	assert call(0x20008, 1, 3, second) == 0x14008
	assert call(0x20008, 2, 3, second) == 0x18008
	for index in [u64(15), 0x4008, 0x30009, ~u64(0)]! { assert call(index, 0, ~u64(0), 1) == index }
	for distance in [i64(-9223372036854775807) - 1, -1, 7, 9223372036854775807]! { if _ := swift_foreign_offset_checked(15, distance, 3, second) { assert false } }
	for index in [u64(4), 0x8008, 0x20009, 0x24008, 0x34008, ~u64(0)]! { if _ := swift_foreign_offset_checked(index, 1, 3, second) { assert false } }
	if _ := swift_foreign_offset_checked(0x20008, -1, 3, second) { assert false }
	if _ := swift_foreign_offset_checked(15, 1, 4, second) { assert false }
	objc_release(owner); if _ := swift_foreign_offset_checked(15, 1, 3, second) { assert false }
	empty := owned_string(''); assert call(15, 0, 0, empty | u64(0x5000000000000000)) == 15
	for distance in [i64(-1), 1]! { if _ := swift_foreign_offset_checked(15, distance, 0, empty | u64(0x5000000000000000)) { assert false } }; objc_release(empty)
}
fn foreign_offset_constants(call ForeignOffsetCall) {
	wide := [u16(0x3c0), 0xd83c, 0xdfae, 0]!
	mut constant := [u64(0), 0x7d0, 0, 3]!
	constant[0] = ios_runtime.names['NSString']; constant[2] = u64(unsafe { &wide[0] })
	owner := u64(unsafe { &constant[0] }); ios_runtime.constants[owner] = true
	metadata := ObjMetadata{ image: macho.Image{ segments: [macho.Segment{ name: '__TEXT', address: 0, filesize: 8, prot: 1 }] }, layout: macho.Layout{ size: 8 }, base: constant[2] }
	metadata.constant_string(owner) or { panic(err) }; unsafe { metadata.image.segments.free() }
	assert call(15, 6, 3, owner | u64(0xd000000000000000)) == 0x30009
	assert call(0x30009, -6, 3, owner | u64(0xd000000000000000)) == 8
	ios_runtime.constants.delete(owner); cached := ios_runtime.constant_utf8[owner] or { panic('missing constant text') }
	ios_runtime.constant_utf8.delete(owner); unsafe { cached.free() }
}
fn test_swift_foreign_offset() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); foundation := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		native := unsafe { ForeignOffsetCall(C.dlsym(core, c'$sSS8UTF8ViewV13_foreignIndex_8offsetBySS0D0VAF_SitF')) }
		advance := unsafe { ForeignOffsetAdvance(C.dlsym(core, c'$sSS8UTF8ViewV13_foreignIndex5afterSS0D0VAF_tF')) }
		bridge := unsafe { ForeignOffsetBridge(C.dlsym(foundation, c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ')) }
		release := unsafe { ForeignOffsetRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
		objc_start(); mut pairs := 0
		for text in ['π🎮', '€é', 'long\x00 embedded NUL unicode π🎮', 'αβγδεζηθικλμνξοπρστυφχψω', '🎮🎮🎮🎮🎮🎮🎮🎮']! {
			source := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false); assert source != unsafe { nil }
			words := bridge(u64(source)); assert words.second >> 60 == 5; refs := C.CFGetRetainCount(source)
			owner := owned_string(text); mut positions := []u64{len: text.len + 1}; positions[0] = 15
			for i in 0 .. text.len { positions[i + 1] = advance(positions[i], words.first, words.second) }
			for start in 0 .. positions.len { for target in 0 .. positions.len {
				distance := i64(target - start); expected := native(positions[start], distance, words.first, words.second)
				assert swift_foreign_offset(positions[start], distance, words.first, owner | u64(0x5000000000000000)) == expected; pairs++
			} }
			assert C.CFGetRetainCount(source) == refs && obj_header(owner).refs == 1
			unsafe { positions.free() }; objc_release(owner); release(words.second); C.CFRelease(source)
		}
		assert pairs == 4744; objc_stop()
		println('IOS-FOREIGN-OFFSET-NATIVE: x0 index/x1 signed byte distance/x2-x3 borrowed view/x0 result; 4744 exact native raw-index matches across forward/backward/zero/endpoints and Unicode/NUL/combining marks/surrogates, unchanged ownership')
	}
	if _ := swift_foreign_offset_checked(15, 0, 0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		call := unsafe { ForeignOffsetCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS8UTF8ViewV13_foreignIndex_8offsetBySS0D0VAF_SitF') or { panic(err) })) }
		foreign_offset_values(call); foreign_offset_constants(call)
		page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert guard != unsafe { voidptr(-1) }
		assert call(~u64(0), 0, ~u64(0), u64(guard)) == ~u64(0)
		if _ := swift_foreign_offset_checked(15, 1, 1, u64(guard) | u64(0x5000000000000000)) { assert false }
		assert C.munmap(guard, page) == 0
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$sSS8UTF8ViewV13_foreignIndex_8offsetBySS0D0VAF_SitF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS8UTF8ViewV13_foreignIndex_8offsetBySS0D0VAF_SitF') == none
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop(); if _ := swift_foreign_offset_checked(15, 0, 0, 0) { assert false }
	}
	println('IOS-FOREIGN-OFFSET: bounded signed byte movement, exact zero no-read behavior and directional raw flags, two linear scans, four readers, constants, guarded/dead/bad-index/extent/INT64 rejection and two drained lifetimes')
}
