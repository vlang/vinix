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
fn C.CFRelease(voidptr)
fn C.CFGetRetainCount(voidptr) i64

type ShCall = fn (u64, u64, u64)
type ShLiteral = fn (&u8, i64, bool) SwiftStringWords
type ShProbe = fn (u64, u64, u64, u64, &u64)

fn sh_from_scalars(field string) []u32 {
	mut result := []u32{}
	for word in field.fields() { result << u32(strconv.parse_uint(word, 16, 32) or { panic(err) }) }
	return result
}

fn sh_utf8(scalars []u32) []u8 {
	mut result := []u8{cap: scalars.len * 4}
	for scalar in scalars {
		if scalar < 128 {
			result << u8(scalar)
		} else if scalar < 0x800 {
			result << u8(0xc0 | (scalar >> 6))
			result << u8(0x80 | (scalar & 63))
		} else if scalar < 0x10000 {
			result << u8(0xe0 | (scalar >> 12))
			result << u8(0x80 | ((scalar >> 6) & 63))
			result << u8(0x80 | (scalar & 63))
		} else {
			result << u8(0xf0 | (scalar >> 18))
			result << u8(0x80 | ((scalar >> 12) & 63))
			result << u8(0x80 | ((scalar >> 6) & 63))
			result << u8(0x80 | (scalar & 63))
		}
	}
	return result
}

fn sh_normalization() {
	path := $if macos { os.real_path(os.dir(@FILE) + '/../../../build/ios/unicode-nfc/NormalizationTest.txt') } $else { '/opt/ios/NormalizationTest.txt' }
	data := os.read_file(path) or { panic(err) }
	mut cases := 0
	for raw in data.split_into_lines() {
		line := raw.all_before('#').trim_space()
		if line == '' || line.starts_with('@') { continue }
		fields := line.split(';')
		assert fields.len >= 5
		canonical := sh_from_scalars(fields[1])
		compatibility := sh_from_scalars(fields[3])
		for i in 0 .. 5 {
			scalars := sh_from_scalars(fields[i])
			bytes := sh_utf8(scalars)
			actual := swift_nfc_normalize(unsafe { tos(bytes.data, bytes.len) })
			assert actual == if i < 3 { canonical } else { compatibility }, raw
			unsafe {
				actual.free()
				bytes.free()
				scalars.free()
			}
		}
		unsafe {
			canonical.free()
			compatibility.free()
		}
		cases++
	}
	assert cases > 20000
	println('IOS-STRING-HASH-NFC: ' + cases.str() + ' Unicode 17 normalization records, all five NFC invariants')
}

fn sh_expected(mut state SwiftHasher, text string) {
	bytes := SwiftStringBytes{u64(text.str), u64(text.len)}
	if swift_replace_ascii(bytes) {
		swift_hasher_bytes(mut state, bytes.address, bytes.address + bytes.count)
	} else {
		scalars := swift_nfc_normalize(text)
		for scalar in scalars { swift_string_hash_scalar(mut state, scalar) }
		unsafe { scalars.free() }
	}
	swift_hasher_byte(mut state, 255)
}

fn sh_case(call ShCall, words SwiftStringWords, expected_text string, probe ShProbe) {
	for prefix in 0 .. 8 {
		mut actual := [11]u64{}
		actual[0] = 0x1234
		actual[10] = 0x5678
		mut reference := swift_hasher_raw_seed(0x0706050403020100, 0x0f0e0d0c0b0a0908)
		for i in 0 .. prefix { swift_hasher_byte(mut reference, u64(i)) }
		unsafe { *(&SwiftHasher(&actual[1])) = reference }
		sh_expected(mut reference, expected_text)
		mut registers := [u64(0x1234), 0, 0, 0x5678]!
		probe(u64(unsafe { &actual[1] }), words.first, words.second, u64(unsafe { voidptr(call) }), unsafe { &registers[1] })
		assert registers == [u64(0x1234), 0x5020, 0x5021, 0x5678]!
		assert C.memcmp(unsafe { &actual[1] }, &reference, 72) == 0, expected_text
		assert actual[0] == 0x1234 && actual[10] == 0x5678
		// Chained hashing must preserve the incoming tail and add each terminator.
		call(u64(unsafe { &actual[1] }), words.first, words.second)
		sh_expected(mut reference, expected_text)
		assert C.memcmp(unsafe { &actual[1] }, &reference, 72) == 0
	}
}

