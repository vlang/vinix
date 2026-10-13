// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)

type DescribingEntry = fn (u64, u64) SwiftStringWords
type DescribingRaw = fn (u64, u64, u64, &u64)
type DescribingExtract = fn (u64, &u64, &SwiftErrorValue)
type DescribingLookup = fn (u64, u64, u64, u64) u64
type DescribingLiteral = fn (&u8, i64, bool) SwiftStringWords
type DescribingCString = fn (&u8) SwiftStringWords
type DescribingBytes = fn (u64, u64) u64
type DescribingRelease = fn (u64)
struct DescribingApi {
	native bool
	entry DescribingEntry
	literal DescribingLiteral
	bytes DescribingBytes
	release DescribingRelease
	extract DescribingExtract
	lookup DescribingLookup
	string_type u64
	int_type u64
	void_type u64
	error_type u64
}

fn describing_api(native bool) DescribingApi {
	name := 's5Error_p'
	if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert core != unsafe { nil }
		assert C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', C.RTLD_NOW) != unsafe { nil }
		lookup := unsafe { DescribingLookup(C.dlsym(core, c'swift_getTypeByMangledNameInContext')) }
		return DescribingApi{ native: true
			lookup: lookup
			entry: unsafe { DescribingEntry(C.dlsym(core, c'$sSS10describingSSx_tclufC')) }
			literal: unsafe { DescribingLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }
			bytes: unsafe { DescribingBytes(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }
			release: unsafe { DescribingRelease(C.dlsym(core, c'swift_bridgeObjectRelease')) }
			extract: unsafe { DescribingExtract(C.dlsym(core, c'swift_getErrorValue')) }
			string_type: u64(C.dlsym(core, c'$sSSN'))
			int_type: u64(C.dlsym(core, c'$sSiN'))
			void_type: u64(C.dlsym(core, c'$sytN')) + 8
			error_type: lookup(u64(name.str), u64(name.len), 0, 0)
		}
	}
	address := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS10describingSSx_tclufC') or { panic(err) }
	assert address == u64(unsafe { voidptr(swift_string_describing) })
	return DescribingApi{ entry: unsafe { DescribingEntry(voidptr(address)) }, literal: swift_string_literal,
		lookup: swift_mangled_lookup,
		bytes: swift_string_utf8_cstring, release: swift_bridge_release, extract: swift_error_value,
		string_type: swift_string_metadata(), int_type: swift_integer_metadata(),
		void_type: swift_void_full_metadata() + 8,
		error_type: swift_mangled_lookup(u64(name.str), u64(name.len), 0, 0) }
}

