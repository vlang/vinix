// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.mincore(voidptr, usize, &u8) i32
type IntHashProbe = fn (u64, u64, u64, u64, u64, &u64) i64
type IntHashAccessor = fn (u64) SwiftAssociatedMetadata
type IntHashArray = fn (u64, u64) SwiftAssociatedMetadata
type IntHashCopy = fn (u64, u64, u64) u64
type IntHashDestroy = fn (u64, u64)
type IntHashGet = fn (u64, u32, u64) u32
type IntHashStore = fn (u64, u32, u32, u64)
type IntHashEqual = fn (u64, u64) bool
type IntHashEqualWitness = fn (u64, u64, u64, u64) bool

const int_hash_symbols = ['_$sSiN', '_$sSiMn', '_$sSiMa', '_$sSiSHsWP', '_$sSiSQsWP',
	'_$sSiSHsMc', '_$sSiSQsMc', '_$sSHMp', '_$sSHTL', '_$sSH9hashValueSivgTq',
	'_$sSH4hash4intoys6HasherVz_tFTq', '_$sSH13_rawHashValue4seedS2i_tFTq', '_$sSQMp', '_$sSQTL',
	'_$sSQ2eeoiySbx_xtFZTq', '_$sSQ2eeoiySbx_xtFZTj', '_$sSi2eeoiySbSi_SitFZ',
	'_$sSi9hashValueSivg', '_$sSi4hash4intoys6HasherVz_tF', '_$sSi13_rawHashValue4seedS2i_tF',
	'_$sSH9hashValueSivgTj', '_$sSH4hash4intoys6HasherVz_tFTj', '_$sSH13_rawHashValue4seedS2i_tFTj',
	'_$sSHsE13_rawHashValue4seedS2i_tF', '_$ss6HasherV7combineyyxSHRzlF', '_$ss10_hashValue3forSix_tSHRzlF',
	'__swift_stdlib_Hashing_parameters', '_$sSHSQTb']!
