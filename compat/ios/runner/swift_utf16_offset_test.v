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
type UTF16OffsetCall = fn (u64, i64, u64, u64) u64
type UTF16OffsetBridge = fn (u64) SwiftStringWords
type UTF16OffsetRelease = fn (u64)

fn utf16_offset_matrix(call UTF16OffsetCall, words SwiftStringWords, positions []u64, foreign bool, ascii bool) {
	for _ in 0 .. 20 { for start in 0 .. positions.len { for target in 0 .. positions.len {
		expected := if foreign { (u64(target) << 16) | 8 } else if ascii { (u64(target) << 16) | 13 } else { positions[target] }
		assert call(positions[start], i64(target - start), words.first, words.second) == expected
	} } }
}
fn utf16_offset_values(call UTF16OffsetCall) {
	owner := owned_string('π🎮'); words := SwiftStringWords{first: 3, second: owner | u64(0x5000000000000000)}
	foreign := [u64(8), 0x10008, 0x20008, 0x30008]
	utf16_offset_matrix(call, words, foreign, true, false)
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn utf16_offset_matrix(call, words, foreign, true, false) }
	workers.wait(); unsafe { workers.free(); foreign.free() }
	assert obj_header(owner).refs == 1
	for index in [u64(0), 1, 8, 12, 15, 0x14000, 0x14008]! {
		assert call(index, 0, words.first, words.second) == ((index >> 16) << 16) | 8
	}
	for distance in [i64(-9223372036854775807) - 1, -1, 4, 9223372036854775807]! {
		if _ := swift_utf16_offset_checked(15, distance, words.first, words.second) { assert false }
	}
	for index in [u64(4), 0x34008, 0x40008, ~u64(0)]! { if _ := swift_utf16_offset_checked(index, 0, words.first, words.second) { assert false } }
	if _ := swift_utf16_offset_checked(15, 0, 4, words.second) { assert false }
	objc_release(owner); if _ := swift_utf16_offset_checked(15, 0, words.first, words.second) { assert false }
	literal := swift_string_literal(c'π🎮', 6, false)
	positions := [u64(5), 0x20005, 0x24004, 0x60005]
	utf16_offset_matrix(call, literal, positions, false, false); unsafe { positions.free() }
	assert call(15, 0, literal.first, literal.second) == 15
	assert call(0x10000, 0, literal.first, literal.second) == 5
	assert call(0x40000, 1, literal.first, literal.second) == 0x24004
	for index in [u64(8), 0x14004, 0x28004, 0x40001, 0x70005]! { if _ := swift_utf16_offset_checked(index, 0, literal.first, literal.second) { assert false } }
	for distance in [i64(-9223372036854775807) - 1, -1, 4, 9223372036854775807]! { if _ := swift_utf16_offset_checked(15, distance, literal.first, literal.second) { assert false } }
	empty := swift_string_empty(); assert call(15, 0, empty.first, empty.second) == 13
	for distance in [i64(-1), 1]! { if _ := swift_utf16_offset_checked(15, distance, empty.first, empty.second) { assert false } }
	owned := swift_string_storage(64, 6, false)
	C.memcpy(unsafe { voidptr(owned.second + 32) }, c'π🎮', 6)
	assert call(15, 2, owned.first, owned.second) == 0x24004
	assert call(0x60005, -3, owned.first, owned.second) == 5
	assert swift_buffer_refs(owned.second, 0) or { panic(err) } == 1
	swift_release(owned.second); if _ := swift_utf16_offset_checked(15, 0, owned.first, owned.second) { assert false }
	bad := swift_string_literal(c'\xff', 1, false)
	if _ := swift_utf16_offset_checked(15, 0, bad.first, bad.second) { assert false }
}
fn utf16_offset_constants(call UTF16OffsetCall) {
	wide := [u16(0x3c0), 0xd83c, 0xdfae, 0]!
	mut constant := [u64(0), 0x7d0, 0, 3]!
	constant[0] = ios_runtime.names['NSString']; constant[2] = u64(unsafe { &wide[0] })
	owner := u64(unsafe { &constant[0] }); ios_runtime.constants[owner] = true
	metadata := ObjMetadata{ image: macho.Image{ segments: [macho.Segment{ name: '__TEXT', address: 0, filesize: 8, prot: 1 }] }, layout: macho.Layout{ size: 8 }, base: constant[2] }
	metadata.constant_string(owner) or { panic(err) }; unsafe { metadata.image.segments.free() }
	assert call(15, 2, 3, owner | u64(0xd000000000000000)) == 0x20008
	assert call(0x30008, -3, 3, owner | u64(0xd000000000000000)) == 8
	ios_runtime.constants.delete(owner); cached := ios_runtime.constant_utf8[owner] or { panic('missing constant text') }
	ios_runtime.constant_utf8.delete(owner); unsafe { cached.free() }
}
fn test_swift_utf16_offset() {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW); foundation := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		native := unsafe { UTF16OffsetCall(C.dlsym(core, c'$sSS9UTF16ViewV5index_8offsetBySS5IndexVAF_SitF')) }
		bridge := unsafe { UTF16OffsetBridge(C.dlsym(foundation, c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ')) }
		release := unsafe { UTF16OffsetRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
		objc_start(); mut pairs := 0
		for text in ['', 'ascii\x00', 'π🎮', '€é', 'long\x00 embedded NUL unicode π🎮', 'αβγδεζηθικλμνξοπρστυφχψω', '🎮🎮🎮🎮🎮🎮🎮🎮', 'a'.repeat(80) + '🎮éπ'] {
			mut units := 0; mut ascii := true
			for byte in text { if byte >= 128 { ascii = false }; if byte & 0xc0 != 0x80 { units += if byte >= 0xf0 { 2 } else { 1 } } }
			source := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false); assert source != unsafe { nil }
			bridged := bridge(u64(source)); refs := C.CFGetRetainCount(source)
			literal := swift_string_literal(text.str, i64(text.len), ascii)
			owner := owned_string(text)
			for words in [literal, bridged]! {
				runtime := if words.second >> 60 == 5 { SwiftStringWords{first: words.first, second: owner | u64(0x5000000000000000)} } else { words }
				mut positions := []u64{len: units + 1}
				for target in 0 .. positions.len { positions[target] = native(15, i64(target), words.first, words.second) }
				for start in 0 .. positions.len { for target in 0 .. positions.len {
					distance := i64(target - start)
					expected := native(positions[start], distance, words.first, words.second)
					observed := swift_utf16_offset(positions[start], distance, runtime.first, runtime.second)
					assert observed == expected, 'text=${text} second=${words.second.hex()} start=${start} target=${target} index=${positions[start].hex()} distance=${distance} observed=${observed.hex()} expected=${expected.hex()}'
					pairs++
				} }
				for target in 0 .. positions.len { assert swift_utf16_offset(15, i64(target), runtime.first, runtime.second) == positions[target] }
				unsafe { positions.free() }
			}
			assert C.CFGetRetainCount(source) == refs && obj_header(owner).refs == 1
			objc_release(owner); release(bridged.second); C.CFRelease(source)
		}
		assert pairs == 18706; objc_stop()
		println('IOS-UTF16-OFFSET-NATIVE: x0 index/x1 signed UTF16 distance/x2-x3 borrowed view/x0 result; 18706 exact native raw-index matches including large distances, inline/native-tail/foreign storage, Unicode/NUL/combining/surrogate interiors, normalized zero flags and unchanged ownership')
	}
	if _ := swift_utf16_offset_checked(15, 0, 0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		call := unsafe { UTF16OffsetCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS9UTF16ViewV5index_8offsetBySS5IndexVAF_SitF') or { panic(err) })) }
		utf16_offset_values(call); utf16_offset_constants(call)
		page := usize(C.getpagesize()); guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0); assert guard != unsafe { voidptr(-1) }
		for second in [u64(guard), u64(guard) | u64(0x5000000000000000)]! { if _ := swift_utf16_offset_checked(15, 0, u64(0x1000000000000001), second) { assert false } }
		if _ := swift_utf16_offset_checked(15, 0, u64(0x1000000000100001), u64(guard) | u64(0x8000000000000000)) { assert false }
		assert C.munmap(guard, page) == 0
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$sSS9UTF16ViewV5index_8offsetBySS5IndexVAF_SitF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS9UTF16ViewV5index_8offsetBySS5IndexVAF_SitF') == none
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		ios_runtime.swift_concurrency_retired = true
		if _ := swift_utf16_offset_checked(15, 0, 0, u64(0xe000000000000000)) { assert false }
		ios_runtime.swift_concurrency_retired = false
		objc_stop()
	}
	println('IOS-UTF16-OFFSET: signed bounded UTF16 movement, native/foreign surrogate interiors, zero normalization, four readers, owned native storage, decoded constants, guarded/dead/malformed/encoding/INT64 rejection and two drained lifetimes')
}