fn describing_raw(api DescribingApi, probe DescribingRaw, source u64, metadata u64) SwiftStringWords {
	mut output := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
	probe(source, metadata, u64(unsafe { voidptr(api.entry) }), unsafe { &output[1] })
	assert output[0] == 0x1234 && output[5] == 0x5678
	assert output[3] == 0x5020 && output[4] == 0x5021
	return SwiftStringWords{ first: output[1], second: output[2] }
}
fn describing_assert(api DescribingApi, words SwiftStringWords, expected string) {
	array := api.bytes(words.first, words.second)
	assert read64(array + 16) == u64(expected.len + 1)
	assert C.memcmp(unsafe { voidptr(array + 32) }, expected.str, usize(expected.len)) == 0
	assert unsafe { *(&u8(array + 32 + u64(expected.len))) } == 0
	api.release(array); api.release(words.second)
}
fn (api DescribingApi) text(value string) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateWithBytes(unsafe { nil }, value.str, i64(value.len), 0x08000100, false)) } }
	return owned_string(value)
}
fn (api DescribingApi) drop(owner u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(owner) }); return } }
	objc_release(owner)
}
fn (api DescribingApi) keep(owner u64) {
	$if macos { if api.native { C.CFRetain(unsafe { voidptr(owner) }); return } }
	objc_retain(owner)
}
fn (api DescribingApi) refs(owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}
fn (api DescribingApi) error_owner(field bool) u64 {
	domain := api.text('Fortnite π'); mut info := u64(0)
	if field {
		$if macos { if api.native { info = u64(C.CFDictionaryCreateMutable(unsafe { nil }, 0, unsafe { &C.kCFTypeDictionaryKeyCallBacks }, unsafe { &C.kCFTypeDictionaryValueCallBacks })) } }
		if !api.native { info = cf_dictionary_mutable(0, 0, cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'), cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks')) }
		key := api.text('NSLocalizedDescription'); value := api.text('Description π')
		$if macos { if api.native { C.CFDictionarySetValue(unsafe { voidptr(info) }, unsafe { voidptr(key) }, unsafe { voidptr(value) }) } }
		if !api.native { cf_dictionary_set(info, key, value) }
		api.drop(key); api.drop(value)
	}
	mut owner := u64(0)
	$if macos { if api.native { owner = u64(C.CFErrorCreate(unsafe { nil }, unsafe { voidptr(domain) }, -7, unsafe { voidptr(info) })) } }
	if !api.native {
		owner = objc_allocate(cf_error_type_id()); mut header := obj_header(owner)
		header.number = -7; header.fields[0] = objc_retain(domain); header.fields[1] = objc_retain(info)
	}
	api.drop(domain); if info != 0 { api.drop(info) }; return owner
}

