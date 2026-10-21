// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type CkdProbe = fn (u64, u64, u64, u64, &u64)
type CkdSign = fn (u64, u64) u64
type CkdLiteral = fn (&u8, i64, bool) SwiftStringWords
type CkdCString = fn (&u8) SwiftStringWords
type CkdBytes = fn (u64, u64) u64
type CkdDrop = fn (u64)

struct CkdApi {
	native bool
	code u64
	entry u64
	integer u64
	literal CkdLiteral @[required]
	cstring u64
	bytes CkdBytes @[required]
	drop CkdDrop @[required]
}
struct CkdObservation {
mut:
	step int
	owner u64
}
struct CkdValue {
	api CkdApi
	metadata u64
	table u64
	text string
	number i64
	tag u64
	reenter bool
	observation &CkdObservation
}

fn ckd_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss9CodingKeyPsE11descriptionSSvg') or { panic(err) }
}
fn ckd_reenter(value &CkdValue) {
	if value.reenter && !value.api.native {
		worker := spawn ckd_publish()
		assert worker.wait() == value.api.entry
	}
}
fn ckd_integer(metadata u64, table u64, source u64) SwiftStringWords {
	value := unsafe { &CkdValue(source) }
	assert value.metadata == metadata && value.table == table && value.observation.step == 0
	mut observation := value.observation
	observation.step = 1
	ckd_reenter(value)
	return SwiftStringWords{first: u64(value.number), second: value.tag}
}
fn ckd_string(metadata u64, table u64, source u64) SwiftStringWords {
	value := unsafe { &CkdValue(source) }
	assert value.metadata == metadata && value.table == table && value.observation.step == 1
	mut observation := value.observation
	observation.step = 2
	ckd_reenter(value)
	if value.api.native {
		// cString supplies mortal native storage for long inputs. The literal
		// initializer preserves explicit lengths when the text contains NUL.
		words := if value.text.contains('\x00') {
			value.api.literal(value.text.str, i64(value.text.len), value.text.is_ascii())
		} else { unsafe { CkdCString(voidptr(value.api.cstring))(value.text.str) } }
		observation.owner = words.second
		return words
	}
	words := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(words)) = swift_interpolation_init(i64(value.text.len), 0) }
	swift_string_append_bytes(words, u64(value.text.str), u64(value.text.len))
	result := unsafe { *(&SwiftStringWords(words)) }
	observation.owner = result.second
	return result
}
fn ckd_emit(code u64) {
	// C(entry,metadata,table,Self,capture) -> Swift; observe nonthrowing
	// context preservation as well as the owned two-register String result.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0303f4, 0xaa0403f3,
		0xd28a2435, 0xd28a4456, 0xd63f0200, 0xa9000660,
		0xa9015674, 0xf9001276, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for i, target in [u64(voidptr(ckd_integer)), u64(voidptr(ckd_string))]! {
		entry := code + 128 + u64(i * 32)
		write32(entry, 0xaa1403e2); write32(entry + 4, 0x58000070); write32(entry + 8, 0xd61f0200)
		unsafe { *(&u64(entry + 16)) = target }
	}
	write32(code + 192, 0xdac10020); write32(code + 196, 0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 200))
}
fn ckd_assert(api CkdApi, words SwiftStringWords, expected string) {
	buffer := api.bytes(words.first, words.second)
	assert read64(buffer + 16) == u64(expected.len + 1)
	assert C.memcmp(voidptr(buffer + 32), expected.str, usize(expected.len)) == 0
	assert unsafe { *(&u8(buffer + 32 + u64(expected.len))) } == 0
	api.drop(buffer)
}
fn ckd_case(api CkdApi, metadata u64, name string, text string, number i64, tag u64, placement int, reenter bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != ~u64(0)
	defer { assert C.munmap(voidptr(span), page * 5) == 0 }
	for offset in [u64(page), u64(page * 3)]! { assert C.mprotect(voidptr(span + offset), page, C.PROT_READ | C.PROT_WRITE) == 0 }
	source := span + u64(page) + if placement & 1 != 0 { u64(page) - u64(sizeof(CkdValue)) } else { u64(0) }
	table := span + u64(page * 3) + if placement & 2 != 0 { u64(page) - 48 } else { u64(0) }
	mut observation := CkdObservation{}
	unsafe { *(&CkdValue(source)) = CkdValue{api, metadata, table, text, number, tag, reenter, &observation} }
	for pair in [[u64(24), api.code + 160, 0xdcb0]!, [u64(40), api.code + 128, 0xbeb7]!]! {
		mut address := pair[1]
		if api.native { address = unsafe { CkdSign(voidptr(api.code + 192))(address, (table + pair[0]) | (pair[2] << 48)) } }
		unsafe { *(&u64(table + pair[0])) = address }
	}
	for offset in [u64(page), u64(page * 3)]! { assert C.mprotect(voidptr(span + offset), page, C.PROT_READ) == 0 }
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0, 0xbeef]!
	unsafe { CkdProbe(voidptr(api.code))(api.entry, metadata, table, source, &capture[1]) }
	assert capture[0] == 0xcafe && capture[6] == 0xbeef && capture[3] == source && capture[4] == 0x5121 && capture[5] == 0x5222
	assert observation.step == 2
	// A retired getter address can be reused by this output or another
	// worker. Check ownership after joining all callers, without racing the
	// allocation registry or confusing a new owner with the retired one.
	digits := if tag & 255 == 1 { 'nil' } else { number.str() }
	expected := name + '(stringValue: "' + text + '", intValue: ' + digits + ')'
	result := SwiftStringWords{capture[1], capture[2]}
	ckd_assert(api, result, expected)
	// Keep two independent outputs alive and release them in either order.
	observation.step = 0
	unsafe { CkdProbe(voidptr(api.code))(api.entry, metadata, table, source, &capture[1]) }
	api.drop(result.second)
	ckd_assert(api, SwiftStringWords{capture[1], capture[2]}, expected)
	api.drop(capture[2])
	unsafe { expected.free(); if tag & 255 != 1 { digits.free() } }
}
fn ckd_worker(api CkdApi) {
	for i in 0 .. 8 { ckd_case(api, api.integer, 'Int', 'worker owned getter text', i64(i - 4), u64(i & 1), i & 3, false) }
}
fn ckd_cases(api CkdApi) {
	for placement in 0 .. 4 {
		for text in ['', 'plain', 'quote" slash\\ line\n\t\r\x00π🎮', 'long mortal String returned by a supplied CodingKey witness']! {
			for number in [i64(0), -7, 9223372036854775807, -9223372036854775807 - 1]! {
				for tag in [u64(0), 0xabcdef01]! { ckd_case(api, api.integer, 'Int', text, number, tag, placement, false) }
			}
		}
	}
	ckd_case(api, api.integer, 'Int', 'reentrant supplied getter', -1, 0, 3, true)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn ckd_worker(api) }
	workers.wait(); unsafe { workers.free() }
	if !api.native { assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 }
}
fn ckd_image(api CkdApi) {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != ~u64(0)
	defer { assert C.munmap(voidptr(base), page) == 0 }
	metadata := base + 16; descriptor := base + 64; parent := base + 128; module_record := base + 192
	unsafe { *(&u64(metadata - 8)) = read64(api.integer - 8) & 0x0000ffffffffffff; *(&u64(metadata + 8)) = descriptor }
	swift_protocol_relative(descriptor + 4, parent); swift_protocol_relative(descriptor + 8, base + 256)
	swift_protocol_relative(parent + 4, module_record); swift_protocol_relative(parent + 8, base + 288)
	swift_protocol_relative(module_record + 8, base + 320)
	C.memcpy(voidptr(base + 256), c'CodingKeys', 11); C.memcpy(voidptr(base + 288), c'Outer', 6); C.memcpy(voidptr(base + 320), c'Fixture', 8)
	write32(parent, 0x51)
	mut loaded := LoadedModule{ image: macho.Image{ segments: [macho.Segment{ name: '__DATA_CONST', address: 0, size: u64(page), filesize: u64(page), prot: 1 }] }, layout: macho.Layout{ base: 0, size: u64(page) }, base: base }
	mut runtime := ModuleRuntime{ modules: [&loaded] }
	if !api.native { assert module_runtime == unsafe { nil }; module_runtime = unsafe { &runtime } }
	defer { if !api.native { module_runtime = unsafe { nil } } }
	for kind in [u64(0x200), 0x201]! {
		unsafe { *(&u64(metadata)) = kind }; write32(descriptor, if kind == 0x200 { u32(0x51) } else { u32(0x52) })
		assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0
		ckd_case(api, metadata, 'CodingKeys', 'nested nominal', -17, 0, 3, false)
		assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	if !api.native {
		for flags in [u32(0xd2), 0x53, 0x51, 0]! { write32(descriptor, flags); if _ := swift_coding_key_name(metadata) { assert false } }
		write32(descriptor, 0x52); write32(descriptor + 8, 0); if _ := swift_coding_key_name(metadata) { assert false }
		swift_protocol_relative(descriptor + 8, base + u64(page) - 1); unsafe { *(&u8(base + u64(page) - 1)) = `a` }
		if _ := swift_coding_key_name(metadata) { assert false }
	}
}
fn ckd_invalid(api CkdApi, guard u64) {
	for pointer in [u64(0), 1, ~u64(0), guard]! { if _ := swift_coding_key_description_checked(pointer, guard, guard) { assert false } }
	for table in [u64(0), 1, ~u64(0)]! { if _ := swift_coding_key_description_checked(api.integer, table, guard) { assert false } }
	if _ := swift_coding_key_description_checked(api.integer, guard, 0) { assert false }
	mut table := [6]u64{}
	if _ := swift_coding_key_description_checked(api.integer, u64(unsafe { &table[0] }), guard) { assert false }
	mut observation := CkdObservation{}
	mut value := CkdValue{ api: api, metadata: api.integer, table: u64(unsafe { &table[0] }), text: 'owned invalid UTF8', observation: &observation, tag: 2 }
	table[5] = api.code + 128; table[3] = api.code + 160
	if _ := swift_coding_key_description_checked(api.integer, value.table, u64(unsafe { &value })) { assert false }
	assert observation.step == 1
	// Malformed owned UTF-8 must still release the getter's mortal String.
	mut invalid := 'x'.repeat(32); unsafe { invalid.str[0] = 255 }
	observation.step = 0
	bad := CkdValue{ ...value, text: invalid, tag: 0 }
	if _ := swift_coding_key_description_checked(api.integer, bad.table, u64(unsafe { &bad })) { assert false }
	assert observation.step == 2 && observation.owner !in ios_runtime.swift_strings
	unsafe { invalid.free() }
	// The output cap includes punctuation, not just the getter's payload.
	large := 'x'.repeat(1048576); observation.step = 0
	bounded := CkdValue{ ...value, text: large, tag: 1 }
	if _ := swift_coding_key_description_checked(api.integer, bounded.table, u64(unsafe { &bounded })) { assert false }
	assert observation.owner !in ios_runtime.swift_strings
	unsafe { large.free() }
}
fn test_swift_coding_key_description() {
	$if !arm64 { return }
	page := usize(C.getpagesize()); code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != ~u64(0); ckd_emit(code)
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(code + u64(page)), page, C.PROT_NONE) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert core != unsafe { nil }
		api := CkdApi{ native: true, code: code, entry: u64(C.dlsym(core, c'$ss9CodingKeyPsE11descriptionSSvg')), integer: u64(C.dlsym(core, c'$sSiN')),
			literal: unsafe { CkdLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }, cstring: u64(C.dlsym(core, c'$sSS7cStringSSSPys4Int8VG_tcfC')),
			bytes: unsafe { CkdBytes(C.dlsym(core, c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }, drop: unsafe { CkdDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) } }
		assert api.entry != 0; ckd_cases(api); ckd_image(api)
		println('NATIVE-CODING-KEY-DESCRIPTION: slots40/24 and callback order, unqualified nested names, verbatim Unicode/NUL/quotes, optional signed limits, guarded borrowed Self/table and preserved x20/x21/x22, owned results and eight callers')
	}
	assert swift_coding_key_description_symbol('_$ss9CodingKeyPsE11descriptionSSvg') == none
	for order in 0 .. 2 {
		objc_start(); assert ios_runtime.swift_hash_code == 0
		for symbol in ['_$ss9CodingKeyPsE11descriptionSSvgExtra', '$ss9CodingKeyPsE11descriptionSSvg', '_$ss9CodingKeyPsE16debugDescriptionSSvg']! { assert swift_coding_key_description_symbol(symbol) == none }
		ios_runtime.swift_concurrency_retired = true; assert swift_coding_key_description_symbol('_$ss9CodingKeyPsE11descriptionSSvg') == none; ios_runtime.swift_concurrency_retired = false
		if order == 1 { swift_hash_entry(1792) }
		mut publishers := []thread u64{}; for _ in 0 .. 8 { publishers << spawn ckd_publish() }; entries := publishers.wait()
		for entry in entries { assert entry == entries[0] }; unsafe { publishers.free() }
		api := CkdApi{ code: code, entry: entries[0], integer: swift_integer_metadata(), literal: swift_string_literal, bytes: swift_string_utf8_cstring, drop: swift_bridge_release }
		unsafe { entries.free() }
		assert api.entry == ios_runtime.swift_hash_code + 1824
		ckd_cases(api); ckd_image(api); ckd_invalid(api, code + u64(page))
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0
		ios_runtime.swift_concurrency_retired = true
		if _ := swift_coding_key_description_checked(api.integer, code + u64(page), code + u64(page)) { assert false }
		assert swift_coding_key_description_symbol('_$ss9CodingKeyPsE11descriptionSSvg') == none
		objc_stop(); assert ios_runtime.swift_hash_code == 0
		assert C.mprotect(voidptr(api.entry - 1824), page, C.PROT_READ) == -1
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-CODING-KEY-DESCRIPTION: supplied getters and owned results, bounded nominal names, verbatim Unicode/NUL, signed optional limits, guarded readonly Self/table, reentrant callbacks, eight publishers/callers and two drained/unmapped lifetimes')
}
