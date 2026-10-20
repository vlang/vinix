// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
}
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFStringCreateMutableCopy(voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)

type SswCall = fn (u64, u64, u64) i64
type SswLiteral = fn (&u8, i64, bool) SwiftStringWords
type SswProbe = fn (u64, u64, u64, u64, u64, &u64)
struct SswApi {
	native bool
	entry SswCall @[required]
	literal SswLiteral @[required]
	probe SswProbe @[required]
	guard u64
}

fn ssw_row(row u64, text string) {
	unsafe {
		*(&u64(row)) = u64(text.str)
		*(&u64(row + 8)) = u64(text.len)
		*(&u64(row + 16)) = 0xa5a5a5a5a5a5a500 | if text.is_ascii() { u64(2) } else { u64(0) }
	}
}

fn ssw_call(api SswApi, owner u64, words SwiftStringWords, expected i64) {
	assert api.entry(owner, words.first, words.second) == expected
	mut out := [u64(0xcafe), 0, 0, 0, 0xbeef]!
	api.probe(owner, words.first, words.second, u64(unsafe { voidptr(api.entry) }), api.guard, unsafe { &out[1] })
	assert out == [u64(0xcafe), u64(expected), 0x5020, 0x5021, 0xbeef]!
}

fn ssw_units(text string) u64 {
	mut units := u64(0)
	for byte in text { if byte & 0xc0 != 0x80 { units += if byte >= 240 { u64(2) } else { u64(1) } } }
	return units
}

fn ssw_queries(api SswApi, owner u64) {
	for pair in [['', '0']!, ['alpha', '1']!, ['é', '2']!, ['é', '2']!, ['a\x00b', '4']!,
		['long pointer case exceeds inline storage', '5']!, ['🎮', '6']!, ['각', '7']!, ['각', '7']!,
		['Ａ', '8']!, ['K', '9']!, ['K', '9']!, ['ạ́', '12']!, ['ạ́', '12']!, ['A', '-1']!,
		['k', '-1']!, ['Alpha', '-1']!, ['a\x00', '-1']!, ['missing', '-1']!]! {
		text := pair[0];expected := pair[1].i64()
		words := api.literal(text.str, text.len, text.is_ascii())
		ssw_call(api, owner, words, expected)
		if api.native {
			$if macos {
				constant := C.CFStringCreateWithBytes(unsafe { nil }, text.str, text.len, 0x08000100, false)
				foreign := C.CFStringCreateMutableCopy(unsafe { nil }, 0, constant);C.CFRelease(constant)
				assert foreign != unsafe { nil };refs := C.CFGetRetainCount(foreign)
				ssw_call(api, owner, SwiftStringWords{ssw_units(text), u64(foreign) | u64(0x5000000000000000)}, expected)
				assert C.CFGetRetainCount(foreign) == refs;C.CFRelease(foreign)
			}
		} else {
			foreign := owned_string(text);refs := obj_header(foreign).refs
			ssw_call(api, owner, SwiftStringWords{ssw_units(text), foreign | u64(0x5000000000000000)}, expected)
			assert obj_header(foreign).refs == refs;objc_release(foreign)
		}
	}
}

