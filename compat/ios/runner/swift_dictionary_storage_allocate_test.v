// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <objc/runtime.h>
}

fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)

type DsaProbe = fn (u64, i64, u64, u64, &u64)
type DsaAccess = fn (u64, u64, u64, u64) SwiftAssociatedMetadata
type DsaDrop = fn (u64)
type DsaObjMetadata = fn (u64) u64

fn dsa_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203f4,
		0xaa0303e8, 0xaa0403f3, 0xd28a0435, 0xd63f0200, 0xf9000260, 0xf9000674, 0xf9000a75, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 128, 0xaa1403e0)
	write32(code + 132, 0x58000070)
	write32(code + 136, 0xd61f0200)
	write32(code + 140, 0xd503201f)
	unsafe { *(&u64(code + 144)) = u64(voidptr(dsa_destroy)) }
}

fn dsa_destroy(owner u64) {
	metadata := read64(owner)
	if read64(owner + 16) != 0 {
		key := read64(metadata + 176)
		value := read64(metadata + 184)
		key_stride := read64(read64(key - 8) + 72)
		value_stride := read64(read64(value - 8) + 72)
		for bucket in u64(0) .. (u64(1) << unsafe { *(&u8(owner + 32)) }) {
			if read64(owner + 64 + bucket / 64 * 8) & (u64(1) << (bucket & 63)) == 0 { continue }
			unsafe { SwiftSequenceDestroy(voidptr(read64(read64(key - 8) + 8)))(read64(owner + 48) + bucket * key_stride, key) }
			unsafe { SwiftSequenceDestroy(voidptr(read64(read64(value - 8) + 8)))(read64(owner + 56) + bucket * value_stride, value) }
		}
	}
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss18_DictionaryStorageC8allocate8capacityAByxq_GSi_tFZ') != none
	// Match the measured native deallocating destructor's fixed arguments.
	if _ := swift_heap_deallocate_checked(owner, 64, 7, false) {
		assert false
	}
	swift_heap_deallocate_class(owner, 64, 7)
}

fn dsa_class(data u64, code u64, key u64, value u64, hashable u64) u64 {
	metadata := data + 24
	descriptor := data + 272
	unsafe {
		*(&u64(metadata - 16)) = code + 128
		*(&u64(metadata)) = metadata + 256
		*(&u64(metadata + 32)) = 2
		*(&u64(metadata + 64)) = descriptor
		*(&u64(metadata + 176)) = key
		*(&u64(metadata + 184)) = value
		*(&u64(metadata + 192)) = hashable
	}
	write32(metadata + 40, 2)
	write32(metadata + 48, 64)
	write32(metadata + 52, 7)
	write32(metadata + 56, 232)
	write32(metadata + 60, 24)
	write32(descriptor, 0xd0)
	swift_protocol_relative(descriptor + 4, data + 352)
	swift_protocol_relative(descriptor + 8, data + 384)
	write32(descriptor + 28, 26)
	write32(descriptor + 32, 4)
	swift_protocol_relative(data + 360, data + 416)
	C.memcpy(voidptr(data + 384), c'_DictionaryStorage', 19)
	C.memcpy(voidptr(data + 416), c'Swift', 6)
	return metadata
}

fn dsa_unused_copy(_a u64, _b u64, _c u64) u64 { panic('raw allocation invoked a value witness') }

fn dsa_unused_destroy(_a u64, _b u64) { panic('raw allocation destroyed an element') }

fn dsa_unused_tag(_a u64, _b u32, _c u64) u32 { panic('raw allocation inspected an enum') }

fn dsa_unused_store(_a u64, _b u32, _c u32, _d u64) { panic('raw allocation initialized an enum') }

