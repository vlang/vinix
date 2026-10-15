// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFLocale.h>
	#include <CoreFoundation/CFString.h>
	#include <mach/mach.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFLocaleGetIdentifier(voidptr) voidptr
fn C.CFStringGetCString(voidptr, &u8, i64, u32) bool
fn C.CFRelease(voidptr)
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type LocaleProbe = fn (u64, u64, u64, u64, u64, &u64)
type LocaleAccess = fn (u64) SwiftAssociatedMetadata
type LocaleCString = fn (&u8) SwiftStringWords
type LocaleUTF8 = fn (u64, u64) u64
type LocaleKeep = fn (u64) u64
type LocaleDrop = fn (u64)
type LocaleCopy = fn (u64, u64, u64) u64
type LocaleDestroy = fn (u64, u64)
type LocaleTag = fn (u64, u32, u64) u32
type LocaleStore = fn (u64, u32, u32, u64)

struct LocaleApi {
	native bool
	entries [5]u64
	metadata u64
	witness u64
	probe LocaleProbe
mut:
	utf8 LocaleUTF8 = swift_string_utf8_cstring
	keep LocaleKeep = swift_bridge_retain
	drop LocaleDrop = swift_bridge_release
	cstring LocaleCString = locale_owned_input
}

fn locale_names() [5]string {
	return ['_$s10Foundation6LocaleV10identifierACSS_tcfC',
		'_$s10Foundation6LocaleV10identifierSSvg',
		'_$s10Foundation6LocaleV19_bridgeToObjectiveCSo8NSLocaleCyF',
		'_$s10Foundation6LocaleVMa', '_$s10Foundation6LocaleVMn']!
}

fn locale_owned_input(bytes &u8) SwiftStringWords {
	text := unsafe { (&char(bytes)).vstring() }
	scratch := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(scratch)) = swift_interpolation_init(128, 0) }
	swift_string_append_bytes(scratch, u64(bytes), u64(text.len))
	return unsafe { *(&SwiftStringWords(scratch)) }
}

fn locale_api(native bool, code u64) LocaleApi {
	mut entries := [5]u64{}
	for i, name in locale_names() {
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/swift/libswiftFoundation.dylib']! {
			mut address := u64(0)
			$if macos { if native { handle := C.dlopen(library.str, 2); address = u64(C.dlsym(handle, name[1..].str)) } }
			if !native { address = runtime_symbol(library, name) or { panic(err) } }
			assert address != 0 && (entries[i] == 0 || entries[i] == address)
			entries[i] = address
		}
	}
	response := unsafe { LocaleAccess(voidptr(entries[3]))(0) }
	assert response.state == 0 && read64(response.metadata) == 0x200
	witness := read64(response.metadata - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 16 && read64(witness + 72) == 16
	assert read32(witness + 80) == 0x02010007 && read32(witness + 84) == 0x7fffffff
	assert read64(response.metadata + 8) & 0x0000ffffffffffff == entries[4]
	mut api := LocaleApi{native: native, entries: entries, metadata: response.metadata, witness: witness, probe: unsafe { LocaleProbe(voidptr(code)) }}
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		api.utf8 = unsafe { LocaleUTF8(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }
		api.keep = unsafe { LocaleKeep(C.dlsym(core, c'swift_bridgeObjectRetain')) }
		api.drop = unsafe { LocaleDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) }
		api.cstring = unsafe { LocaleCString(C.dlsym(core, c'$sSS7cStringSSSPys4Int8VG_tcfC')) }
	} }
	return api
}

fn (api LocaleApi) call(entry u64, first u64, second u64, self u64, result u64) [2]u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	api.probe(entry, first, second, self, result, unsafe { &capture[1] })
	assert capture[0] == 0xcafe && capture[3] == self && capture[4] == 0x5021 && capture[5] == 0xbeef
	return [capture[1], capture[2]]!
}

fn (api LocaleApi) check_string(first u64, second u64, expected string) {
	array := api.utf8(first, second)
	assert read64(array + 16) == u64(expected.len + 1)
	assert C.memcmp(voidptr(array + 32), expected.str, usize(expected.len)) == 0
	assert unsafe { *(&u8(array + 32 + u64(expected.len))) } == 0
	api.drop(array)
}

fn (api LocaleApi) check_object(object u64, expected string) {
	$if macos { if api.native {
		mut buffer := [256]u8{}
		assert C.CFStringGetCString(C.CFLocaleGetIdentifier(voidptr(object)), unsafe { &buffer[0] }, 256, 0x08000100)
		assert unsafe { (&char(&buffer[0])).vstring() } == expected
		return
	} }
	assert objc_is_kind(object, ios_runtime.names['NSLocale'])
	assert string_text(obj_header(object).fields[0]) == expected
}

