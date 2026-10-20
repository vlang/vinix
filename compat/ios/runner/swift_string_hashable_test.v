// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

$if macos {
	#flag -framework CoreFoundation
	#include <mach/mach.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFStringCreateMutableCopy(voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type ShbProbe = fn (u64, u64, u64, u64, u64, u64, &u64, u64) i64
type ShbLiteral = fn (&u8, i64, bool) SwiftStringWords
type ShbLookup = fn (u64, u64, u64) u64

const shb_symbols = ['_$sSH9hashValueSivgTj', '_$sSH4hash4intoys6HasherVz_tFTj',
	'_$sSH13_rawHashValue4seedS2i_tFTj', '_$sSHsE13_rawHashValue4seedS2i_tF',
	'_$ss6HasherV7combineyyxSHRzlF', '_$ss10_hashValue3forSix_tSHRzlF', '_$sSQ2eeoiySbx_xtFZTj',
	'__swift_stdlib_Hashing_parameters']!

struct ShbApi {
	native   bool
	core     voidptr
	metadata u64
	hash     u64
	entries  [8]u64
	probe    ShbProbe
	guard    u64
}

struct ShbPair {
	left  string
	right string
	equal bool
}

fn shb_symbol(native bool, core voidptr, name string) u64 {
	if native {
		address := u64(C.dlsym(core, name[1..].str))
		assert address != 0, name
		return address
	}
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
}

fn shb_api(native bool, core voidptr, probe ShbProbe, guard u64) ShbApi {
	mut entries := [8]u64{}
	for i, name in shb_symbols { entries[i] = shb_symbol(native, core, name) }
	return ShbApi{native, core, shb_symbol(native, core, '_$sSSN'), shb_symbol(native, core, '_$sSSSHsWP'), entries, probe, guard}
}

fn shb_call(api ShbApi, entry u64, args [4]u64, receiver u64) i64 {
	mut output := [u64(0x1234), 0, 0, 0x5678]!
	result := api.probe(args[0], args[1], args[2], args[3], receiver, entry, unsafe { &output[1] }, api.guard)
	assert output == [u64(0x1234), receiver, 0x5021, 0x5678]!
	return result
}

fn shb_relative(field u64) u64 { return u64(i64(field) + i64(i32(read32(field)))) }

fn shb_protocol(field u64) u64 {
	address := shb_relative(field)
	return if address & 1 != 0 { read64(address - 1) } else { address }
}

fn shb_layout(api ShbApi) {
	equal := read64(api.hash + 8)
	for i, table in [api.hash, equal]! {
		conf := read64(table)
		assert shb_protocol(conf) == shb_symbol(api.native, api.core, if i == 0 {
			'_$sSHMp'
		} else {
			'_$sSQMp'
		})
		assert shb_relative(conf + 4) == read64(api.metadata + 8)
		assert shb_relative(conf + 8) == table && read32(conf + 12) == 0
		lookup := unsafe { ShbLookup(voidptr(shb_symbol(api.native, api.core, '_swift_getWitnessTable'))) }
		assert lookup(conf, api.metadata, api.guard) == table
	}
	if api.native {
		assert equal == shb_symbol(true, api.core, '_$sSSSQsWP')
		assert read64(api.hash) == shb_symbol(true, api.core, '_$sSSSHsMc')
		assert read64(equal) == shb_symbol(true, api.core, '_$sSSSQsMc')
	}
}

fn shb_literal(api ShbApi, text string) SwiftStringWords {
	ascii := swift_replace_ascii(SwiftStringBytes{u64(text.str), u64(text.len)})
	if api.native {
		make := unsafe { ShbLiteral(voidptr(shb_symbol(true, api.core, '_$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC'))) }
		return make(text.str, text.len, ascii)
	}
	return swift_string_literal(text.str, text.len, ascii)
}

fn shb_model(api ShbApi, text string, seed i64) i64 {
	mut state := swift_hasher_raw_seed(read64(api.entries[7]) ^ u64(seed), read64(api.entries[7] + 8))
	normalized := swift_nfc_normalize(text)
	for scalar in normalized { swift_string_hash_scalar(mut state, scalar) }
	unsafe { normalized.free() }
	swift_hasher_byte(mut state, 255)
	return swift_hasher_finalize(mut state)
}

fn shb_hash(api ShbApi, words SwiftStringWords, text string) {
	self := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(self)) = words }
	for seed in [i64(0), 1, -1, 9223372036854775807, i64(-9223372036854775807) - 1]! {
		expected := shb_model(api, text, seed)
		for entry in [read64(api.hash + 32), api.entries[2], api.entries[3]]! {
			assert shb_call(api, entry, [u64(seed), api.metadata, api.hash, api.guard]!, self) == expected
		}
		if seed == 0 {
			for entry in [read64(api.hash + 16), api.entries[0]]! {
				assert shb_call(api, entry, [api.metadata, api.hash, api.guard, api.guard]!, self) == expected
			}
			assert shb_call(api, api.entries[5], [self, api.metadata, api.hash, api.guard]!, api.guard) == expected
		}
	}
	for prefix in 0 .. 8 {
		mut initial := swift_hasher_raw_seed(0x0706050403020100, 0x0f0e0d0c0b0a0908)
		for i in 0 .. prefix { swift_hasher_byte(mut initial, u64(i)) }
		for entry in [read64(api.hash + 24), api.entries[1], api.entries[4]]! {
			mut guarded := [11]u64{}
			guarded[0] = 0x1234
			guarded[10] = 0x5678
			address := u64(unsafe { &guarded[1] })
			unsafe { *(&SwiftHasher(address)) = initial }
			mut expected := initial
			for _ in 0 .. 2 {
				if entry == api.entries[4] {
					shb_call(api, entry, [self, api.metadata, api.hash, api.guard]!, address)
				} else {
					shb_call(api, entry, [address, api.metadata, api.hash, api.guard]!, self)
				}
				scalars := swift_nfc_normalize(text)
				for scalar in scalars { swift_string_hash_scalar(mut expected, scalar) }
				unsafe { scalars.free() }
				swift_hasher_byte(mut expected, 255)
				assert C.memcmp(voidptr(address), &expected, 72) == 0
				assert guarded[0] == 0x1234 && guarded[10] == 0x5678
			}
		}
	}
	assert read64(self) == words.first && read64(self + 8) == words.second
}