fn dsa_wide(data u64, size u64, stride u64, alignment u32) u64 {
	metadata := data + 16
	witness := data + 256
	unsafe {
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = data + 128
	}
	write32(data + 128, 0x51)
	swift_protocol_relative(data + 132, data + 192)
	swift_protocol_relative(data + 136, data + 224)
	swift_protocol_relative(data + 200, data + 208)
	C.memcpy(voidptr(data + 208), c'Swift', 6)
	C.memcpy(voidptr(data + 224), c'AllocateLayoutFixture', 22)
	for i, entry in [u64(unsafe { voidptr(dsa_unused_copy) }),
		u64(unsafe { voidptr(dsa_unused_destroy) }), u64(unsafe { voidptr(dsa_unused_copy) }),
		u64(unsafe { voidptr(dsa_unused_copy) }), u64(unsafe { voidptr(dsa_unused_copy) }),
		u64(unsafe { voidptr(dsa_unused_copy) }), u64(unsafe { voidptr(dsa_unused_tag) }),
		u64(unsafe { voidptr(dsa_unused_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = entry }
	}
	unsafe {
		*(&u64(witness + 64)) = size
		*(&u64(witness + 72)) = stride
	}
	write32(witness + 80, alignment - 1)
	return metadata
}

type DsaHash = fn (i64, u64) i64

fn dsa_call(code u64, entry u64, capacity i64, metadata u64, guard u64) u64 {
	mut captured := [u64(0), 0, 0]!
	unsafe { DsaProbe(voidptr(code))(entry, capacity, metadata, guard, &captured[0]) }
	assert captured[1] == metadata && captured[2] == 0x5021
	return captured[0]
}

fn dsa_hash(seed i64, word u64, native bool) i64 {
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			return unsafe { DsaHash(C.dlsym(core, c'$ss6HasherV5_hash4seed_S2i_SutFZ')) }(seed, word)
		}
	}
	return swift_hasher_hash_word(seed, word)
}

fn dsa_drop(owner u64, native bool) {
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			unsafe { DsaDrop(C.dlsym(core, c'swift_release'))(owner) }
			return
		}
	}
	swift_release(owner)
}

fn dsa_shape(owner u64, metadata u64, scale u8, key u64, value u64, native bool) {
	key_witness := read64(key - 8) & 0x0000ffffffffffff
	value_witness := read64(value - 8) & 0x0000ffffffffffff
	key_align := u64(read32(key_witness + 80) & 255) + 1
	value_align := u64(read32(value_witness + 80) & 255) + 1
	buckets := u64(1) << scale
	words := (buckets + 63) / 64
	keys := (64 + words * 8 + key_align - 1) & ~(key_align - 1)
	values := (keys + buckets * read64(key_witness + 72) + value_align - 1) & ~(value_align - 1)
	assert read64(owner) == metadata && read64(owner + 16) == 0
	assert read64(owner + 24) == buckets - buckets / 4 - u64(scale == 1)
	assert read64(owner + 32) == u64(scale) | (u64(u32(dsa_hash(0, owner, native))) << 32)
	assert read64(owner + 40) == if os.getenv('SWIFT_DETERMINISTIC_HASHING') == '1' { u64(scale) } else { owner }
	assert read64(owner + 48) == owner + keys && read64(owner + 56) == owner + values
	assert owner & (key_align - 1) == 0 && owner & (value_align - 1) == 0
	for i in u64(0) .. words {
		assert read64(owner + 64 + i * 8) == if buckets < 64 { ~((u64(1) << u32(buckets)) - 1) } else { u64(0) }
	}
	if !native {
		storage := ios_runtime.swift_heap[owner] or { panic('unregistered allocated storage') }
		assert storage.dictionary_tail && storage.size == values + buckets * read64(value_witness + 72)
		assert read64(owner + 8) == 3
	}
}

fn dsa_profile(code u64, entry u64, metadata u64, key u64, value u64, guard u64, native bool) {
	for pair in [[i64(-9223372036854775807) - 1, 1]!, [-1, 1]!, [0, 1]!, [1, 1]!, [2, 2]!, [3, 2]!, [4, 3]!, [6, 3]!, [7, 4]!, [23, 5]!, [24, 5]!, [25, 6]!, [47, 6]!, [48, 6]!, [49, 7]!, [96, 7]!, [97, 8]!, [192, 8]!, [193, 9]!, [384, 9]!, [385, 10]!, [768, 10]!, [769, 11]!, [1536, 11]!, [1537, 12]!, [3072, 12]!, [3073, 13]!, [6144, 13]!, [6145, 14]!, [12288, 14]!]! {
		for _ in 0 .. 2 {
			// The indirect-result register and Hashable table are inaccessible.
			owner := dsa_call(code, entry, pair[0], metadata, guard)
			dsa_shape(owner, metadata, u8(pair[1]), key, value, native)
			dsa_drop(owner, native)
		}
	}
}

fn dsa_refs(object u64, native bool) i64 {
	$if macos { if native { return C.CFGetRetainCount(voidptr(object)) } }
	return obj_header(object).refs
}