fn ssw_worker(api SswApi, owner u64) {
	for _ in 0 .. 24 {
		if !api.native {
			assert (runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStF') or { panic(err) }) == u64(unsafe { voidptr(api.entry) })
		}
		text := 'é';words := api.literal(text.str, text.len, false)
		assert api.entry(owner, words.first, words.second) == 2
	}
}

fn ssw_cases(api SswApi, owner u64) {
	ssw_queries(api, owner)
	mut readers := []thread{}
	for _ in 0 .. 8 { readers << spawn ssw_worker(api, owner) }
	readers.wait();unsafe { readers.free() }
	if !api.native {
		text := 'long pointer case exceeds inline storage'
		mut tail := swift_string_empty()
		swift_string_append_bytes(u64(unsafe { &tail }), u64(text.str), u64(text.len))
		refs := read64((tail.second & swift_address_mask) + 8)
		ssw_call(api, owner, tail, 5)
		assert read64((tail.second & swift_address_mask) + 8) == refs
		swift_bridge_release(tail.second)
	}
}

fn ssw_image(api SswApi, address u64, length u64, owner u64, full bool) {
	if api.native {
		if full { ssw_cases(api, owner) } else { ssw_call(api, owner, SwiftStringWords{api.guard, api.guard}, -1) }
		return
	}
	mut loaded := LoadedModule{image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', address: 0, size: length, filesize: length, prot: 1}]}, layout: macho.Layout{base: 0, size: length}, base: address}
	mut runtime := ModuleRuntime{modules: [&loaded]}
	assert module_runtime == unsafe { nil };module_runtime = unsafe { &runtime }
	defer { module_runtime = unsafe { nil } }
	if full { ssw_cases(api, owner) } else { ssw_call(api, owner, SwiftStringWords{api.guard, api.guard}, -1) }
}

fn ssw_suite(api SswApi) {
	texts := ['', 'alpha', 'é', 'é', 'a\x00b', 'long pointer case exceeds inline storage', '🎮', '각', 'Ａ', 'K', 'alpha', 'A\x00B', 'ạ́']
	page := usize(C.getpagesize())
	owner := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert owner != u64(-1)
	unsafe { *(&u64(owner + 8)) = 0x80000004ffffffff;*(&u64(owner + 16)) = u64(texts.len);*(&u64(owner + 24)) = u64(texts.len * 2) }
	for i, text in texts { ssw_row(owner + 32 + u64(i * 24), text) }
	assert C.mprotect(voidptr(owner), page, C.PROT_READ) == 0
	ssw_image(api, owner, u64(page), owner, true)
	assert read64(owner + 16) == u64(texts.len) && read64(owner + 8) == 0x80000004ffffffff
	if !api.native {
		metadata := (swift_static_string_metadata_arena_checked() or { panic(err) }) + u64(page) + 16
		allocation := swift_array_allocate(texts.len, metadata)
		for i, text in texts { ssw_row(allocation.bytes + u64(i * 24), text) }
		ssw_cases(api, allocation.owner)
		assert read64(allocation.owner + 8) == 3 && ios_runtime.swift_arrays.len == 1
		swift_release(allocation.owner)
		ssw_call(api, swift_array_empty(), SwiftStringWords{api.guard, api.guard}, -1)
	}
	assert C.munmap(voidptr(owner), page) == 0
	// Empty tables read only their count; neither capacity/tail nor String is needed.
	empty := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert empty != u64(-1);assert C.mprotect(voidptr(empty + u64(page)), page, C.PROT_NONE) == 0
	ssw_image(api, empty, u64(page), empty + u64(page) - 24, false)
	assert C.munmap(voidptr(empty), page * 2) == 0
	unsafe { texts.free() }
}

fn ssw_guarded(api SswApi) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1);assert C.mprotect(voidptr(region + u64(page * 2)), page, C.PROT_NONE) == 0
	mut loaded := LoadedModule{image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', size: u64(page), filesize: u64(page), prot: 1}]}, layout: macho.Layout{size: u64(page)}, base: region}
	mut runtime := ModuleRuntime{modules: [&loaded]}
	if !api.native { assert module_runtime == unsafe { nil };module_runtime = unsafe { &runtime } }
	defer { if !api.native { module_runtime = unsafe { nil } };assert C.munmap(voidptr(region), page * 3) == 0 }
	unsafe { *(&u64(region + 8)) = 0x80000004ffffffff;*(&u64(region + 16)) = 2 }
	for text in ['a\x00b', 'é', 'long guarded nonterminated case data']! {
		end := region + u64(page * 2);start := end - u64(text.len)
		C.memcpy(voidptr(start), text.str, usize(text.len))
		ssw_row(region + 32, text);unsafe { *(&u64(region + 32)) = start }
		// The later case is deliberately invalid and must never be inspected after a hit.
		unsafe { *(&u64(region + 56)) = api.guard;*(&u64(region + 64)) = 1048577;*(&u8(region + 72)) = 1 }
		words := api.literal(text.str, text.len, text.is_ascii());ssw_call(api, region, words, 0)
	}
}

fn ssw_invalid(guard u64) {
	for owner in [u64(0), 1, guard, ~u64(0) - 7]! {
		if _ := swift_string_switch_checked(owner, guard, guard) { assert false }
	}
	metadata := (swift_static_string_metadata_arena_checked() or { panic(err) }) + u64(C.getpagesize()) + 16
	allocation := swift_array_allocate(1, metadata)
	defer { swift_release(allocation.owner) }
	ssw_row(allocation.bytes, 'valid')
	words := swift_string_literal(c'valid', 5, true)
	unsafe { *(&u64(allocation.owner + 16)) = 2 }
	if _ := swift_string_switch_checked(allocation.owner, guard, guard) { assert false }
	unsafe { *(&u64(allocation.owner + 16)) = 1 }
	for row in [[guard, u64(1), 1]!, [u64(0), 0, 2]!, [~u64(0) - 3, 8, 0]!, [guard, 1048577, 0]!, [guard, 0, 4]!]! {
		for i in 0 .. 3 { unsafe { *(&u64(allocation.bytes + u64(i * 8))) = row[i] } }
		if _ := swift_string_switch_checked(allocation.owner, words.first, words.second) { assert false }
	}
	ssw_row(allocation.bytes, 'valid')
	if _ := swift_string_switch_checked(allocation.owner, 0, guard | u64(0x5000000000000000)) { assert false }
	if _ := swift_string_switch_checked(allocation.owner, 0xff, 0xe100000000000000) { assert false }
	ssw_row(allocation.bytes, 'é');unsafe { *(&u8(allocation.bytes + 16)) = 2 }
	if _ := swift_string_switch_checked(allocation.owner, words.first, words.second) { assert false }
	wrong := swift_array_allocate(1, swift_integer_metadata())
	if _ := swift_string_switch_checked(wrong.owner, guard, guard) { assert false };swift_release(wrong.owner)
	for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
		assert runtime_symbol(library, '_$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStF') == none
	}
	for symbol in ['_$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStFExtra', '_$ss30_findStringSwitchCaseWithCache5cases6string5cacheSiSays06StaticB0VG_SSs07_OpaquebC5CacheVztF']! {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) == none
	}
}