fn sh_native(probe ShProbe) {
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert core != unsafe { nil }
		call := unsafe { ShCall(C.dlsym(core, c'$sSS4hash4intoys6HasherVz_tF')) }
		literal := unsafe { ShLiteral(C.dlsym(core, c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) }
		assert voidptr(call) != unsafe { nil } && voidptr(literal) != unsafe { nil }
		for text in ['', 'Fortnite', 'a\x00b', '123456789012345', '1234567890123456', 'é', 'é',
			'Å', 'Å', 'Å', '각', '각', 'π🎮', 'ạ́', 'ạ́', 'ﬃ',
			'long unicode café with é and 🎮', 'version', 'heartbeats']! {
			sh_case(call, literal(text.str, text.len, swift_replace_ascii(SwiftStringBytes{u64(text.str), u64(text.len)})), text, probe)
			constant := C.CFStringCreateWithBytes(unsafe { nil }, text.str, text.len, 0x08000100, false)
			owner := C.CFStringCreateMutableCopy(unsafe { nil }, 0, constant)
			C.CFRelease(constant)
			assert owner != unsafe { nil }
			mut units := u64(0)
			for byte in text {
				if byte & 0xc0 != 0x80 { units += if byte >= 240 { u64(2) } else { u64(1) } }
			}
			before := C.CFGetRetainCount(owner)
			sh_case(call, SwiftStringWords{units, u64(owner) | u64(0x5000000000000000)}, text, probe)
			assert C.CFGetRetainCount(owner) == before
			C.CFRelease(owner)
		}
		println('NATIVE-STRING-HASH: full 72-byte states, eight incoming tail lengths, repeated strings, NFC equivalence, embedded NUL, inline/literal/foreign forms and preserved x20/x21/ownership')
	}
}

fn sh_worker(call ShCall, words SwiftStringWords, text string, probe ShProbe) {
	for _ in 0 .. 16 { sh_case(call, words, text, probe) }
}

fn test_swift_string_hash() {
	sh_normalization()
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0303f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9005674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 52))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page * 2)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	probe := unsafe { ShProbe(voidptr(code)) }
	sh_native(probe)
	if _ := swift_string_hash_into_checked(guard, 0, 0) {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSS4hash4intoys6HasherVz_tF') or { panic(err) }
		call := unsafe { ShCall(voidptr(entry)) }
		for text in ['', 'Fortnite', 'a\x00b', 'é', 'é', 'Å', 'Å', 'Å', '각', '각',
			'ạ́', 'ạ́', 'ﬃ', 'π🎮', 'long unicode café with é and 🎮']! {
			words := swift_string_literal(text.str, text.len, swift_replace_ascii(SwiftStringBytes{u64(text.str), u64(text.len)}))
			sh_case(call, words, text, probe)
			if text.len > 15 {
				storage := u64(C.__builtin_alloca(16))
				unsafe { *(&SwiftStringWords(storage)) = swift_string_empty() }
				swift_string_append_bytes(storage, u64(text.str), u64(text.len))
				tail := unsafe { *(&SwiftStringWords(storage)) }
				owner := tail.second & swift_address_mask
				refs := read64(owner + 8)
				sh_case(call, tail, text, probe)
				assert read64(owner + 8) == refs
				swift_bridge_release(tail.second)
			}
			owner := owned_string(text)
			mut units := u64(0)
			for byte in text {
				if byte & 0xc0 != 0x80 { units += if byte >= 240 { u64(2) } else { u64(1) } }
			}
			sh_case(call, SwiftStringWords{units, owner | u64(0x5000000000000000)}, text, probe)
			assert obj_header(owner).refs == 1 && string_text(owner) == text
			objc_release(owner)
			mut workers := []thread{}
			for _ in 0 .. 4 { workers << spawn sh_worker(call, words, text, probe) }
			workers.wait()
			unsafe { workers.free() }
		}
		for length in 0 .. 65 {
			address := guard - u64(length)
			for i in 0 .. length {
				unsafe { *(&u8(address + u64(i))) = u8(32 + i) }
			}
			text := unsafe { tos(&u8(address), length) }
			sh_case(call, swift_string_literal(unsafe { &u8(address) }, length, true), text, probe)
		}
		mut state := swift_hasher_raw_seed(1, 2)
		before := state
		for bad in [u64(0), 1, ~u64(0) - 7]! {
			if _ := swift_string_hash_into_checked(bad, 0, 0) {
				assert false
			}
		}
		for words in [SwiftStringWords{}, SwiftStringWords{1, guard},
			SwiftStringWords{1048577 | u64(0x1000000000000000), guard | u64(0x8000000000000000)},
			SwiftStringWords{0xc0, u64(0xa100000000000000)}]! {
			if _ := swift_string_hash_into_checked(u64(unsafe { &state }), words.first, words.second) {
				assert false
			}
			assert C.memcmp(&state, &before, 72) == 0
		}
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSS4hash4intoys6HasherVz_tF') == none
		}
		ios_runtime.swift_concurrency_retired = true
		if _ := swift_string_hash_into_checked(guard, 0, 0) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.live == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		if _ := swift_string_hash_into_checked(guard, 0, 0) {
			assert false
		}
	}
	assert C.munmap(voidptr(code), page * 3) == 0
	println('IOS-STRING-HASH: NFC UTF8 plus terminator, allocation-free ASCII, native state/ABI comparisons, checked inline/literal/native-tail/foreign reader, guarded extents, invalid inputs leave Hasher unchanged, four workers and two drained runtimes')
}