fn dsa_ownership(code u64, entry u64, metadata u64, guard u64, native bool) {
	for move in [u64(0), 1]! {
		mut object := u64(0)
		$if macos {
			if native { object = u64(C.CFStringCreateMutable(unsafe { nil }, 0)); C.CFRetain(voidptr(object)) }
		}
		if !native { object = owned_string('Dictionary allocation caller owns entry initialization and element transfer'); objc_retain(object) }
		source := dsa_call(code, entry, 3, metadata, guard)
		old_bucket := u64(dsa_hash(i64(read64(source + 40)), 17, native)) & 3
		unsafe {
			*(&u64(read64(source + 48) + old_bucket * 8)) = 17
			*(&u64(read64(source + 56) + old_bucket * 8)) = object
			*(&u64(source + 64)) |= u64(1) << old_bucket
			*(&u64(source + 16)) = 1
		}
		mut before := [9]u64{}
		C.memcpy(unsafe { &before[0] }, voidptr(source), 72)
		target := dsa_call(code, entry, 49, metadata, guard)
		assert C.memcmp(unsafe { &before[0] }, voidptr(source), 72) == 0 && dsa_refs(object, native) == 2
		dsa_shape(target, metadata, 7, read64(metadata + 176), read64(metadata + 184), native)
		new_bucket := u64(dsa_hash(i64(read64(target + 40)), 17, native)) & 127
		for offset in [u64(176), 184]! {
			type_metadata := read64(metadata + offset)
			witness := read64(type_metadata - 8) & 0x0000ffffffffffff
			initialize := unsafe { SwiftSequenceCopy(voidptr(read64(witness + if move == 0 { u64(16) } else { u64(32) }) & 0x0000ffffffffffff)) }
			field := if offset == 176 { u64(48) } else { u64(56) }
			initialize(read64(target + field) + new_bucket * 8, read64(source + field) + old_bucket * 8, type_metadata)
		}
		unsafe {
			*(&u64(target + 64 + new_bucket / 64 * 8)) |= u64(1) << (new_bucket & 63)
			*(&u64(target + 16)) = 1
			if move != 0 { *(&u64(source + 16)) = 0; *(&u64(source + 64)) = ~u64(15) }
		}
		assert dsa_refs(object, native) == if move == 0 { i64(3) } else { i64(2) }
		dsa_drop(source, native)
		assert dsa_refs(object, native) == 2
		assert read64(read64(target + 48) + new_bucket * 8) == 17 && read64(read64(target + 56) + new_bucket * 8) == object
		dsa_drop(target, native)
		assert dsa_refs(object, native) == 1
		$if macos { if native { C.CFRelease(voidptr(object)); continue } }
		objc_release(object)
	}
}

fn dsa_worker(entry u64, metadata u64) {
	for i in 0 .. 32 {
		owner := swift_dictionary_storage_allocate_capacity(i64(i * 3), metadata)
		swift_release(owner)
	}
	assert entry == runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss18_DictionaryStorageC8allocate8capacityAByxq_GSi_tFZ') or { panic(err) }
}