fn (api LocaleApi) drop_object(object u64) {
	$if macos { if api.native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}

fn (api LocaleApi) destroy(value u64) {
	unsafe { LocaleDestroy(voidptr(read64(api.witness + 8) & 0x0000ffffffffffff))(value, api.metadata) }
}

fn locale_case(api LocaleApi, source string, expected string, owned bool, at_end bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	value := span + u64(page) + if at_end { u64(page) - 16 } else { u64(0) }
	words := if owned { api.cstring(source.str) } else { swift_string_literal(source.str, i64(source.len), true) }
	heap := words.second != 0 && words.second & (u64(1) << 63) == 0
	mut refs := u64(0)
	if heap { api.keep(words.second); refs = read64(words.second + 8) }
	api.call(api.entries[0], words.first, words.second, span, value)
	if heap { assert read64(words.second + 8) == refs - (u64(1) << 33); api.drop(words.second) }
	assert read64(value) != 0 && read64(value + 8) != 0
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	identifier := api.call(api.entries[1], span, span, value, span)
	api.check_string(identifier[0], identifier[1], expected)
	bridge := api.call(api.entries[2], span, span, value, span)[0]
	api.check_object(bridge, expected)
	mut copies := [4]u64{}
	for i, slot in [0, 2]! {
		destination := u64(unsafe { &copies[i * 2] })
		copy_value := unsafe { LocaleCopy(voidptr(read64(api.witness + u64(slot * 8)) & 0x0000ffffffffffff)) }
		assert copy_value(destination, value, api.metadata) == destination
	}
	first_copy := u64(unsafe { &copies[0] })
	second_copy := u64(unsafe { &copies[2] })
	assign_copy := unsafe { LocaleCopy(voidptr(read64(api.witness + 24) & 0x0000ffffffffffff)) }
	assert assign_copy(first_copy, second_copy, api.metadata) == first_copy
	mut moved := [2]u64{}
	moved_value := u64(unsafe { &moved[0] })
	take_value := unsafe { LocaleCopy(voidptr(read64(api.witness + 32) & 0x0000ffffffffffff)) }
	assert take_value(moved_value, first_copy, api.metadata) == moved_value
	assign_take := unsafe { LocaleCopy(voidptr(read64(api.witness + 40) & 0x0000ffffffffffff)) }
	assert assign_take(second_copy, moved_value, api.metadata) == second_copy
	api.destroy(value)
	// A surviving copy and both owned results outlive the original. The take
	// operations transferred ownership out of first_copy and moved_value.
	api.check_string(identifier[0], identifier[1], expected)
	api.check_object(bridge, expected)
	for i in 1 .. 2 {
		copy := u64(unsafe { &copies[i * 2] })
		text := api.call(api.entries[1], span, span, copy, span)
		api.check_string(text[0], text[1], expected); api.drop(text[1]); api.destroy(copy)
	}
	api.check_object(bridge, expected); api.drop_object(bridge)
	api.check_string(identifier[0], identifier[1], expected); api.drop(identifier[1])
	assert C.munmap(voidptr(span), page * 3) == 0
}

fn locale_worker(api LocaleApi) {
	for _ in 0 .. 8 { locale_case(api, 'en_US_POSIX', 'en_US_POSIX', true, true); locale_case(api, 'zh_Hant_TW_POSIX', 'zh-Hant_TW_POSIX', true, false) }
}

fn locale_suite(api LocaleApi) {
	for pair in [['en_US_POSIX','en_US_POSIX']!, ['EN_us_POSIX','en_US_POSIX']!, ['en_US_posix','en_US_POSIX']!,
		['en-US','en-US']!, ['EN-us','en-US']!, ['en_us','en_US']!, ['de_DE','de_DE']!,
		['zh-Hant-TW','zh-Hant-TW']!, ['ZH-hANT-tw','zh-Hant-TW']!, ['sr_Latn_RS','sr-Latn_RS']!,
		['sr_Latn_RS_POSIX','sr-Latn_RS_POSIX']!, ['zh_Hant_TW_POSIX','zh-Hant_TW_POSIX']!,
		['en-US-POSIX','en-US-posix']!, ['en-us-posix','en-US-posix']!, ['es_419','es_419']!,
		['iw_IL','he_IL']!, ['in_ID','id_ID']!, ['ji_US','yi_US']!, ['ru_RU','ru_RU']!, ['fr-FR','fr-FR']!,
		['C','c']!, ['POSIX','posix']!, ['','']!, ['en__POSIX','en__POSIX']!]! {
		for owned in [false, true]! { for at_end in [false, true]! { locale_case(api, pair[0], pair[1], owned, at_end) } }
	}
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn locale_worker(api) }
	workers.wait(); unsafe { workers.free() }
	store := unsafe { LocaleStore(voidptr(read64(api.witness + 56) & 0x0000ffffffffffff)) }
	get := unsafe { LocaleTag(voidptr(read64(api.witness + 48) & 0x0000ffffffffffff)) }
	for cases in [u32(0), 1, 255, 0x7fffffff, 0x80000000, 0xffffffff]! {
		for tag in [u32(0), 1, 255, 0x7fffffff, 0x80000000, 0xffffffff]! {
			if tag > cases { continue }
			mut bytes := [40]u8{}
			for i in 0 .. 40 { bytes[i] = 0xa5 }
			value := u64(unsafe { &bytes[5] })
			store(value, tag, cases, api.metadata)
			assert get(value, cases, api.metadata) == tag
			length := if cases > 0x7fffffff { 17 } else { 16 }
			for i in 0 .. 40 { if i < 5 || i >= 5 + length { assert bytes[i] == 0xa5 } }
		}
	}
}

