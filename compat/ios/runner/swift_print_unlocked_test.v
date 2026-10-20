// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type PuLiteral = fn (&u8, i64, bool) SwiftStringWords
type PuRetain = fn (u64) u64
type PuDrop = fn (u64)
type PuProbe = fn (u64, u64, u64, u64, u64, u64, &u64)
type PuSign = fn (u64, u64) u64

struct PuApi {
	native      bool
	entry       u64
	code        u64
	string_type u64
	int_type    u64
	bool_type   u64
	static_type u64
	void_type   u64
	merge_type  u64
	literal     PuLiteral @[required]
	retain      PuRetain  @[required]
	drop        PuDrop    @[required]
}

struct PuTarget {
	api      PuApi
	metadata u64
	table    u64
	data     u64
	reenter  bool
mut:
	count u64
	calls u64
	held  SwiftStringWords
}

fn pu_write(first u64, second u64, metadata u64, table u64, self u64) {
	mut target := unsafe { &PuTarget(self) }
	assert metadata == target.metadata && table == target.table
	mut scratch := [u64(0), 0]!
	bytes := swift_string_bytes(SwiftStringWords{first, second}, u64(unsafe { &scratch[0] })) or { panic(err) }
	assert target.count + bytes.count <= 131072
	C.memcpy(voidptr(target.data + target.count), voidptr(bytes.address), usize(bytes.count))
	target.count += bytes.count
	target.calls++
	target.api.retain(second)
	target.api.drop(target.held.second)
	target.held = SwiftStringWords{first, second}
	if target.reenter {
		worker := spawn pu_worker(target.api)
		worker.wait()
	}
}

fn pu_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0603f3, 0xd28a0414, 0xd28a2435,
		0xd63f00a0, 0xa9005674, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 64, 0xdac143e0)
	write32(code + 68, 0xdac10020)
	write32(code + 72, 0xd65f03c0)
	write32(code + 128, 0xaa1403e4)
	write32(code + 132, 0x58000070)
	write32(code + 136, 0xd61f0200)
	unsafe { *(&u64(code + 144)) = u64(voidptr(pu_write)) }
}

fn pu_call(api PuApi, source u64, metadata u64, expected string, reenter bool) {
	mut target_metadata := [u64(0x200), 0]!
	mut table := [u64(0), 0, 0, api.code + 128, 0]!
	address := u64(unsafe { &table[0] })
	if api.native {
		unsafe { table[3] = PuSign(voidptr(api.code + 64))(api.code + 128, (address + 24) | (u64(25323) << 48)) }
	}
	data := u64(C.calloc(1, 131072))
	assert data != 0
	defer { C.free(voidptr(data)) }
	mut target := PuTarget{ api: api, metadata: u64(unsafe { &target_metadata[0] }), table: address, data: data, reenter: reenter }
	mut capture := [u64(0xcafe), 0, 0, 0xbeef]!
	unsafe { PuProbe(voidptr(api.code))(source, u64(&target), metadata, target.metadata, address, api.entry, &capture[1]) }
	assert capture == [u64(0xcafe), 0x5020, 0x5121, 0xbeef]!
	assert target.calls > 0 && target.count == u64(expected.len) && C.memcmp(voidptr(data), expected.str, usize(expected.len)) == 0, expected
	if target.calls == 1 {
		mut scratch := [u64(0), 0]!
		held := swift_string_bytes(target.held, u64(unsafe { &scratch[0] })) or { panic(err) }
		assert held.count == u64(expected.len) && C.memcmp(voidptr(held.address), expected.str, usize(expected.len)) == 0
	}
	api.drop(target.held.second)
}

fn pu_worker(api PuApi) {
	mut value := i64(-17)
	pu_call(api, u64(unsafe { &value }), api.int_type, '-17', false)
}