fn test_swift_dictionary_storage_allocate() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	guard := code + u64(page) * 3
	dsa_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 152))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	wide := dsa_wide(code + u64(page) * 2, 17, 64, 64)
	wide_key := dsa_wide(code + u64(page) * 2 + 512, 17, 256, 256)
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		access := unsafe { DsaAccess(C.dlsym(core, c'$ss18_DictionaryStorageCMa')) }
		entry := u64(C.dlsym(core, c'$ss18_DictionaryStorageC8allocate8capacityAByxq_GSi_tFZ'))
		int_type := u64(C.dlsym(core, c'$sSiN'))
		string_type := u64(C.dlsym(core, c'$sSSN'))
		for pair in [[string_type, int_type]!, [string_type, string_type]!, [string_type, u64(C.dlsym(core, c'$ss12StaticStringVN'))]!, [u64(C.dlsym(core, c'$sSbN')), u64(C.dlsym(core, c'$sytN')) + 8]!, [int_type, wide]!, [wide_key, wide]!, [string_type, u64(C.dlsym(core, c'$sypN')) + 8]!]! {
			metadata := access(0, pair[0], pair[1], u64(C.dlsym(core, c'$sSSSHsWP'))).metadata
			dsa_profile(code, entry, metadata, pair[0], pair[1], guard, true)
		}
		object_type := unsafe { DsaObjMetadata(C.dlsym(core, c'swift_getObjCClassMetadata')) }(u64(C.objc_getClass(c'NSString')))
		owned_type := access(0, int_type, object_type, u64(C.dlsym(core, c'$sSiSHsWP'))).metadata
		dsa_ownership(code, entry, owned_type, guard, true)
		println('NATIVE-DICTIONARY-STORAGE-ALLOCATE: capacity x0 and metatype x20, owned x0 and preserved x20/x21, seven layouts with zero-size and 256-byte alignment, capacity boundaries and fresh age/seed, protected unused x8/Hashable, caller-initialized copy/move lifecycle')
	}
	for _ in 0 .. 2 {
		objc_start()
		library := '/usr/lib/swift/libswiftCore.dylib'
		symbol := '_$ss18_DictionaryStorageC8allocate8capacityAByxq_GSi_tFZ'
		entry := runtime_symbol(library, symbol) or { panic(err) }
		assert runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', symbol) == none
		int_type := swift_integer_metadata()
		string_type := swift_string_metadata()
		for i, pair in [[string_type, int_type]!, [string_type, string_type]!, [string_type, (swift_static_string_metadata_arena_checked() or { panic(err) }) + u64(page) + 16]!, [(swift_bool_metadata_arena_checked() or { panic(err) }) + u64(page) + 16, swift_void_full_metadata() + 8]!, [int_type, wide]!, [wide_key, wide]!, [string_type, swift_any_full_metadata() + 8]!]! {
			metadata := dsa_class(code + u64(page) + u64(i * 512), code, pair[0], pair[1], guard)
			dsa_profile(code, entry, metadata, pair[0], pair[1], guard, false)
			if i == 0 { mut workers := []thread{}; for _ in 0 .. 8 { workers << spawn dsa_worker(entry, metadata) }; workers.wait() }
		}
		owned_type := dsa_class(code + u64(page) * 2 + 1024, code, int_type, swift_objc_metadata(ios_runtime.names['NSString']), guard)
		dsa_ownership(code, entry, owned_type, guard, false)
		metadata := code + u64(page) + 24
		first := dsa_call(code, entry, 0, metadata, guard)
		second := dsa_call(code, entry, 0, metadata, guard)
		assert first != second && read64(first + 24) == 1 && read64(second + 24) == 1
		assert read64(first + 48) != read64(second + 48) && read64(first + 56) != read64(second + 56)
		swift_release(first)
		swift_release(second)
		before := ios_runtime.swift_heap.len
		for capacity in [i64(12289), 1 << 32, 9223372036854775807]! { if _ := swift_dictionary_storage_for_capacity_checked(capacity, guard) { assert false } }
		for bad in [u64(0), 1, ~u64(0), int_type]! { if _ := swift_dictionary_storage_for_capacity_checked(1, bad) { assert false } }
		wide_witness := read64(wide - 8)
		for stride in [u64(2048), ~u64(63), 17]! {
			unsafe { *(&u64(wide_witness + 72)) = stride }
			if _ := swift_dictionary_storage_for_capacity_checked(12288, code + u64(page) + 4 * 512 + 24) { assert false }
		}
		unsafe { *(&u64(wide_witness + 72)) = 64 }
		assert ios_runtime.swift_heap.len == before
		ios_runtime.swift_dictionary_metadata_retired = true
		assert runtime_symbol(library, symbol) == none
		if _ := swift_dictionary_storage_for_capacity_checked(1, guard) { assert false }
		ios_runtime.swift_dictionary_metadata_retired = false
		ios_runtime.swift_concurrency_retired = true
		assert runtime_symbol(library, symbol) == none
		if _ := swift_dictionary_storage_for_capacity_checked(1, guard) { assert false }
		ios_runtime.swift_concurrency_retired = false
		arena := ios_runtime.swift_dictionary_metadata_arena
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert runtime_symbol(library, symbol) == none && ios_runtime.swift_dictionary_metadata_arena == 0
		assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
	}
	assert C.munmap(voidptr(code), page * 4) == 0
	println('IOS-DICTIONARY-STORAGE-ALLOCATE: native empty allocation and capacity/fresh age/seed contract, independent aligned tails, protected unused witnesses, caller-initialized copy/move lifecycle and reentrant destruction, guarded bounds/lifetimes, eight concurrent workers and two drained/unmapped lifetimes')
}