fn locale_publish(overlay bool) u64 {
	library := if overlay { '/usr/lib/swift/libswiftFoundation.dylib' } else { '/System/Library/Frameworks/Foundation.framework/Foundation' }
	mut entry := u64(0)
	for _ in 0 .. 128 { candidate := runtime_symbol(library, '_$s10Foundation6LocaleV10identifierACSS_tcfC') or { panic(err) }; assert entry == 0 || entry == candidate; entry = candidate }
	return entry
}

fn locale_mapping(address u64, count u64, present bool) {
	$if macos {
		mut next := address; mut size := u64(0); mut info := [9]i32{}; mut length := u32(9); mut object := u32(0)
		result := C.vm_region_64(C.mach_task_self(), unsafe { &next }, unsafe { &size }, 9, unsafe { &info[0] }, unsafe { &length }, unsafe { &object })
		if object != 0 { assert C.mach_port_deallocate(C.mach_task_self(), object) == 0 }
		if present { assert result == 0 && next <= address && next + size >= address + count && info[0] & C.PROT_WRITE == 0 }
		else { assert result != 0 || next >= address + count }
	} $else {
		maps := os.read_file('/proc/self/maps') or { panic(err) }; mut found := false
		for line in maps.split_into_lines() { columns := line.fields(); if columns.len < 2 { continue }; ends := columns[0].split('-'); if ends.len != 2 { continue }; start := strconv.parse_uint(ends[0], 16, 64) or { panic(err) }; end := strconv.parse_uint(ends[1], 16, 64) or { panic(err) }; if start <= address && end >= address + count { found = true; assert columns[1][1] != `w` } }
		assert found == present
	}
}

fn test_swift_locale() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0503f3,
		0xaa0403e8, 0xaa0303f4, 0xaa0103e0, 0xaa0203e1, 0xd28a0435, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 68)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos { locale_suite(locale_api(true, code)); println('IOS-SWIFT-LOCALE-NATIVE: native fixed identifiers, consuming String, guarded result and borrowed Self, owned identifier/NSLocale, independent copies and concurrent construction measured') }
	for name in locale_names() { if _ := swift_foundation_symbol(name) { assert false } }
	for _ in 0 .. 2 {
		objc_start(); baseline := ios_runtime.live
		mut workers := []thread u64{}
		for i in 0 .. 8 { workers << spawn locale_publish(i % 2 == 0) }
		entries := workers.wait(); for entry in entries { assert entry == entries[0] }; unsafe { workers.free(); entries.free() }
		api := locale_api(false, code); arena := ios_runtime.swift_foundation_arena
		locale_mapping(arena, 2328, true); locale_mapping(arena + u64(page), 1504, true)
		locale_suite(api)
		for text in ['zh_hant_tw','en_US.UTF-8','de_DE@currency=EUR','en-US-u-ca-buddhist','xx_YY','😀','en_ABCDE','en\x00US']! {
			input := swift_string_literal(text.str, i64(text.len), false); buffer := u64(C.__builtin_alloca(128))
			if _ := swift_locale_canonical_checked(input.first, input.second, buffer) { assert false, text }
		}
		for name in locale_names() { if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) { assert false }; if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', name) { assert false } }
		for name in ['_$s10Foundation6LocaleVN', '_$s10Foundation6LocaleV7currentACvgZ', '_$s10Foundation6LocaleVSHAAMc']! { if _ := swift_foundation_symbol(name) { assert false } }
		assert ios_runtime.live == baseline && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0
		objc_stop(); locale_mapping(arena, u64(page) * 2, false)
		for name in locale_names() { if _ := swift_foundation_symbol(name) { assert false } }
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-SWIFT-LOCALE: native fixed-locale identifiers, consuming inline/literal/heap String, guarded resilient result, borrowed getters and owned NSLocale, value-copy/result lifetime independence, concurrent construction/publication, scoped aliases and two drained/unmapped runtimes')
}
