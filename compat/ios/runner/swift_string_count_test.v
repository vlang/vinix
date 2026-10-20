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

type ScCall = fn (u64, u64) i64
type ScLiteral = fn (&u8, i64, bool) SwiftStringWords
type ScProbe = fn (u64, u64, u64, &u64)

struct ScCase {
	text  string
	count i64
}

fn sc_cases() []ScCase {
	return [ScCase{'', 0}, ScCase{'Fortnite', 8}, ScCase{'a\x00b', 3}, ScCase{'\r\n', 1},
		ScCase{'a\r\nb\rc\nd', 7}, ScCase{'\n\r\r\n', 3}, ScCase{'é', 1}, ScCase{'é', 1},
		ScCase{'́̂', 1}, ScCase{'ạ́b', 2}, ScCase{'각', 1}, ScCase{'각', 1},
		ScCase{'🇺🇸🇫🇷🇬', 3}, ScCase{'👩🏽‍🚀', 1},
		ScCase{'👨‍👩‍👧‍👦', 1}, ScCase{'👩́‍🚀', 1}, ScCase{'👩‍́🚀', 2},
		ScCase{'क्ष', 1}, ScCase{'क्‍ष', 1}, ScCase{'a‍b', 2}, ScCase{'؀a', 1},
		ScCase{'؀\nb', 3}, ScCase{'long café é 🎮\r\ntext', 18}]
}

fn sc_encode(scalar u32, mut bytes []u8) {
	if scalar < 128 {
		bytes << u8(scalar)
	} else if scalar < 0x800 {
		bytes << u8(0xc0 | (scalar >> 6))
		bytes << u8(0x80 | (scalar & 63))
	} else if scalar < 0x10000 {
		bytes << u8(0xe0 | (scalar >> 12))
		bytes << u8(0x80 | ((scalar >> 6) & 63))
		bytes << u8(0x80 | (scalar & 63))
	} else {
		bytes << u8(0xf0 | (scalar >> 18))
		bytes << u8(0x80 | ((scalar >> 12) & 63))
		bytes << u8(0x80 | ((scalar >> 6) & 63))
		bytes << u8(0x80 | (scalar & 63))
	}
}

fn sc_corpus(call ScCall) {
	path := $if macos { os.real_path(os.dir(@FILE) + '/../../../build/ios/unicode-grapheme/GraphemeBreakTest.txt') } $else { '/opt/ios/GraphemeBreakTest.txt' }
	data := os.read_file(path) or { panic(err) }
	mut cases := 0
	mut boundaries := 0
	for raw in data.split_into_lines() {
		line := raw.all_before('#').trim_space()
		if line == '' { continue }
		fields := line.fields()
		assert fields.len % 2 == 1 && fields[0] == '÷' && fields.last() == '÷'
		mut state := SwiftGraphemeState{}
		mut bytes := []u8{cap: fields.len * 2}
		mut expected := i64(0)
		for i := 1; i < fields.len; i += 2 {
			scalar := u32(strconv.parse_uint(fields[i], 16, 21) or { panic(err) })
			boundary := fields[i - 1] == '÷'
			assert swift_grapheme_break(mut state, scalar) == boundary, raw
			if boundary { expected++ }
			boundaries++
			sc_encode(scalar, mut bytes)
		}
		text := unsafe { tos(bytes.data, bytes.len) }
		words := swift_string_literal(text.str, text.len, swift_replace_ascii(SwiftStringBytes{u64(text.str), u64(text.len)}))
		assert call(words.first, words.second) == expected, raw
		unsafe { bytes.free() }
		cases++
	}
	assert cases == 766
	println('IOS-STRING-COUNT-UNICODE: ' + cases.str() + ' Unicode 17 records; ' + boundaries.str() + ' scalar boundaries and all full-string counts passed')
}

fn sc_case(call ScCall, probe ScProbe, words SwiftStringWords, expected i64) {
	assert call(words.first, words.second) == expected
	mut output := [u64(0x1234), 0, 0, 0, 0x5678]!
	probe(words.first, words.second, u64(unsafe { voidptr(call) }), unsafe { &output[1] })
	assert output == [u64(0x1234), u64(expected), 0x5020, 0x5021, 0x5678]!
}

fn sc_units(text string) u64 {
	mut units := u64(0)
	for byte in text {
		if byte & 0xc0 != 0x80 { units += if byte >= 240 { u64(2) } else { u64(1) } }
	}
	return units
}