fn pu_cases(api PuApi, guard u64) {
	for text in ['', 'plain', 'π/🎮/é', 'a\x00b',
		'long independently owned text after the callback returns']! {
		mut words := api.literal(text.str, i64(text.len), text.is_ascii())
		saved := words
		pu_call(api, u64(unsafe { &words }), api.string_type, text, false)
		assert words == saved
		api.drop(words.second)
	}
	for number in [i64(0), 1, -1, 9223372036854775807, -9223372036854775807 - 1]! {
		mut value := number
		text := number.str()
		pu_call(api, u64(unsafe { &value }), api.int_type, text, false)
		assert value == number
		unsafe { text.free() }
	}
	for pair in [[u8(0), 0]!, [u8(1), 1]!]! {
		mut value := pair[0]
		pu_call(api, u64(unsafe { &value }), api.bool_type, if value == 0 {
			'false'
		} else {
			'true'
		}, false)
	}
	for text in ['', 'StaticString payload owns this temporary source', 'a\x00b', 'π 🎮']! {
		mut words := [u64(text.str), u64(text.len), if text.is_ascii() { u64(2) } else { u64(0) }]!
		pu_call(api, u64(unsafe { &words[0] }), api.static_type, text, false)
	}
	for pair in [[u64(0x41), 3]!, [u64(0), 3]!, [u64(0x1f3ae), 1]!]! {
		mut words := [pair[0], u64(0), pair[1]]!
		pu_call(api, u64(unsafe { &words[0] }), api.static_type, if pair[0] == 0x41 {
			'A'
		} else if pair[0] == 0 {
			'\x00'
		} else {
			'🎮'
		}, false)
	}
	pu_call(api, guard, api.void_type, '()', false)
	pu_call(api, guard, api.merge_type, 'keyCollision', false)
}

fn pu_image(api PuApi, base u64, page u64) {
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
		pu_call(api, base + page, metadata, 'daily', false)
		assert C.mprotect(voidptr(base), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
		write32(descriptor + 20, 1)
		if _ := swift_print_value_checked(base + page, metadata) {
			assert false
		}
		write32(descriptor + 20, 0)
		write32(fields + 20, 1)
		if _ := swift_print_value_checked(base + page, metadata) {
			assert false
		}
		write32(fields + 20, 0)
		write32(witness + 64, 1)
		if _ := swift_print_value_checked(base + page, metadata) {
			assert false
		}
		write32(witness + 64, 0)
		swift_protocol_relative(descriptor + 16, fields + 2)
		if _ := swift_print_value_checked(base + page, metadata) {
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
			if _ := swift_print_value_checked(base + page, metadata) {
				assert false
			}
		}
		unsafe { *(&u64(base + 640)) = ios_runtime.swift_metadata_arena + u64(C.getpagesize()) + 352 }
		swift_protocol_relative(base + 544, base + 641)
		if _ := swift_print_value_checked(base + page, metadata) {
			assert false
		}
		swift_protocol_relative(base + 512, base + 546)
		if _ := swift_print_value_checked(base + page, metadata) {
			assert false
		}
		swift_protocol_relative(base + 512, base + 544)
		swift_protocol_relative(base + 544, base + 643)
		if _ := swift_print_value_checked(base + page, metadata) {
			assert false
		}
		write32(base + 556, 8)
		swift_protocol_relative(base + 548, base + 673)
		if _ := swift_print_value_checked(base + page, metadata) {
			assert false
		}
		return
	}
	assert C.mprotect(voidptr(base), usize(page), C.PROT_READ) == 0
	pu_call(api, base + page, metadata, 'daily', false)
	assert C.mprotect(voidptr(base), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
}

fn pu_invalid(api PuApi, guard u64) {
	mut owned := swift_interpolation_init(128, 0)
	text := 'owned source survives borrowed generic printing'
	swift_string_append_bytes(u64(unsafe { &owned }), u64(text.str), u64(text.len))
	owner := owned.second
	pu_call(api, u64(unsafe { &owned }), api.string_type, text, false)
	assert owned.second == owner && swift_buffer_refs(owner, 0) or { panic(err) } == 1
	retained := swift_print_value_checked(u64(unsafe { &owned }), api.string_type) or { panic(err) }
	assert retained == owned && swift_buffer_refs(owner, 0) or { panic(err) } == 2
	api.drop(owned.second)
	mut scratch := [u64(0), 0]!
	bytes := swift_string_bytes(retained, u64(unsafe { &scratch[0] })) or { panic(err) }
	assert C.memcmp(voidptr(bytes.address), text.str, usize(text.len)) == 0
	api.drop(retained.second)
	mut value := i64(1)
	before := ios_runtime.swift_strings.len
	for metadata in [u64(0), guard, api.int_type + 1]! {
		if _ := swift_print_value_checked(guard, metadata) {
			assert false
		}
	}
	for source in [u64(0), u64(1)]! {
		if _ := swift_print_value_checked(source, api.int_type) {
			assert false
		}
	}
	mut bad_bool := u8(2)
	if _ := swift_print_value_checked(u64(unsafe { &bad_bool }), api.bool_type) {
		assert false
	}
	for words in [[u64(0x110000), 0, 1]!, [u64(0xd800), 0, 1]!, [u64(0), 0, 2]!, [u64(1), 0, 255]!]! {
		mut bad := words
		if _ := swift_print_value_checked(u64(unsafe { &bad[0] }), api.static_type) {
			assert false
		}
	}
	for args in [[u64(0), 1, guard]!, [u64(1), 0, guard]!, [u64(1), 1, 0]!]! {
		if _ := swift_print_unlocked_checked(u64(unsafe { &value }), args[0], api.int_type, args[1], args[2]) {
			assert false
		}
	}
	assert ios_runtime.swift_strings.len == before
	pu_call(api, u64(unsafe { &value }), api.int_type, '1', true)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn pu_worker(api) }
	workers.wait()
}