fn shb_equal(api ShbApi, left SwiftStringWords, right SwiftStringWords, expected bool) {
	values := u64(C.__builtin_alloca(32))
	unsafe {
		*(&SwiftStringWords(values)) = left
		*(&SwiftStringWords(values + 16)) = right
	}
	for entry in [read64(read64(api.hash + 8) + 8), api.entries[6]]! {
		for swapped in [false, true]! {
			lhs := values + if swapped { u64(16) } else { u64(0) }
			rhs := values + if swapped { u64(0) } else { u64(16) }
			actual := shb_call(api, entry, [lhs, rhs, api.metadata, read64(api.hash + 8)]!, api.metadata)
			assert (actual & 1 != 0) == expected
		}
	}
	assert read64(values) == left.first && read64(values + 8) == left.second
	assert read64(values + 16) == right.first && read64(values + 24) == right.second
}

fn shb_pairs() []ShbPair {
	return [ShbPair{'', '', true}, ShbPair{'Fortnite', 'Fortnite', true},
		ShbPair{'Fortnite', 'fortnite', false}, ShbPair{'a\x00b', 'a\x00b', true},
		ShbPair{'a\x00b', 'a', false}, ShbPair{'é', 'é', true}, ShbPair{'Å', 'Å', true},
		ShbPair{'ạ́', 'ạ́', true}, ShbPair{'각', '각', true},
		ShbPair{'ﬃ', 'ffi', false}, ShbPair{'👩‍🚀', '👩🚀', false},
		ShbPair{'\r\n', '\n', false},
		ShbPair{'long unicode café é and 🎮', 'long unicode café é and 🎮', true}]
}