fn sc_native(probe ScProbe) {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert core != unsafe { nil }
		call := unsafe { ScCall(C.dlsym(core, c'$sSS5countSivg')) }
		literal := unsafe { ScLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }
		assert voidptr(call) != unsafe { nil } && voidptr(literal) != unsafe { nil }
		cases := sc_cases()
		for item in cases {
			words := literal(item.text.str, item.text.len, swift_replace_ascii(SwiftStringBytes{u64(item.text.str), u64(item.text.len)}))
			sc_case(call, probe, words, item.count)
			constant := C.CFStringCreateWithBytes(unsafe { nil }, item.text.str, item.text.len, 0x08000100, false)
			owner := C.CFStringCreateMutableCopy(unsafe { nil }, 0, constant)
			C.CFRelease(constant)
			assert owner != unsafe { nil }
			before := C.CFGetRetainCount(owner)
			sc_case(call, probe, SwiftStringWords{sc_units(item.text), u64(owner) | u64(0x5000000000000000)}, item.count)
			assert C.CFGetRetainCount(owner) == before
			C.CFRelease(owner)
		}
		unsafe { cases.free() }
		println('NATIVE-STRING-COUNT: borrowed x0/x1, signed result x0, preserved x20/x21, inline/literal/foreign storage, CRLF/NUL/combining/Hangul/RI/emoji/Indic and unchanged ownership')
	}
}

fn sc_worker(call ScCall, words SwiftStringWords, expected i64) {
	for _ in 0 .. 100 {
		assert call(words.first, words.second) == expected
	}
}

fn test_swift_string_count() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0203f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xf9000260, 0xa900d674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 56))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page * 2)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	probe := unsafe { ScProbe(voidptr(code)) }
	sc_native(probe)
	if _ := swift_string_count_checked(0, guard) {
		assert false
	}
	for cycle in 0 .. 2 {
		objc_start()
		call := unsafe { ScCall(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS5countSivg') or { panic(err) })) }
		if cycle == 0 { sc_corpus(call) }
		cases := sc_cases()
		for item in cases {
			words := swift_string_literal(item.text.str, item.text.len, swift_replace_ascii(SwiftStringBytes{u64(item.text.str), u64(item.text.len)}))
			sc_case(call, probe, words, item.count)
			if item.text.len > 15 {
				storage := u64(C.__builtin_alloca(16))
				unsafe { *(&SwiftStringWords(storage)) = swift_string_empty() }
				swift_string_append_bytes(storage, u64(item.text.str), u64(item.text.len))
				tail := unsafe { *(&SwiftStringWords(storage)) }
				owner := tail.second & swift_address_mask
				refs := read64(owner + 8)
				sc_case(call, probe, tail, item.count)
				assert read64(owner + 8) == refs
				swift_bridge_release(tail.second)
			}
			owner := owned_string(item.text)
			foreign := SwiftStringWords{sc_units(item.text), owner | u64(0x5000000000000000)}
			sc_case(call, probe, foreign, item.count)
			mut workers := []thread{}
			for _ in 0 .. 4 { workers << spawn sc_worker(call, foreign, item.count) }
			workers.wait()
			unsafe { workers.free() }
			assert obj_header(owner).refs == 1 && string_text(owner) == item.text
			objc_release(owner)
			if _ := swift_string_count_checked(foreign.first, foreign.second) {
				assert false
			}
		}
		unsafe { cases.free() }
		for length in 0 .. 66 {
			address := guard - u64(length)
			for i in 0 .. length {
				unsafe { *(&u8(address + u64(i))) = if i % 2 == 0 { u8(13) } else { u8(10) } }
			}
			sc_case(call, probe, swift_string_literal(unsafe { &u8(address) }, length, true), (length + 1) / 2)
		}
		for text in ['é', '🇺🇸', '👩🏽‍🚀', 'क्ष']! {
			address := guard - u64(text.len)
			C.memcpy(voidptr(address), text.str, usize(text.len))
			sc_case(call, probe, swift_string_literal(unsafe { &u8(address) }, text.len, false), 1)
		}
		for words in [SwiftStringWords{}, SwiftStringWords{1, guard},
			SwiftStringWords{1048577 | u64(0x1000000000000000), guard | u64(0x8000000000000000)},
			SwiftStringWords{1, guard | u64(0x5000000000000000)},
			SwiftStringWords{0xc0, u64(0xa100000000000000)},
			SwiftStringWords{0xa9c3, u64(0xe200000000000000)}]! {
			if _ := swift_string_count_checked(words.first, words.second) {
				assert false
			}
		}
		// Exercise the full accepted extent with repeated CRLF and a combining run.
		mut large := []u8{len: 1048576, init: if index % 2 == 0 { u8(13) } else { u8(10) }}
		words := swift_string_literal(large.data, large.len, true)
		assert call(words.first, words.second) == 524288
		large[0] = `a`
		for i := 1; i + 1 < large.len; i += 2 {
			large[i] = 0xcc
			large[i + 1] = 0x81
		}
		large[large.len - 1] = `b`
		unicode_words := swift_string_literal(large.data, large.len, false)
		assert call(unicode_words.first, unicode_words.second) == 2
		unsafe { large.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSS5countSivg') == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSS5countSivg') == none
		ios_runtime.swift_concurrency_retired = true
		if _ := swift_string_count_checked(0, guard) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.live == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		if _ := swift_string_count_checked(0, guard) {
			assert false
		}
	}
	assert C.munmap(voidptr(code), page * 3) == 0
	println('IOS-STRING-COUNT: allocation-free grapheme scan, checked inline/literal/native-tail/foreign forms, guarded UTF8 extents, 1 MiB CRLF/combining stress, invalid/stale/retired inputs, four workers and two drained runtimes')
}