fn pu_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss15_print_unlockedyyx_q_zts16TextOutputStreamR_r0_lF') or { panic(err) }
}

fn test_swift_print_unlocked() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	defer { assert C.munmap(voidptr(code), page * 3) == 0 }
	pu_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 152))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	fixture := code + u64(page)
	guard := code + u64(page * 2)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		api := PuApi{ native: true, entry: u64(C.dlsym(lib, c'$ss15_print_unlockedyyx_q_zts16TextOutputStreamR_r0_lF')), code: code, string_type: u64(C.dlsym(lib, c'$sSSN')), int_type: u64(C.dlsym(lib, c'$sSiN')), bool_type: u64(C.dlsym(lib, c'$sSbN')), static_type: u64(C.dlsym(lib, c'$ss12StaticStringVN')), void_type: u64(C.dlsym(lib, c'$sytN')) + 8, merge_type: u64(C.dlsym(lib, c'$ss11_MergeErrorON')), literal: unsafe { PuLiteral(C.dlsym(lib, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }, retain: unsafe { PuRetain(C.dlsym(lib, c'swift_bridgeObjectRetain')) }, drop: unsafe { PuDrop(C.dlsym(lib, c'swift_bridgeObjectRelease')) } }
		assert api.entry != 0
		pu_cases(api, guard)
		pu_image(api, fixture, u64(page))
		C.memset(voidptr(fixture), 0, page)
		println('NATIVE-PRINT-UNLOCKED: borrowed String/Int/Bool/Void/StaticString/enum values, arbitrary signed stream witness, pointer/scalar Unicode and NUL, TimePeriod.daily reflection, callback retention and x20/x21')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn pu_publish() }
		entries := publishers.wait()
		for entry in entries {
			assert entry == entries[0]
		}
		library := '/usr/lib/swift/libswiftCore.dylib'
		api := PuApi{ entry: entries[0], code: code, string_type: swift_string_metadata(), int_type: swift_integer_metadata(), bool_type: (swift_bool_metadata_arena_checked() or { panic(err) }) + u64(page) + 16, static_type: (swift_static_string_metadata_arena_checked() or { panic(err) }) + u64(page) + 16, void_type: runtime_symbol(library, '_$sytN') or { panic(err) }, merge_type: (swift_merge_error_metadata_arena_checked() or { panic(err) }) + u64(page) + 16, literal: swift_string_literal, retain: swift_bridge_retain, drop: swift_bridge_release }
		// The Void symbol exports the full metadata header, unlike its value metadata.
		compat := PuApi{ ...api, void_type: api.void_type + 8 }
		pu_cases(compat, guard)
		pu_image(compat, fixture, u64(page))
		pu_invalid(compat, guard)
		C.memset(voidptr(fixture), 0, page)
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.objects.len == 0
		ios_runtime.swift_concurrency_retired = true
		assert runtime_symbol(library, '_$ss15_print_unlockedyyx_q_zts16TextOutputStreamR_r0_lF') == none
		ios_runtime.swift_concurrency_retired = false
		arena := ios_runtime.swift_interpolation_arena
		objc_stop()
		assert ios_runtime.swift_interpolation_arena == 0 && ios_runtime.swift_print_unlocked_retired
		assert runtime_symbol(library, '_$ss15_print_unlockedyyx_q_zts16TextOutputStreamR_r0_lF') == none
		assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
	}
	println('IOS-PRINT-UNLOCKED: borrowed generic values and arbitrary stream write, retained results, bounded image enum reflection, guarded unsupported values, reentrant callbacks, eight cold publishers/workers and two drained/unmapped lifetimes')
}