struct IntHashApi {
	native bool
	entries [28]u64
	probe IntHashProbe
}
struct IntHashGuard {
mut:
	before u64 = 0x123456789abcdef0
	state SwiftHasher
	after u64 = 0xfedcba9876543210
}
fn int_hash_relative(field u64) u64 { return u64(i64(field) + i64(unsafe { *(&i32(field)) })) }
fn int_hash_call(api IntHashApi, entry u64, a u64, b u64, c u64, context u64) i64 {
	mut returned := u64(0)
	value := api.probe(a, b, c, context, entry, unsafe { &returned })
	assert returned == context
	return value
}
fn int_hash_layout(api IntHashApi) {
	meta := api.entries[0]; desc := api.entries[1]
	assert read64(meta) == 0x200 && read64(meta + 8) == desc && read64(meta + 16) == 0
	accessor := unsafe { IntHashAccessor(voidptr(api.entries[2])) }
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x1ff]! {
		response := accessor(request)
		assert response.metadata == meta && response.state == 0
	}
	assert unsafe { *(&u32(desc)) } == 0x51
	assert unsafe { *(&u32(desc + 20)) } == 1 && unsafe { *(&u32(desc + 24)) } == 2
	assert int_hash_relative(desc + 12) == api.entries[2]
	assert unsafe { (&char(int_hash_relative(desc + 8))).vstring() } == 'Int'
	module_desc := int_hash_relative(desc + 4)
	assert unsafe { (&char(int_hash_relative(module_desc + 8))).vstring() } == 'Swift'
	vwt := read64(meta - 8)
	assert read64(vwt + 64) == 8 && read64(vwt + 72) == 8 && read64(vwt + 80) == 7
	for i in 0 .. 2 {
		table := api.entries[3 + i]; conf := api.entries[5 + i]
		protocol := api.entries[if i == 0 { 7 } else { 12 }]
		assert read64(table) == conf
		assert int_hash_relative(conf) == protocol && int_hash_relative(conf + 4) == desc
		assert int_hash_relative(conf + 8) == table && unsafe { *(&u32(conf + 12)) } == 0
		assert unsafe { *(&u32(protocol)) } == 0x30043
		assert int_hash_relative(protocol + 4) == module_desc
		assert unsafe { (&char(int_hash_relative(protocol + 8))).vstring() } == if i == 0 { 'Hashable' } else { 'Equatable' }
	}
	hash := api.entries[7]; equal := api.entries[12]
	assert read64(api.entries[3] + 8) == api.entries[4]
	assert unsafe { *(&u32(hash + 12)) } == 1 && unsafe { *(&u32(hash + 16)) } == 4
	assert unsafe { *(&u32(hash + 24)) } == 0x80
	assert unsafe { (&char(int_hash_relative(hash + 28))).vstring() } == 'x'
	assert int_hash_relative(hash + 32) == equal
	assert api.entries[8] == hash + 28 && api.entries[13] == equal + 16
	// This export names the actual first requirement, preserving pointer
	// identity and its witness-table index independently of the symbol spelling.
	assert api.entries[27] == hash + 36
	assert unsafe { *(&u32(api.entries[27])) } == 0
	assert unsafe { *(&i32(api.entries[27] + 4)) } == 0
	assert read64(api.entries[3] + 8) == api.entries[4]
	for i, flags in [u32(0), 0x026b0013, 0x3d890011, 0xc41a0011]! {
		assert unsafe { *(&u32(hash + 36 + u64(i * 8))) } == flags
		if i > 0 { assert api.entries[8 + i] == hash + 36 + u64(i * 8) }
	}
	assert unsafe { *(&u32(equal + 12)) } == 0 && unsafe { *(&u32(equal + 16)) } == 1
	assert api.entries[14] == equal + 24 && unsafe { *(&u32(equal + 24)) } == 0x97eb0001
	assert int_hash_relative(hash + 64) != 0
}
fn int_hash_values(api IntHashApi) {
	int_hash_value_table(api.entries[0], read64(api.entries[0] - 8))
}
fn int_hash_value_table(meta u64, vwt u64) {
	assert read64(vwt + 64) == 8 && read64(vwt + 72) == 8 && read64(vwt + 80) == 7
	// ASAN sees the exact eight-byte allocation: no spare byte may be read by
	// destruction or the zero-empty-case enum witnesses.
	source := u64(C.malloc(8)); assert source != 0
	defer { C.free(unsafe { voidptr(source) }) }
	mut destination := [u64(0x5555555555555555), 0xaaaaaaaaaaaaaaaa, 0xfedcba9876543210]!
	for bits in [u64(0), 1, 0x7fffffffffffffff, 0x8000000000000000, 0xffffffffffffffff]! {
		unsafe { *(&u64(source)) = bits }
		for slot in [0, 2, 3, 4, 5]! {
			copy_value := unsafe { IntHashCopy(voidptr(read64(vwt + u64(slot * 8)))) }
			dest := u64(unsafe { &destination[0] })
			assert copy_value(dest, source, meta) == dest && destination[0] == bits && read64(source) == bits
			assert destination[1] == 0xaaaaaaaaaaaaaaaa && destination[2] == 0xfedcba9876543210
			assert copy_value(source, source, meta) == source && read64(source) == bits
		}
		destroy := unsafe { IntHashDestroy(voidptr(read64(vwt + 8))) }; destroy(source, meta)
		assert read64(source) == bits
	}
	get := unsafe { IntHashGet(voidptr(read64(vwt + 48))) }
	store := unsafe { IntHashStore(voidptr(read64(vwt + 56))) }
	store(source, 0, 0, meta); assert get(source, 0, meta) == 0
	assert read64(source) == 0xffffffffffffffff
	for count in [u32(1),255,256,0x7fffffff,0x80000000,0xffffffff]! {
		for tag in [u32(0),1,255,256,0x7fffffff,0x80000000,0xffffffff]! {
			if tag > count { continue }
			mut bytes := [u8(0x55)].repeat(10)
			store(u64(bytes.data), tag, count, meta)
			assert get(u64(bytes.data), count, meta) == tag && bytes[9] == 0x55
			for i in 0 .. 8 { assert bytes[i] == if tag == 0 { u8(0x55) } else { u8(u64(tag - 1) >> u32(i * 8)) } }
			assert bytes[8] == if tag == 0 { u8(0) } else { u8(1) }
		}
	}
}