fn describing_values(api DescribingApi, probe DescribingRaw, boundary u64) {
	// Marketplace uses a seven-byte indirect Error protocol reference followed
	// by _p. Recreate its bound slot at a protected boundary, including the
	// unaligned signed relative field and embedded zero bytes.
	name := boundary - 7
	distance := u32(i32(i64(boundary - 64) - i64(name + 1)))
	unsafe {
		*(&u64(boundary - 64)) = read64(api.error_type + 16)
		*(&u8(name)) = 2
		for offset in u64(0) .. 4 { *(&u8(name + 1 + offset)) = u8(distance >> (offset * 8)) }
		*(&u8(name + 5)) = `_`; *(&u8(name + 6)) = `p`
	}
	assert api.lookup(name, 7, 0, 0) == api.error_type
	if !api.native {
		unsafe { *(&u64(boundary - 64)) = boundary }
		if _ := swift_mangled_lookup_checked(name, 7, 0, 0) { assert false }
		unsafe { *(&u64(boundary - 64)) = read64(api.error_type + 16) }
	}
	for expected in ['', 'Fortnite', '123456789012345', 'Fortnite π\x00🎮', 'long borrowed description exceeds inline capacity']! {
		words := api.literal(expected.str, i64(expected.len), expected.is_ascii())
		unsafe { *(&SwiftStringWords(boundary - 16)) = words }
		result := describing_raw(api, probe, boundary - 16, api.string_type)
		assert result.first == words.first && result.second == words.second
		describing_assert(api, result, expected)
	}
	for index, value in [i64(0), -1, 9223372036854775807, i64(-9223372036854775807) - 1]! {
		unsafe { *(&i64(boundary - 8)) = value }
		result := describing_raw(api, probe, boundary - 8, api.int_type)
		describing_assert(api, result, ['0', '-1', '9223372036854775807', '-9223372036854775808']![index])
	}
	for source in [u64(0), boundary]! { describing_assert(api, describing_raw(api, probe, source, api.void_type), '()') }
	// The owned String's one strong reference transfers to the result, without
	// an extra retain or a premature free, for both direct and raw ABI calls.
	for raw in [false, true]! {
		expected := 'a real owned Swift String for consuming description'
		mut words := SwiftStringWords{}
		$if macos { if api.native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			words = unsafe { DescribingCString(C.dlsym(core, c'$sSS7cStringSSSPys4Int8VG_tcfC'))(expected.str) }
		} }
		if !api.native { words = swift_interpolation_init(i64(expected.len), 0); swift_string_append_bytes(u64(unsafe { &words }), u64(expected.str), u64(expected.len)) }
		assert read64(words.second + 8) >> 33 == 0
		result := if raw { describing_raw(api, probe, u64(unsafe { &words }), api.string_type) } else { api.entry(u64(unsafe { &words }), api.string_type) }
		assert result.first == words.first && result.second == words.second
		assert read64(result.second + 8) >> 33 == 0
		describing_assert(api, result, expected)
	}
	for field in [false, true]! {
		for concrete in [false, true]! {
			owner := api.error_owner(field)
			mut scratch := u64(0); mut extracted := SwiftErrorValue{}
			api.extract(owner, unsafe { &scratch }, unsafe { &extracted })
			api.keep(owner); assert api.refs(owner) == 2
			unsafe { *(&u64(boundary - 8)) = owner }
			result := describing_raw(api, probe, boundary - 8, if concrete { extracted.metadata } else { api.error_type })
			assert api.refs(owner) == 1; api.drop(owner)
			expected := if field { 'Error Domain=Fortnite π Code=-7 "Description π" UserInfo={NSLocalizedDescription=Description π}' } else { 'Error Domain=Fortnite π Code=-7 "(null)"' }
			describing_assert(api, result, expected) // Result outlives all error fields.
		}
	}
}
fn describing_invalid(api DescribingApi, guard u64) {
	for metadata in [u64(0), 1, ~u64(0), guard]! { if _ := swift_string_describing_checked(guard, metadata) { assert false } }
	for source in [u64(0), 1, ~u64(0)]! { if _ := swift_string_describing_checked(source, api.string_type) { assert false } }
	mut owner := guard
	if _ := swift_string_describing_checked(u64(unsafe { &owner }), api.error_type) { assert false }
	owner = objc_allocate(ios_runtime.names['NSObject'])
	if _ := swift_string_describing_checked(u64(unsafe { &owner }), api.error_type) { assert false }
	assert obj_header(owner).refs == 1; objc_release(owner)
	owner = api.error_owner(true)
	info := obj_header(owner).fields[1]; key := owned_string('NSLocalizedDescription'); wrong := objc_allocate(ios_runtime.names['NSNumber'])
	cf_dictionary_set(info, key, wrong); objc_release(key); objc_release(wrong)
	if _ := swift_string_describing_checked(u64(unsafe { &owner }), api.error_type) { assert false }
	assert obj_header(owner).refs == 1; objc_release(owner)
	for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { if _ := runtime_symbol(library, '_$sSS10describingSSx_tclufC') { assert false } }
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS10describingSSx_tclufC') == none
}
fn test_swift_string_describing() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	boundary := code + u64(page * 2)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0203f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 56) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(unsafe { voidptr(boundary) }, page, C.PROT_NONE) == 0
	probe := unsafe { DescribingRaw(voidptr(code)) }
	$if macos { describing_values(describing_api(true), probe, boundary)
		println('IOS-DESCRIBING-NATIVE: consuming String/Int/Void and concrete/existential CFError, exact Unicode text, signed limits, owned results, no input overread and preserved x20/x21') }
	for _ in 0 .. 2 {
		objc_start(); api := describing_api(false)
		assert read64(api.error_type) == 0x303 && read64(api.error_type + 8) == 0x181000001
		assert read64(api.error_type + 16) == swift_error_metadata_arena() + u64(page) + 240
		assert read64(read64(api.error_type - 8) + 64) == 8
		describing_values(api, probe, boundary); describing_invalid(api, boundary)
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop(); assert ios_runtime.swift_error_arena == 0 && ios_runtime.swift_objc_metadata.len == 0
		if _ := swift_string_describing_checked(boundary, api.error_type) { assert false }
	}
	assert C.munmap(unsafe { voidptr(code) }, page * 3) == 0
	println('IOS-DESCRIBING: scoped consuming constructor, canonical Error metadata, protected value boundaries, owned result lifetimes, rejected foreign metadata/owners/fields without consumption, two drained runtimes')
}
