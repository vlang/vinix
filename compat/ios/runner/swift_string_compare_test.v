// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFStringCreateMutableCopy(voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
type ScRun = fn (u64, u64, u64, u64, u64) bool
type ScLiteral = fn (&u8, i64, bool) SwiftStringWords
type ScCtor = fn (i64, i64) SwiftStringWords
type ScDrop = fn (u64)
type ScProbe = fn (u64, u64, u64, &u64) bool
type ScAppend = fn (u64, u64, u64, u64)
struct ScApi {
	native bool
	entry ScRun @[required]
	literal ScLiteral @[required]
	ctor ScCtor @[required]
	drop ScDrop @[required]
	append_entry u64
	code u64
	guard u64
}
fn sc_emit(code u64) {
	// Five-word frame -> Swift x0...x4. Protect x5/x6/x7/x8; capture
	// x20/x21/x22 without exposing writable indirect result storage.
	for i, op in [u32(0xa9bc7bfd), 0xa90157f4, 0xa9024ff6, 0xf9001bf7,
		0xaa0103f3, 0xaa0303f7, 0xaa0203f4, 0x91002055, 0x91004056,
		0xaa0203e8, 0xaa0003e9, 0xa9400520, 0xa9410d22, 0xf9401124,
		0xaa0803e5, 0xaa0803e6, 0xaa0803e7, 0xd63f0260, 0xa90056f4,
		0xf9000af6, 0xa9424ff6, 0xa94157f4, 0xf9401bf7, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	// C-to-Swift appendLiteral adapter for genuinely owned native tails.
	for i, op in [u32(0xa9be7bfd), 0xf9000bf4, 0xaa0203f4, 0xaa0303f0,
		0xd63f0200, 0xf9400bf4, 0xa8c27bfd, 0xd65f03c0]! { write32(code + 128 + u64(i * 4), op) }
}
fn sc_order(left string, right string) int {
	return if left == right { 0 } else if left < right { -1 } else { 1 }
}
fn sc_words(api ScApi, left SwiftStringWords, right SwiftStringWords, order int, probe bool, ordering bool) {
	for high in [u64(0), 0xa5a5a5a5a5a5a500]! { for tag in [u64(0), 1]! {
		if tag == 1 && !ordering { continue }
		expected := if tag == 0 { order == 0 } else { order < 0 }
		assert api.entry(left.first, left.second, right.first, right.second, high | tag) == expected
		if probe {
			mut frame := [left.first, left.second, right.first, right.second, high | tag]!
			mut capture := [u64(0xCAFE), 0, 0, 0, 0xBEEF]!
			assert unsafe { ScProbe(voidptr(api.code))(u64(&frame[0]), u64(voidptr(api.entry)), api.guard, &capture[1]) } == expected
			assert capture == [u64(0xCAFE), api.guard, api.guard + 8, api.guard + 16, 0xBEEF]!
			assert frame == [left.first, left.second, right.first, right.second, high | tag]!
		}
	} }
}
fn sc_pair(api ScApi, left string, right string, order int, probe bool) {
	a := api.literal(left.str, left.len, left.is_ascii());b := api.literal(right.str, right.len, right.is_ascii())
	sc_words(api, a, b, order, probe, left.is_ascii() && right.is_ascii());sc_words(api, b, a, -order, probe, left.is_ascii() && right.is_ascii())
	api.drop(a.second);api.drop(b.second)
}
fn sc_suite(api ScApi) {
	for pair in [['', '']!, ['a', 'a']!, ['a', 'b']!, ['a', 'aa']!, ['a\x00', 'a\x00b']!,
		['é', 'é']!, ['ạ́', 'ạ́']!, ['a\u0315\u0300', 'à\u0315']!, ['K', 'K']!,
		['각', '각']!, ['A', 'a']!, ['z', 'é']!, ['Z', 'Å']!, ['ff', 'ﬀ']!,
		['A', 'Ａ']!, ['\ue000', '\U00010000']!, ['🎮', '🎯']!,
		['123456789012345', '1234567890123456']!,
		['long common prefix goes past inline storage A', 'long common prefix goes past inline storage B']!]! {
		canonical_equal := pair[0] in ['é', 'ạ́', 'a\u0315\u0300', 'K', '각']!
		sc_pair(api, pair[0], pair[1], if canonical_equal { 0 } else { sc_order(pair[0], pair[1]) }, true)
	}
	// Every ASCII byte, including NUL and the complete small/large boundary.
	for byte in 0 .. 128 {
		mut a := [u8(byte), u8(0)]!;mut b := [u8(byte), u8(1)]!
		sc_pair(api, unsafe { tos(&a[0], 1) }, unsafe { tos(&b[0], 2) }, -1, false)
	}
	for pair in [['owned native source with é', 'owned native source with é']!,
		['owned native source with A', 'owned native source with B']!]! {
		mut values := [api.ctor(128, 0), api.ctor(128, 0)]!
		for i, text in pair {
			word := api.literal(text.str, text.len, text.is_ascii())
			unsafe { ScAppend(voidptr(api.code + 128))(word.first, word.second, u64(&values[i]), api.append_entry) }
			api.drop(word.second)
		}
		first_owner := values[0].second & 0x0fffffffffffffff;second_owner := values[1].second & 0x0fffffffffffffff
		first_refs := read64(first_owner + 8);second_refs := read64(second_owner + 8);before := values
		sc_words(api, values[0], values[1], if pair[0].ends_with('é') { 0 } else { -1 }, true, pair[0].is_ascii() && pair[1].is_ascii())
		assert values == before && read64(first_owner + 8) == first_refs && read64(second_owner + 8) == second_refs
		api.drop(values[0].second);api.drop(values[1].second)
	}
}
fn sc_guarded(api ScApi) {
	page := usize(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert region != u64(-1)
	for text in ['nonterminated ASCII string crosses inline boundary', 'nonterminated é scalar at the exact boundary']! {
		for tail in [false, true]! {
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
			data := region + u64(page) + if tail { u64(page - usize(text.len)) } else { u64(0) }
			C.memcpy(voidptr(data), text.str, usize(text.len))
			assert C.mprotect(voidptr(region + u64(page)), page, C.PROT_READ) == 0
			words := api.literal(unsafe { &u8(data) }, text.len, text.is_ascii())
			other := api.literal(text.str, text.len, text.is_ascii())
			sc_words(api, words, other, 0, true, text.is_ascii())
			sc_words(api, words, api.literal(c'z', 1, true), -1, true, text.is_ascii())
			api.drop(words.second);api.drop(other.second)
		}
	}
	assert C.munmap(voidptr(region), page * 3) == 0
}
fn sc_scalars(field string) string {
	mut bytes := []u8{cap: field.len}
	for word in field.fields() {
		scalar := u32(strconv.parse_uint(word, 16, 32) or { panic(err) })
		if scalar < 128 { bytes << u8(scalar) }
		else if scalar < 0x800 { bytes << [u8(0xc0 | (scalar >> 6)), u8(0x80 | (scalar & 63))] }
		else if scalar < 0x10000 { bytes << [u8(0xe0 | (scalar >> 12)), u8(0x80 | ((scalar >> 6) & 63)), u8(0x80 | (scalar & 63))] }
		else { bytes << [u8(0xf0 | (scalar >> 18)), u8(0x80 | ((scalar >> 12) & 63)), u8(0x80 | ((scalar >> 6) & 63)), u8(0x80 | (scalar & 63))] }
	}
	result := bytes.bytestr();unsafe { bytes.free() };return result
}
fn sc_corpus(api ScApi) {
	path := $if macos { os.real_path(os.getwd() + '/build/ios/unicode-nfc/NormalizationTest.txt') } $else { '/opt/ios/NormalizationTest.txt' }
	mut cases := 0;mut previous := ''
	for raw in (os.read_file(path) or { panic(err) }).split_into_lines() {
		line := raw.all_before('#').trim_space();if line == '' || line.starts_with('@') { continue }
		fields := line.split(';');a := sc_scalars(fields[0]);nfc := sc_scalars(fields[1]);nfd := sc_scalars(fields[2])
		sc_pair(api, a, nfc, 0, false);sc_pair(api, a, nfd, 0, false)
		sc_pair(api, a, previous, sc_order(nfc, previous), false)
		unsafe { a.free();nfd.free();previous.free() };previous = nfc;cases++
	}
	unsafe { previous.free() };assert cases == 20034
	println('STRING-COMPARE-NFC: 20034 Unicode 17 records, canonical equivalence and adjacent canonical distinctions')
}
fn sc_worker(api ScApi) {
	for _ in 0 .. 32 { sc_pair(api, 'ạ́', 'ạ́', 0, true);sc_pair(api, '\ue000', '\U00010000', -1, true) }
}
fn sc_publish() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF') or { panic(err) }
}
fn sc_foreign(api ScApi) {
	for text in ['foreign String with é', 'a\x00b', '🎮', '']! {
		mut units := u64(0);for byte in text { if byte & 0xc0 != 0x80 { units += if byte >= 240 { u64(2) } else { u64(1) } } }
		literal := api.literal(text.str, text.len, text.is_ascii())
		if api.native {
			$if macos {
				constant := C.CFStringCreateWithBytes(unsafe { nil }, text.str, text.len, 0x08000100, false)
				foreign := C.CFStringCreateMutableCopy(unsafe { nil }, 0, constant);C.CFRelease(constant)
				assert foreign != unsafe { nil };refs := C.CFGetRetainCount(foreign)
				sc_words(api, SwiftStringWords{units, u64(foreign) | u64(0x5000000000000000)}, literal, 0, true, text.is_ascii())
				assert C.CFGetRetainCount(foreign) == refs;C.CFRelease(foreign)
			}
		} else {
			foreign := owned_string(text);refs := obj_header(foreign).refs
			sc_words(api, SwiftStringWords{units, foreign | u64(0x5000000000000000)}, literal, 0, true, text.is_ascii())
			assert obj_header(foreign).refs == refs;objc_release(foreign)
		}
		api.drop(literal.second)
	}
}
fn sc_invalid(guard u64) {
	for tag in [u64(2), 255, 258, ~u64(0)]! {
		if _ := swift_string_compare_checked(guard, guard, guard, guard, tag) { assert false }
	}
	unicode := swift_string_literal('é'.str, 2, false)
	if _ := swift_string_compare_checked(unicode.first, unicode.second, unicode.first, unicode.second, 1) { assert false }
	good := swift_string_literal(c'valid', 5, true)
	for bad in [SwiftStringWords{guard, 0x5000000000000000 | guard},
		SwiftStringWords{0xff, 0xe100000000000000}, SwiftStringWords{0xa9c3, 0xe200000000000000}, SwiftStringWords{0, 0x6100000000000000},
		SwiftStringWords{0x9000000000100001, guard}, SwiftStringWords{0x9000000000000001, guard},
		SwiftStringWords{0x9000000000000008, ~u64(0) - 3}]! {
		for tag in [u64(0), 1]! {
			if _ := swift_string_compare_checked(good.first, good.second, bad.first, bad.second, tag) { assert false }
			if _ := swift_string_compare_checked(bad.first, bad.second, good.first, good.second, tag) { assert false }
		}
	}
}
fn test_swift_string_compare() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0));assert code != u64(-1)
	sc_emit(code);C.__builtin___clear_cache(voidptr(code), voidptr(code + 160))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page);assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2);assert core != unsafe { nil }
		api := ScApi{native: true, entry: unsafe { ScRun(C.dlsym(core, c'$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF')) },
			literal: unsafe { ScLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) },
			ctor: unsafe { ScCtor(C.dlsym(core, c'$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC')) },
			drop: unsafe { ScDrop(C.dlsym(core, c'swift_bridgeObjectRelease')) }, append_entry: u64(C.dlsym(core, c'$ss26DefaultStringInterpolationV13appendLiteralyySSF')), code: code, guard: guard}
		sc_suite(api);sc_guarded(api);sc_foreign(api);sc_corpus(api)
		println('NATIVE-STRING-COMPARE: equality/less-than low-byte tag, canonical equality and ASCII ordering, inline/literal/owned/foreign borrowed values, protected nonterminated spans and x8, preserved x20/x21/x22')
	}
	assert swift_string_compare_symbol('_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF') == none
	for _ in 0 .. 2 {
		objc_start();mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn sc_publish() };entries := publishers.wait()
		for entry in entries { assert entry == entries[0] }
		api := ScApi{entry: unsafe { ScRun(voidptr(entries[0])) }, literal: swift_string_literal, ctor: swift_interpolation_init,
			drop: swift_bridge_release, append_entry: runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss26DefaultStringInterpolationV13appendLiteralyySSF') or { panic(err) }, code: code, guard: guard}
		sc_suite(api);sc_guarded(api);sc_foreign(api);sc_invalid(guard);sc_corpus(api)
		mut workers := []thread{};for _ in 0 .. 8 { workers << spawn sc_worker(api) };workers.wait()
		unsafe { publishers.free();entries.free();workers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! { assert runtime_symbol(library, '_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF') == none }
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF') == none
		ios_runtime.swift_concurrency_retired = true;assert swift_string_compare_symbol('_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF') == none
		if _ := swift_string_compare_checked(guard, guard, guard, guard, 0) { assert false };ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_stop();if _ := swift_string_compare_checked(guard, guard, guard, guard, 0) { assert false }
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	println('IOS-STRING-COMPARE: canonical equality/ASCII ordering, checked borrowed storage and exact ownership, protected spans and contexts, invalid tags/storage and retired rejection, eight cold publishers/workers and two drained lifetimes without a new owner/cache')
}