fn builtin_integer_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sBi64_WV') or { panic(err) }
}

fn test_swift_builtin_int64_value_witness_export() {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		meta := u64(C.dlsym(lib, c'$sSiN'))
		table := u64(C.dlsym(lib, c'$sBi64_WV'))
		assert meta != 0 && table != 0 && table == read64(meta - 8)
		int_hash_value_table(meta, table)
		assert C.dlclose(lib) == 0
		println('IOS-SWIFT-BUILTIN-NATIVE: exact shared Int64 table, all eight witnesses, alias copies, signed boundaries, zero-empty-case bounds and guarded enum storage passed')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn builtin_integer_resolve() }
		resolved := resolvers.wait()
		table := resolved[0]
		for address in resolved { assert address != 0 && address == table }
		unsafe { resolved.free(); resolvers.free() }
		meta := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSiN') or { panic(err) }
		assert table == read64(meta - 8) && table != meta
		assert table == swift_integer_symbol('_$sBi64_WV') or { panic('missing builtin table') }
		if _ := swift_integer_symbol('_$sBi32_WV') { assert false }
		if _ := swift_integer_symbol('_$sBi128_WV') { assert false }
		mut snapshot := [11]u64{}
		for i in 0 .. 11 { snapshot[i] = read64(table + u64(i * 8)) }
		int_hash_value_table(meta, table)
		for i in 0 .. 11 { assert snapshot[i] == read64(table + u64(i * 8)) }
		arena := ios_runtime.swift_integer_arena
		page := usize(C.getpagesize())
		assert arena != 0 && table == arena + u64(page) + 64
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_integer_arena == 0
		for offset in 0 .. 2 {
			address := arena + u64(offset) * u64(page)
			$if macos { assert C.mprotect(unsafe { voidptr(address) }, page, C.PROT_READ) == -1 }
			$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(address) }, page, unsafe { &residency }) == -1 }
		}
	}
	println('IOS-SWIFT-BUILTIN: canonical Int64 data export, native witness behavior, eight concurrent resolvers, unchanged table and two retired runtime lifetimes passed')
}
fn int_hash_word(api IntHashApi, value u64) {
	meta := api.entries[0]; table := api.entries[3]
	mut bits := value; mut other := value
	self := u64(unsafe { &bits }); rhs := u64(unsafe { &other })
	equal := unsafe { IntHashEqual(voidptr(api.entries[16])) }
	assert equal(value, value) && !equal(value, value ^ 1)
	for entry in [read64(api.entries[4] + 8), api.entries[15]]! {
		eq := unsafe { IntHashEqualWitness(voidptr(entry)) }
		assert eq(self, rhs, meta, api.entries[4])
		other ^= 1; assert !eq(self, rhs, meta, api.entries[4]); other ^= 1
	}
	key0 := read64(api.entries[26]); key1 := read64(api.entries[26] + 8)
	for seed in [i64(0), 1, -1, 9223372036854775807, i64(-9223372036854775807) - 1]! {
		mut model := swift_hasher_raw_seed(key0 ^ u64(seed), key1)
		swift_hasher_word(mut model, value)
		expected := swift_hasher_finalize(mut model)
		assert int_hash_call(api, api.entries[19], u64(seed), value, 0, self) == expected
		for entry in [read64(table + 32), api.entries[22], api.entries[23], int_hash_relative(api.entries[7] + 64)]! {
			assert int_hash_call(api, entry, u64(seed), meta, table, self) == expected
		}
		if seed == 0 {
			assert int_hash_call(api, api.entries[17], value, 0, 0, self) == expected
			for entry in [read64(table + 16), api.entries[20]]! {
				assert int_hash_call(api, entry, meta, table, 0, self) == expected
			}
			assert int_hash_call(api, api.entries[25], self, meta, table, self) == expected
		}
	}
	for tail in 0 .. 8 {
		mut initial := swift_hasher_raw_seed(0x123456789abcdef0, 0xfedcba9876543210)
		swift_hasher_partial(mut initial, 0x00123456789abcde & ((u64(1) << u32(tail * 8)) - 1), i64(tail))
		mut model := initial; swift_hasher_word(mut model, value)
		for entry in [api.entries[18], read64(table + 24), api.entries[21], api.entries[24]]! {
			mut guarded := IntHashGuard{ state: initial }
			state := u64(unsafe { &guarded.state })
			if entry == api.entries[18] { int_hash_call(api, entry, state, value, 0, self) }
			else if entry == api.entries[24] { int_hash_call(api, entry, self, meta, table, state) }
			else { int_hash_call(api, entry, state, meta, table, self) }
			assert C.memcmp(unsafe { &guarded.state }, &model, 72) == 0
			assert guarded.before == 0x123456789abcdef0 && guarded.after == 0xfedcba9876543210
		}
	}
	assert bits == value && other == value
	if !api.native {
		for i, symbol in int_hash_symbols { assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) } == api.entries[i] }
	}
}
fn int_hash_worker(api IntHashApi, index int) {
	for i in 0 .. 64 { int_hash_word(api, (u64(1) << u32(i)) ^ (u64(index) << 56)) }
}
fn int_hash_resolver() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSiSHsWP') or { panic(err) }
}
fn int_hash_run(api IntHashApi) {
	int_hash_layout(api); int_hash_values(api)
	for value in [u64(0),1,0x7fffffffffffffff,0x8000000000000000,0xffffffffffffffff]! { int_hash_word(api, value) }
	for bit in 0 .. 64 { int_hash_word(api, u64(1) << u32(bit)); int_hash_word(api, ~(u64(1) << u32(bit))) }
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn int_hash_worker(api, i) }; workers.wait()
}
fn test_swift_integer_hashable() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd, 0xaa0503f3, 0xaa0303f4,
		0xaa0403f0, 0xd63f0200, 0xf9000274, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 44) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	defer { assert C.munmap(code, page) == 0 }
	probe := unsafe { IntHashProbe(code) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		mut entries := [28]u64{}
		for i, name in int_hash_symbols { entries[i] = u64(C.dlsym(lib, name[1..].str)); assert entries[i] != 0, name }
		int_hash_run(IntHashApi{ native: true, entries: entries, probe: probe })
		println('IOS-SWIFT-INTEGER-HASH-NATIVE: Int metadata/value witnesses, exact enum storage, Hashable base conformance descriptor, Equatable, seeded hashing, witness/default/generic dispatch and preserved context matched')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn int_hash_resolver() }
		resolved := resolvers.wait()
		for address in resolved { assert address == resolved[0] && address != 0 }
		mut entries := [28]u64{}
		for i, name in int_hash_symbols { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		int_hash_run(IntHashApi{ entries: entries, probe: probe })
		array_accessor := unsafe { IntHashArray(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSaMa') or { panic(err) })) }
		response := array_accessor(0, entries[0])
		assert read64(response.metadata + 16) == entries[0] && response.state == 0
		arena := ios_runtime.swift_integer_arena
		assert arena != 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getGenericMetadata') == none
		objc_stop()
		for offset in 0 .. 2 {
			address := arena + u64(offset) * u64(page)
			$if macos { assert C.mprotect(unsafe { voidptr(address) }, page, C.PROT_READ) == -1 }
			$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(address) }, page, unsafe { &residency }) == -1 }
		}
	}
	println('IOS-SWIFT-INTEGER-HASH: real Int metadata, Hashable base conformance descriptor and inherited Equatable/Hashable tables, all value witnesses, enums, seeded/generic hashing, eight workers, Array<Int> and two drained teardowns')
}
