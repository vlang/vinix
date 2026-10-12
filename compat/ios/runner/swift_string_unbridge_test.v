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
fn C.CFRelease(voidptr)
type UnbridgeCall = fn (u64) SwiftStringWords
type UnbridgeBytes = fn (u64, u64) u64
type UnbridgeRelease = fn (u64)
struct UnbridgeApi {
	native bool
	call UnbridgeCall
	bytes UnbridgeBytes
	release UnbridgeRelease
}
fn unbridge_assert_text(api UnbridgeApi, words SwiftStringWords, expected string) {
	array := api.bytes(words.first, words.second)
	assert read64(array + 16) == u64(expected.len + 1)
	assert C.memcmp(unsafe { voidptr(array + 32) }, expected.str, usize(expected.len)) == 0
	assert unsafe { *(&u8(array + 32 + u64(expected.len))) } == 0
	api.release(array)
}
fn unbridge_source(api UnbridgeApi, text string) u64 {
	if api.native {
		$if macos {
			object := C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false)
			assert object != unsafe { nil }
			return u64(object)
		}
	}
	return owned_string(text)
}
fn unbridge_source_release(api UnbridgeApi, source u64) {
	if api.native { $if macos { C.CFRelease(unsafe { voidptr(source) }); return } }
	objc_release(source)
}
fn unbridge_worker(api UnbridgeApi, source u64) {
	for _ in 0 .. 200 {
		words := api.call(source)
		unbridge_assert_text(api, words, 'Concurrent NSString bridge π 🎮 storage')
		api.release(words.second)
	}
}
fn unbridge_cases(api UnbridgeApi) {
	empty := api.call(0)
	assert empty.first == 0 && empty.second == u64(0xe000000000000000)
	unbridge_assert_text(api, empty, ''); api.release(empty.second)
	for text in ['', 'A', 'Fortnite', '123456789012345', '1234567890123456',
		'long ASCII Fortnite string from NSString', 'é 🎮', 'nonASCII large αβγδεζηθικλμνξοπ',
		'a\x00b', 'large\x00 embedded NUL NSString with π']! {
		source := unbridge_source(api, text)
		first := api.call(source); second := api.call(source)
		if !api.native { assert obj_header(source).refs == 1 }
		// Repeated bridges own independent results; source and either result may
		// die first. Native foreign representations also pass the same contract.
		unbridge_assert_text(api, first, text); api.release(first.second)
		if !api.native { assert string_text(source) == text && obj_header(source).refs == 1 }
		unbridge_source_release(api, source)
		unbridge_assert_text(api, second, text); api.release(second.second)
	}
	for count in 0 .. 33 {
		text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'.substr(0, count)
		source := unbridge_source(api, text); words := api.call(source)
		unbridge_source_release(api, source)
		unbridge_assert_text(api, words, text); api.release(words.second)
		unsafe { text.free() }
	}
	for _ in 0 .. 200 {
		source := unbridge_source(api, 'Repeated NSString bridges own this long UTF-8 π string')
		words := api.call(source); unbridge_source_release(api, source)
		unbridge_assert_text(api, words, 'Repeated NSString bridges own this long UTF-8 π string')
		api.release(words.second)
	}
	source := unbridge_source(api, 'Concurrent NSString bridge π 🎮 storage')
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn unbridge_worker(api, source) }
	workers.wait(); unsafe { workers.free() }; unbridge_source_release(api, source)
	if !api.native { assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 }
}
fn unbridge_constants(api UnbridgeApi) {
	// Real constant-string layout and UTF-16 registration, as used by Mach-O
	// loading. Only the cached UTF-8 bytes are read by the new bridge.
	text := 'Constant\x00NSString 🎮'; mut constant := [4]u64{}
	constant[0] = ios_runtime.names['NSString']; constant[1] = 0x7c8
	constant[2] = u64(text.str); constant[3] = u64(text.len)
	address := u64(unsafe { &constant[0] }); ios_runtime.constants[address] = true
	words := api.call(address); ios_runtime.constants.delete(address)
	unbridge_assert_text(api, words, text); api.release(words.second)
	utf16 := [u16(0x41), 0, 0xd83c, 0xdfae, 0x3c0, 0]!
	constant[1] = 0x7d0; constant[2] = u64(unsafe { &utf16[0] }); constant[3] = 5
	ios_runtime.constants[address] = true
	metadata := ObjMetadata{
		image: macho.Image{ segments: [macho.Segment{ name: '__TEXT', address: 0, filesize: 12, prot: 1 }] }
		layout: macho.Layout{ size: 12 }
		base: constant[2]
	}
	metadata.constant_string(address) or { panic(err) }
	unsafe { metadata.image.segments.free() }
	wide := api.call(address)
	ios_runtime.constants.delete(address)
	cached := ios_runtime.constant_utf8[address] or { panic('missing decoded constant') }
	ios_runtime.constant_utf8.delete(address); unsafe { cached.free() }
	unbridge_assert_text(api, wide, 'A\x00🎮π'); api.release(wide.second)
}
fn unbridge_invalid() {
	page := usize(C.getpagesize())
	guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert guard != unsafe { voidptr(-1) }
	for source in [u64(1), ~u64(0), u64(guard)]! {
		if _ := swift_foundation_unbridge_checked(source) { assert false }
	}
	assert C.munmap(guard, page) == 0
	object := objc_allocate(ios_runtime.names['NSObject'])
	if _ := swift_foundation_unbridge_checked(object) { assert false }
	objc_release(object)
	dead := owned_string('retired NSString'); objc_release(dead)
	if _ := swift_foundation_unbridge_checked(dead) { assert false }
	// Oversized input rejects before touching its deliberately unavailable tail.
	large := objc_allocate(ios_runtime.names['NSString']); mut header := obj_header(large)
	header.text = unsafe { &char(1) }; header.text_length = 1024 * 1024 + 1
	if _ := swift_foundation_unbridge_checked(large) { assert false }
	header.text = unsafe { nil }; header.text_length = 0; objc_release(large)
}
fn test_swift_string_unbridge() {
	$if macos {
		foundation := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert foundation != unsafe { nil } && core != unsafe { nil }
		api := UnbridgeApi{ native: true
			call: unsafe { UnbridgeCall(C.dlsym(foundation, c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ')) }
			bytes: unsafe { UnbridgeBytes(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }
			release: unsafe { UnbridgeRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
		}
		unbridge_cases(api)
		utf16 := [u16(0x41), 0, 0xd83c, 0xdfae, 0x3c0]!
		object := C.CFStringCreateWithCharacters(unsafe { nil }, unsafe { &utf16[0] }, 5)
		assert object != unsafe { nil }
		words := api.call(u64(object)); C.CFRelease(object)
		unbridge_assert_text(api, words, 'A\x00🎮π'); api.release(words.second)
		println('IOS-SWIFT-STRING-UNBRIDGE-NATIVE: nil, tagged/small/large NSStrings, Unicode, embedded NUL, UTF-16, repeated bridges and independently owned results after source release')
	}
	if _ := swift_foundation_unbridge_checked(0) { assert false }
	for library in ['/usr/lib/swift/libswiftFoundation.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
		objc_start(); baseline := ios_runtime.live
		for symbol in ['_$s10Foundation5NSLogyySS_s7CVarArg_pdtF',
			'_$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF',
			'_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ',
			'_$sSSs7CVarArg10FoundationMc']! {
			assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', symbol) or { panic(err) }
				== runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', symbol) or { panic(err) }
		}
		if _ := runtime_symbol('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',
			'_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ') { assert false }
		api := UnbridgeApi{
			call: unsafe { UnbridgeCall(voidptr(runtime_symbol(library, '_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ') or { panic(err) })) }
			bytes: swift_string_utf8_cstring
			release: swift_bridge_release
		}
		unbridge_cases(api); unbridge_constants(api); unbridge_invalid()
		assert ios_runtime.live == baseline && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		if _ := swift_foundation_unbridge_checked(0) { assert false }
	}
	println('IOS-SWIFT-STRING-UNBRIDGE: borrowed registered NSString and constants to owned Swift String; nil empty, Unicode and NUL preservation, source-release independence, guarded foreign/dead/type/size rejection, no retained storage across two drained lifetimes')
}