fn shb_native(api ShbApi) {
	shb_layout(api)
	pairs := shb_pairs()
	for pair in pairs {
		left := shb_literal(api, pair.left)
		right := shb_literal(api, pair.right)
		shb_hash(api, left, pair.left)
		shb_equal(api, left, right, pair.equal)
		$if macos {
			constant := C.CFStringCreateWithBytes(unsafe { nil }, pair.left.str, pair.left.len, 0x08000100, false)
			owner := C.CFStringCreateMutableCopy(unsafe { nil }, 0, constant)
			C.CFRelease(constant)
			assert owner != unsafe { nil }
			mut units := u64(0)
			for byte in pair.left {
				if byte & 0xc0 != 0x80 { units += if byte >= 240 { u64(2) } else { u64(1) } }
			}
			before := C.CFGetRetainCount(owner)
			foreign := SwiftStringWords{units, u64(owner) | u64(0x5000000000000000)}
			shb_hash(api, foreign, pair.left)
			shb_equal(api, foreign, right, pair.equal)
			assert C.CFGetRetainCount(owner) == before
			C.CFRelease(owner)
		}
	}
	unsafe { pairs.free() }
}

fn shb_scalars(field string) []u8 {
	mut bytes := []u8{cap: field.len}
	for word in field.fields() {
		scalar := u32(strconv.parse_uint(word, 16, 32) or { panic(err) })
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
	return bytes
}

fn shb_corpus(api ShbApi) {
	path := $if macos { os.real_path(os.dir(@FILE) + '/../../../build/ios/unicode-nfc/NormalizationTest.txt') } $else { '/opt/ios/NormalizationTest.txt' }
	mut cases := 0
	for raw in (os.read_file(path) or { panic(err) }).split_into_lines() {
		line := raw.all_before('#').trim_space()
		if line == '' || line.starts_with('@') { continue }
		fields := line.split(';')
		for pair in [[0, 1]!, [0, 2]!, [3, 4]!]! {
			left := shb_scalars(fields[pair[0]])
			right := shb_scalars(fields[pair[1]])
			shb_equal(api, shb_literal(api, unsafe { tos(left.data, left.len) }), shb_literal(api, unsafe { tos(right.data, right.len) }), true)
			unsafe {
				left.free()
				right.free()
			}
		}
		cases++
	}
	assert cases == 20034
	println('IOS-STRING-HASHABLE-NFC: 20034 Unicode 17 records; canonical equality through both witness and protocol dispatch, symmetric comparisons')
}

fn shb_worker(api ShbApi) {
	pairs := shb_pairs()
	for pair in pairs {
		left := shb_literal(api, pair.left)
		shb_hash(api, left, pair.left)
		shb_equal(api, left, shb_literal(api, pair.right), pair.equal)
	}
	unsafe { pairs.free() }
}

fn shb_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSSSHsWP') or { panic(err) }
}

fn shb_mapping(address u64, length u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + length <= start + size
			assert info[0] == (C.PROT_READ | if executable { C.PROT_EXEC } else { 0 })
		} else {
			assert status != 0 || start > address
		}
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			if range.len != 2 { continue }
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				assert mapped && address + length <= end && fields[1] == if executable {
					'r-xp'
				} else {
					'r--p'
				}
				found = true
				break
			}
		}
		assert found == mapped
	}
}

