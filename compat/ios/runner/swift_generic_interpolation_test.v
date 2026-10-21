// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type GiLiteral = fn (&u8, i64, bool) SwiftStringWords
type GiCtor = fn (i64, i64) SwiftStringWords
type GiRetain = fn (u64) u64
type GiDrop = fn (u64)
type GiProbe = fn (u64, u64, u64, u64, u64, &u64)
struct GiApi {
	native bool
	entry u64
	code u64
	literal_entry u64
	string_type u64
	int_type u64
	bool_type u64
	static_type u64
	void_type u64
	merge_type u64
	literal GiLiteral @[required]
	ctor GiCtor @[required]
	retain GiRetain @[required]
	drop GiDrop @[required]
}
fn gi_emit(code u64) {
	// C source/type/destination/entry/guard/capture -> Swift source/type,
	// inout x20, opaque x21/x22 and inaccessible x2/x3/x8. Capture contexts.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f4,
		0xaa0303f0, 0xaa0503f3, 0xaa0403f5, 0x91004096, 0xaa0403e8,
		0xaa0403e2, 0xaa0403e3, 0xd63f0200, 0xa9005674, 0xf9000a76,
		0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
}
fn gi_invoke(api GiApi, entry u64, first u64, second u64, destination u64, guard u64) {
	mut capture := [u64(0xCAFE), 0, 0, 0, 0xBEEF]!
	unsafe { GiProbe(voidptr(api.code))(first, second, destination, entry, guard, &capture[1]) }
	assert capture == [u64(0xCAFE), destination, guard, guard + 16, 0xBEEF]!
}
fn gi_expect(words SwiftStringWords, expected string) {
	mut scratch := [u64(0), 0]!
	bytes := swift_string_bytes(words, u64(unsafe { &scratch[0] })) or { panic(err) }
	assert bytes.count == u64(expected.len) && C.memcmp(voidptr(bytes.address), expected.str, usize(expected.len)) == 0
}
fn gi_call(api GiApi, source u64, metadata u64, expected string, _reenter bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 6, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert span != u64(-1)
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	assert C.mprotect(voidptr(span + u64(page * 4)), page, C.PROT_READ | C.PROT_WRITE) == 0
	size := if metadata == api.string_type { u64(16) } else if metadata == api.int_type { u64(8) }
		else if metadata == api.bool_type { u64(1) } else if metadata == api.static_type { u64(24) } else { u64(0) }
	prefix := api.literal(c'pre[', 4, true);suffix := api.literal(c']post', 5, true)
	full := 'pre[' + expected + ']post'
	for source_tail in [false, true]! { for destination_tail in [false, true]! {
		for reserve in [i64(0), 128]! { for alias in [false, true]! {
			input := if size == 0 { span } else { span + u64(page) + if source_tail { u64(page) - size } else { u64(0) } }
			if size != 0 { C.memcpy(voidptr(input), voidptr(source), usize(size)) }
			assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
			destination := span + u64(page * 4) + if destination_tail { u64(page) - 16 } else { u64(0) }
			unsafe { *(&SwiftStringWords(destination)) = api.ctor(reserve, 1) }
			gi_invoke(api, api.literal_entry, prefix.first, prefix.second, destination, span)
			saved := unsafe { *(&SwiftStringWords(destination)) }
			if alias { api.retain(saved.second) }
			mut owner := u64(0)
			if metadata == api.string_type {
				words := unsafe { *(&SwiftStringWords(input)) }
				if words.second & (u64(1) << 63) == 0 { owner = words.second & swift_address_mask }
			}
			refs := if owner != 0 { read64(owner + 8) } else { u64(0) }
			gi_invoke(api, api.entry, input, metadata, destination, span)
			if size != 0 { assert C.memcmp(voidptr(input), voidptr(source), usize(size)) == 0 }
			if owner != 0 { assert read64(owner + 8) == refs }
			gi_invoke(api, api.literal_entry, suffix.first, suffix.second, destination, span)
			gi_expect(unsafe { *(&SwiftStringWords(destination)) }, full)
			if alias { gi_expect(saved, 'pre[');api.drop(saved.second) }
			api.drop(unsafe { (*(&SwiftStringWords(destination))).second })
			assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
		} }
	} }
	api.drop(prefix.second);api.drop(suffix.second)
	unsafe { full.free() }
	assert C.munmap(voidptr(span), page * 6) == 0
}
fn gi_cases(api GiApi, guard u64) {
	for text in ['', 'plain', 'π/🎮/é', 'a\x00b', '123456789012345', '1234567890123456',
		'long independently owned generic interpolation source']! {
		mut value := api.ctor(128, 0)
		words := api.literal(text.str, i64(text.len), text.is_ascii())
		gi_invoke(api, api.literal_entry, words.first, words.second, u64(unsafe { &value }), guard)
		gi_call(api, u64(unsafe { &value }), api.string_type, text, false)
		gi_expect(value, text);api.drop(value.second);api.drop(words.second)
	}
	for value in [i64(0), 1, -1, 9223372036854775807, -9223372036854775807 - 1]! {
		text := value.str();gi_call(api, u64(unsafe { &value }), api.int_type, text, false);unsafe { text.free() }
	}
	for value in [u8(0), 1]! { gi_call(api, u64(unsafe { &value }), api.bool_type, if value == 0 { 'false' } else { 'true' }, false) }
	for text in ['', 'StaticString payload owns these temporary source bytes', 'a\x00b', 'π 🎮']! {
		mut value := [u64(text.str), u64(text.len), if text.is_ascii() { u64(2) } else { u64(0) }]!
		gi_call(api, u64(unsafe { &value[0] }), api.static_type, text, false)
	}
	for pair in [[u64(0x41), 3]!, [u64(0), 3]!, [u64(0x1f3ae), 1]!]! {
		mut value := [pair[0], u64(0), pair[1]]!
		gi_call(api, u64(unsafe { &value[0] }), api.static_type, if pair[0] == 0x41 { 'A' } else if pair[0] == 0 { '\x00' } else { '🎮' }, false)
	}
	gi_call(api, guard, api.void_type, '()', false)
	gi_call(api, guard, api.merge_type, 'keyCollision', false)
}
fn gi_worker(api GiApi, guard u64) {
	mut value := i64(-17)
	gi_call(api, u64(unsafe { &value }), api.int_type, '-17', false)
}
fn gi_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss26DefaultStringInterpolationV06appendC0yyxlF') or { panic(err) }
}
fn gi_invalid(api GiApi, guard u64) {
	mut destination := api.ctor(64, 0);before := destination
	for metadata in [u64(0), guard, api.int_type + 1]! {
		if _ := swift_generic_interpolation_checked(guard, metadata, u64(unsafe { &destination })) { assert false }
		assert destination == before
	}
	for target in [u64(0), 1, ~u64(0) - 7]! {
		if _ := swift_generic_interpolation_checked(guard, guard, target) { assert false }
	}
	mut bad := u8(2)
	if _ := swift_generic_interpolation_checked(u64(unsafe { &bad }), api.bool_type, u64(unsafe { &destination })) { assert false }
	assert destination == before;api.drop(destination.second)
}
fn gi_image(api GiApi, base u64, page u64) {
	// Same single-case, zero-payload shape as the required TimePeriod.daily.
	// Native reflection and Vinix both consume this complete nominal record.
	witness := base + 64
	metadata := base + 200
	descriptor := base + 240
	fields := base + 288
	parent := base + 336
	native_witness := read64(api.merge_type - 8) & 0x0000ffffffffffff
	C.memcpy(voidptr(witness), voidptr(native_witness), 112)
	unsafe {
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x201
		*(&u64(metadata + 8)) = descriptor
	}
	write32(descriptor, 0x52)
	swift_protocol_relative(descriptor + 4, parent)
	swift_protocol_relative(descriptor + 8, base + 384)
	swift_protocol_relative(descriptor + 16, fields)
	write32(descriptor + 24, 1)
	write32(fields + 8, 0x000c0002)
	write32(fields + 12, 1)
	swift_protocol_relative(fields + 24, base + 416)
	swift_protocol_relative(parent + 8, base + 448)
	C.memcpy(voidptr(base + 384), c'TimePeriod', 11)
	C.memcpy(voidptr(base + 416), c'daily', 6)
	C.memcpy(voidptr(base + 448), c'PrintFixture', 13)
	if !api.native {
		mut loaded := LoadedModule{ image: macho.Image{ segments: [macho.Segment{ name: '__DATA_CONST', address: 0, size: page, filesize: page, prot: 1 }] }, layout: macho.Layout{ base: 0, size: page }, base: base }
		mut runtime := ModuleRuntime{ modules: [&loaded] }
		assert module_runtime == unsafe { nil }
		module_runtime = unsafe { &runtime }
		defer { module_runtime = unsafe { nil } }
		assert C.mprotect(voidptr(base), usize(page), C.PROT_READ) == 0
		gi_call(api, base + page, metadata, 'daily', false)
		assert C.mprotect(voidptr(base), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
		write32(descriptor + 20, 1)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		write32(descriptor + 20, 0)
		write32(fields + 20, 1)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		write32(fields + 20, 0)
		write32(witness + 64, 1)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		write32(witness + 64, 0)
		swift_protocol_relative(descriptor + 16, fields + 2)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		swift_protocol_relative(descriptor + 16, fields)
		// A concrete image conformance must not be silently replaced by the
		// reflection fallback, including an indirect protocol reference.
		mut with_protocol := LoadedModule{ image: macho.Image{ segments: [macho.Segment{ name: '__DATA_CONST', address: 0, size: page, filesize: page, prot: 1, sections: [macho.Section{ name: '__swift5_proto', address: 512, size: 4 }] }] }, layout: macho.Layout{ base: 0, size: page }, base: base }
		runtime.modules = [unsafe { &with_protocol }]
		swift_protocol_relative(base + 512, base + 544)
		swift_protocol_relative(base + 548, descriptor)
		swift_protocol_relative(base + 544, base + 600)
		swift_protocol_relative(base + 608, base + 704)
		for name in ['TextOutputStreamable', 'CustomStringConvertible', 'CustomDebugStringConvertible']! {
			C.memcpy(voidptr(base + 704), name.str, usize(name.len + 1))
			if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
				assert false
			}
		}
		unsafe { *(&u64(base + 640)) = ios_runtime.swift_metadata_arena + u64(C.getpagesize()) + 352 }
		swift_protocol_relative(base + 544, base + 641)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		swift_protocol_relative(base + 512, base + 546)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		swift_protocol_relative(base + 512, base + 544)
		swift_protocol_relative(base + 544, base + 643)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		write32(base + 556, 8)
		swift_protocol_relative(base + 548, base + 673)
		if _ := swift_generic_interpolation_checked(base + page, metadata, base + page) {
			assert false
		}
		return
	}
	assert C.mprotect(voidptr(base), usize(page), C.PROT_READ) == 0
	gi_call(api, base + page, metadata, 'daily', false)
	assert C.mprotect(voidptr(base), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
}


fn test_swift_generic_interpolation() {
	page := usize(C.getpagesize());code := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert code != u64(-1)
	gi_emit(code);C.__builtin___clear_cache(voidptr(code), voidptr(code + 72));assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	fixture := code + u64(page);guard := code + u64(page * 2);assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert core != unsafe { nil }
		api := GiApi{native: true, entry: u64(C.dlsym(core, c'$ss26DefaultStringInterpolationV06appendC0yyxlF')), code: code,
			literal_entry: u64(C.dlsym(core, c'$ss26DefaultStringInterpolationV13appendLiteralyySSF')),
			string_type: u64(C.dlsym(core, c'$sSSN')), int_type: u64(C.dlsym(core, c'$sSiN')), bool_type: u64(C.dlsym(core, c'$sSbN')),
			static_type: u64(C.dlsym(core, c'$ss12StaticStringVN')), void_type: u64(C.dlsym(core, c'$sytN')) + 8, merge_type: u64(C.dlsym(core, c'$ss11_MergeErrorON')),
			literal: unsafe { GiLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) },
			ctor: unsafe { GiCtor(C.dlsym(core, c'$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC')) },
			retain: unsafe { GiRetain(C.dlsym(core, c'swift_bridgeObjectRetain')) }, drop: unsafe { GiDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) }}
		assert api.entry != 0;gi_cases(api, guard);gi_image(api, fixture, u64(page));C.memset(voidptr(fixture), 0, page)
		println('NATIVE-GENERIC-INTERPOLATION: borrowed String/Int/Bool/Void/StaticString/enum values, Unicode/NUL and signed extrema, protected input/output boundaries, retained destination aliases, exact source refcounts and x20/x21/x22')
	}
	assert swift_interpolation_symbol('_$ss26DefaultStringInterpolationV06appendC0yyxlF') == none
	for _ in 0 .. 2 {
		objc_start();mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn gi_publish() };entries := publishers.wait()
		for entry in entries { assert entry == entries[0] }
		api := GiApi{entry: entries[0], code: code, literal_entry: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss26DefaultStringInterpolationV13appendLiteralyySSF') or { panic(err) },
			string_type: swift_string_metadata(), int_type: swift_integer_metadata(), bool_type: (swift_bool_metadata_arena_checked() or { panic(err) }) + u64(page) + 16,
			static_type: (swift_static_string_metadata_arena_checked() or { panic(err) }) + u64(page) + 16, void_type: swift_void_full_metadata() + 8,
			merge_type: (swift_merge_error_metadata_arena_checked() or { panic(err) }) + u64(page) + 16, literal: swift_string_literal,
			ctor: swift_interpolation_init, retain: swift_bridge_retain, drop: swift_bridge_release}
		gi_cases(api, guard);gi_image(api, fixture, u64(page));gi_invalid(api, guard);C.memset(voidptr(fixture), 0, page)
		mut workers := []thread{};for _ in 0 .. 8 { workers << spawn gi_worker(api, guard) };workers.wait()
		unsafe { publishers.free();entries.free();workers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$ss26DefaultStringInterpolationV06appendC0yyxlF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$ss26DefaultStringInterpolationV06appendC0yyxlF') == none
		ios_runtime.swift_concurrency_retired = true;assert swift_interpolation_symbol('_$ss26DefaultStringInterpolationV06appendC0yyxlF') == none
		if _ := swift_generic_interpolation_checked(guard, guard, guard) { assert false };ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		arena := ios_runtime.swift_interpolation_arena;objc_stop()
		assert ios_runtime.swift_interpolation_arena == 0 && C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
		assert swift_interpolation_symbol('_$ss26DefaultStringInterpolationV06appendC0yyxlF') == none
	}
	assert C.munmap(voidptr(code), page * 3) == 0
	println('IOS-GENERIC-INTERPOLATION: bounded borrowed print profile and TimePeriod.daily reflection, prefix/suffix/COW text, protected spans and preserved contexts, exact source ownership, guarded unsupported values, eight cold publishers/workers and two drained/unmapped lifetimes')
}