fn ssw_limits(guard u64) {
	metadata := (swift_static_string_metadata_arena_checked() or { panic(err) }) + u64(C.getpagesize()) + 16
	allocation := swift_array_allocate(4097, metadata)
	defer { swift_release(allocation.owner) }
	query := swift_string_literal(c'target', 6, true)
	for i in 0 .. 4096 { ssw_row(allocation.bytes + u64(i * 24), 'miss') }
	ssw_row(allocation.bytes + 4095 * 24, 'target')
	unsafe { *(&u64(allocation.owner + 16)) = 4096 }
	assert (swift_string_switch_checked(allocation.owner, query.first, query.second) or { panic(err) }) == 4095
	unsafe { *(&u64(allocation.owner + 16)) = 4097 }
	if _ := swift_string_switch_checked(allocation.owner, guard, guard) { assert false }
	// Sixteen readable MiB are permitted; reject the next extent before its
	// protected payload is inspected. Every NFC temporary is released by equality.
	text := 'x'.repeat(1048576)
	defer { unsafe { text.free() } }
	for i in 0 .. 16 { ssw_row(allocation.bytes + u64(i * 24), text) }
	unsafe { *(&u64(allocation.owner + 16)) = 17;*(&u64(allocation.bytes + 16 * 24)) = guard;*(&u64(allocation.bytes + 16 * 24 + 8)) = 1;*(&u8(allocation.bytes + 16 * 24 + 16)) = 0 }
	if _ := swift_string_switch_checked(allocation.owner, query.first, query.second) { assert false }
}

fn test_swift_string_switch() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0303f0, 0xaa0403e8,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 60));assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page);assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	probe := unsafe { SswProbe(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		api := SswApi{native: true, entry: unsafe { SswCall(C.dlsym(core, c'$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStF')) }, literal: unsafe { SswLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }, probe: probe, guard: guard}
		ssw_suite(api);ssw_guarded(api)
		println('NATIVE-STRING-SWITCH: borrowed x0 table/x1-x2 String, signed first match or -1, x20/x21 preserved and x8 ignored, 24-byte StaticString stride, NFC/duplicates/NUL/case sensitivity, literal/foreign ownership, protected empty table and nonterminated case spans')
	}
	assert swift_string_switch_symbol('_$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStF') == none
	for _ in 0 .. 2 {
		objc_start()
		api := SswApi{entry: unsafe { SswCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStF') or { panic(err) })) }, literal: swift_string_literal, probe: probe, guard: guard}
		ssw_suite(api);ssw_guarded(api);ssw_invalid(guard);ssw_limits(guard)
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		objc_stop()
		if _ := swift_string_switch_checked(guard, guard, guard) { assert false }
		assert swift_string_switch_symbol('_$ss21_findStringSwitchCase5cases6stringSiSays06StaticB0VG_SStF') == none
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-STRING-SWITCH: first canonical-equal case/-1, registered typed and loaded-image tables, inline/literal/tail/foreign Strings borrowed, protected spans and early match, eight readers, guarded invalid/lifetime rejection and two drained runtimes without new owner/cache')
}