fn test_swift_string_hashable() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0603f3, 0xaa0403f4, 0xaa0503f0,
		0xaa0703e8, 0xd28a0435, 0xd63f0200, 0xa9005674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 56))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page * 2)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	probe := unsafe { ShbProbe(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		assert core != unsafe { nil }
		shb_native(shb_api(true, core, probe, guard))
		println('NATIVE-STRING-HASHABLE: concrete descriptors and inherited Equatable; five signed seeds, complete 72-byte states, eight incoming tails, repeated combines, witness/default/generic dispatch, preserved x20/x21 and borrowed literal/foreign ownership')
	}
	if _ := swift_string_hashable_table_checked() {
		assert false
	}
	for cycle in 0 .. 2 {
		objc_start()
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn shb_resolve() }
		resolved := resolvers.wait()
		for address in resolved {
			assert address == resolved[0] && address != 0
		}
		unsafe {
			resolvers.free()
			resolved.free()
		}
		api := shb_api(false, unsafe { nil }, probe, guard)
		shb_layout(api)
		arena := ios_runtime.swift_metadata_arena
		assert api.hash == arena + u64(page) + 736
		shb_mapping(arena, u64(page), true, true)
		shb_mapping(api.hash, 104, true, false)
		if cycle == 0 { shb_corpus(api) }
		pairs := shb_pairs()
		for pair in pairs {
			left := shb_literal(api, pair.left)
			right := shb_literal(api, pair.right)
			shb_hash(api, left, pair.left)
			shb_equal(api, left, right, pair.equal)
			owner := owned_string(pair.left)
			mut units := u64(0)
			for byte in pair.left {
				if byte & 0xc0 != 0x80 { units += if byte >= 240 { u64(2) } else { u64(1) } }
			}
			foreign := SwiftStringWords{units, owner | u64(0x5000000000000000)}
			shb_hash(api, foreign, pair.left)
			shb_equal(api, foreign, right, pair.equal)
			assert obj_header(owner).refs == 1 && string_text(owner) == pair.left
			objc_release(owner)
			if pair.left.len > 15 {
				storage := u64(C.__builtin_alloca(16))
				unsafe { *(&SwiftStringWords(storage)) = swift_string_empty() }
				swift_string_append_bytes(storage, u64(pair.left.str), u64(pair.left.len))
				tail := unsafe { *(&SwiftStringWords(storage)) }
				refs := read64((tail.second & swift_address_mask) + 8)
				shb_hash(api, tail, pair.left)
				shb_equal(api, tail, right, pair.equal)
				assert read64((tail.second & swift_address_mask) + 8) == refs
				swift_bridge_release(tail.second)
			}
		}
		unsafe { pairs.free() }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn shb_worker(api) }
		workers.wait()
		unsafe { workers.free() }
		// Borrowed Self and Unicode bytes end exactly at an inaccessible page.
		text := 'long é and 🎮 input'
		start := guard - 16 - u64(text.len)
		C.memcpy(voidptr(start), text.str, usize(text.len))
		words := swift_string_literal(unsafe { &u8(start) }, text.len, false)
		unsafe { *(&SwiftStringWords(guard - 16)) = words }
		assert shb_call(api, read64(api.hash + 32), [u64(1), guard, guard, guard]!, guard - 16) == shb_model(api, text, 1)
		valid := u64(C.__builtin_alloca(16))
		unsafe { *(&SwiftStringWords(valid)) = swift_string_empty() }
		for bad in [u64(0), 1, ~u64(0) - 7]! {
			if _ := swift_string_hashable_raw_checked(0, bad) {
				assert false
			}
			if _ := swift_string_hashable_equal_checked(valid, bad) {
				assert false
			}
			if _ := swift_string_hashable_into_checked(guard, bad) {
				assert false
			}
		}
		for bad in [SwiftStringWords{}, SwiftStringWords{1, guard},
			SwiftStringWords{0xc0, u64(0xa100000000000000)},
			SwiftStringWords{0xa9c3, u64(0xe200000000000000)}]! {
			unsafe { *(&SwiftStringWords(guard - 16)) = bad }
			if _ := swift_string_hashable_equal_checked(valid, guard - 16) {
				assert false
			}
			if _ := swift_string_hashable_raw_checked(0, guard - 16) {
				assert false
			}
		}
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, '_$sSSSHsWP') == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '$sSSSHsWP') == none
		ios_runtime.swift_concurrency_retired = true
		if _ := swift_string_hashable_table_checked() {
			assert false
		}
		if _ := swift_string_hashable_raw_checked(0, guard) {
			assert false
		}
		if _ := swift_string_hashable_equal_checked(guard, guard) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.live == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		objc_stop()
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_integer_arena == 0
		shb_mapping(arena, u64(page), false, true)
		shb_mapping(arena + u64(page), u64(page), false, false)
		if _ := swift_string_hashable_table_checked() {
			assert false
		}
	}
	assert C.munmap(voidptr(code), page * 3) == 0
	println('IOS-STRING-HASHABLE: sealed canonical table with all Hashable/Equatable witnesses, NFC equality and hashing, guarded ABI/storage, inline/literal/native-tail/foreign ownership, eight cold publishers/workers, invalid/retired rejection and two drained/unmapped lifetimes')
}
