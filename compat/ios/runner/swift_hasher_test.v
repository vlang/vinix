// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type HasherCall = fn (u64, u64, u64, u64, u64, &u64) i64
type HasherRawSeed = fn (u64, u64) SwiftHasher
type HasherSeed = fn (i64) SwiftHasher
type HasherNew = fn () SwiftHasher
type HasherSeeds = fn () SwiftStringWords
type HasherDeterministic = fn () bool
type HasherHashWord = fn (i64, u64) i64
type HasherHashPartial = fn (i64, u64, i64) i64
type HasherHashBytes = fn (i64, u64, u64) i64
type HasherSign = fn (u64, u64) u64

const hasher_symbols = ['_$ss6HasherV8_rawSeedABs6UInt64V_AEt_tcfC', '_$ss6HasherV5_seedABSi_tcfC',
	'_$ss6HasherVABycfC', '_$ss6HasherV8_combineyySuF', '_$ss6HasherV8_combineyys6UInt64VF',
	'_$ss6HasherV8_combineyys5UInt8VF', '_$ss6HasherV8_combineyys6UInt16VF', '_$ss6HasherV8_combineyys6UInt32VF',
	'_$ss6HasherV8_combine5bytes5countys6UInt64V_SitF', '_$ss6HasherV7combine5bytesySW_tF',
	'_$ss6HasherV9_finalizeSiyF', '_$ss6HasherV8finalizeSiyF', '_$ss6HasherV7combineyyxSHRzlF',
	'_$sSHsE13_rawHashValue4seedS2i_tF', '_$sSYsSHRzSH8RawValueSYRpzrlE08_rawHashB04seedS2i_tF',
	'_$ss6HasherV14_executionSeeds6UInt64V_AEtvgZ', '_$ss6HasherV16_isDeterministicSbvgZ',
	'_$ss6HasherV5_hash4seed_S2i_SutFZ', '_$ss6HasherV5_hash4seed_S2i_s6UInt64VtFZ',
	'_$ss6HasherV5_hash4seed5bytes5countS2i_s6UInt64VSitFZ', '_$ss6HasherV5_hash4seed5bytesS2i_SWtFZ',
	'__swift_stdlib_Hashing_parameters']!

struct HasherApi {
	native bool
	entries [22]u64
	probe u64
	key0 u64
	key1 u64
}
struct HasherGuard {
mut:
	before u64 = 0x123456789abcdef0
	state SwiftHasher
	after u64 = 0xfedcba9876543210
}
struct HasherScenario {
	api HasherApi
	source u64
	length u64
	initial SwiftHasher
	reenter bool
mut:
	metadata u64
	table u64
	calls int
}
fn hasher_call(api HasherApi, slot int, a u64, b u64, c u64, context u64) i64 {
	call := unsafe { HasherCall(voidptr(api.probe)) }
	mut returned := u64(0)
	result := call(a, b, c, context, api.entries[slot], unsafe { &returned })
	assert returned == context
	return result
}
fn hasher_equal(a &SwiftHasher, b &SwiftHasher) {
	assert C.memcmp(a, b, 72) == 0
}
fn hasher_guard(guard &HasherGuard) {
	assert guard.before == 0x123456789abcdef0 && guard.after == 0xfedcba9876543210
	for word in guard.state.reserved { assert word == 0 }
}
fn hasher_callback(state u64, metadata u64, table u64, receiver u64) {
	mut scenario := unsafe { &HasherScenario(read64(metadata + 8)) }
	assert scenario.metadata == metadata && scenario.table == table && scenario.source == receiver
	hasher_equal(unsafe { &SwiftHasher(state) }, &scenario.initial)
	scenario.calls++
	if scenario.reenter {
		worker := spawn hasher_vectors(scenario.api)
		worker.wait()
	}
	hasher_call(scenario.api, 9, receiver, receiver + scenario.length, 0, state)
}
fn hasher_probe_emit(code u64) {
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd,
		0xaa0503f3, 0xaa0303f4, 0xaa0403f0, 0xd63f0200, 0xf9000274,
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	write32(code + 64, 0xaa1403e3) // Witness self x20 -> ordinary callback x3.
	write32(code + 68, 0x58000070)
	write32(code + 72, 0xd61f0200)
	write32(code + 76, 0xd503201f)
	unsafe { *(&u64(code + 80)) = u64(voidptr(hasher_callback)) }
	write32(code + 96, 0xdac10020) // Native arm64e PWT slot signing only.
	write32(code + 100, 0xd65f03c0)
}
fn hasher_vectors(api HasherApi) {
	if !api.native {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', hasher_symbols[14]) or { panic(err) } == api.entries[14]
	}
	// Native Mac libswiftCore vectors captured by the V vectors.v probe.
	expected := [u64(0xabac0158050fc4dc), 0xc9f49bf37d57ca93, 0x82cb9b024dc7d44d, 0x8bf80ab8e7ddf7fb,
		0xcf75576088d38328, 0xdef9d52f49533b67, 0xc50d2b50c59f22a7, 0xd3927d989bb11140,
		0x369095118d299a8e, 0x25a48eb36c063de4, 0x79de85ee92ff097f, 0x70c118c1f94dc352,
		0x78a384b157b4d9a2, 0x306f760c1229ffa7, 0x605aa111c0f95d34, 0xd320d86d2a519956,
		0xcc4fdd1a7d908b66, 0x9cf2689063dbd80c, 0x8ffc389cb473e63e, 0xf21f9de58d297d1c,
		0xc0dc2f46a6cce040, 0xb992abfe2b45f844, 0x7ffe7b9ba320872e, 0x525a0e7fdae6c123,
		0xf464aeb267349c8c, 0x45cd5928705b0979, 0x3a3e35e3ca9913a5, 0xa91dc74e4ade3b35,
		0xfb0bed02ef6cd00d, 0x88d93cb44ab1e1f4, 0x540f11d643c5e663, 0x2370dd1f8c21d1bc,
		0x81157b6c16a7b60d, 0x4d54b9e57a8ff9bf, 0x759f12781f2a753e, 0xcea1a3bebf186b91,
		0x2cf508d3ada26206, 0xb6101c2da3c33057, 0xb3f47496ae3a36a1, 0x626b57547b108392,
		0xc1d2363299e41531, 0x667cc1923f1ad944, 0x65704ffec8138825, 0x24f280d1c28949a6,
		0xc2ca1cedfaf8876b, 0xc2164bfc9f042196, 0xa16e9c9368b1d623, 0x49fb169c8b5114fd,
		0x9f3143f8df074c46, 0xc6fdaf2412cc86b3, 0x7eaf49d10a52098f, 0x1cf313559d292f9a,
		0xc44a30dda2f41f12, 0x36fae98943a71ed0, 0x318fb34c73f0bce6, 0xa27abf3670a7e980,
		0xb4bcc0db243c6d75, 0x23f8d852fdb71513, 0x8f035f4da67d8a08, 0xd89cd0e5b7e8f148,
		0xf6f4e6bcf7a644ee, 0xaec59ad80f1837f2, 0xc3b2f6154b6694e0, 0x9d199062b7bbb3a8]!
	constructor := unsafe { HasherRawSeed(voidptr(api.entries[0])) }
	mut bytes := [64]u8{}
	for i in 0 .. 64 { bytes[i] = u8(i) }
	start := u64(unsafe { &bytes[0] })
	for length in 0 .. 64 {
		for chunk in [1, 2, 3, 4, 7, 8, 13, 64]! {
			mut guarded := HasherGuard{ state: constructor(0x0706050403020100, 0x0f0e0d0c0b0a0908) }
			mut offset := 0
			for offset < length {
				count := if length - offset < chunk { length - offset } else { chunk }
				hasher_call(api, 9, start + u64(offset), start + u64(offset + count), 0, u64(unsafe { &guarded.state }))
				offset += count
			}
			previous := guarded.state
			assert u64(hasher_call(api, 11, 0, 0, 0, u64(unsafe { &guarded.state }))) == expected[length]
			hasher_equal(&guarded.state, &previous) // Public finalize must not mutate input.
			assert u64(hasher_call(api, 10, 0, 0, 0, u64(unsafe { &guarded.state }))) == expected[length]
			hasher_guard(&guarded)
		}
	}
}
fn hasher_measure(api HasherApi) {
	constructor := unsafe { HasherRawSeed(voidptr(api.entries[0])) }
	seeded := unsafe { HasherSeed(voidptr(api.entries[1])) }
	new := unsafe { HasherNew(voidptr(api.entries[2])) }
	seeds := unsafe { HasherSeeds(voidptr(api.entries[15])) }
	deterministic := unsafe { HasherDeterministic(voidptr(api.entries[16])) }
	parameters := api.entries[21]
	keys := seeds()
	assert keys.first == api.key0 && keys.second == api.key1
	assert read64(parameters) == api.key0 && read64(parameters + 8) == api.key1
	assert unsafe { *(&u8(parameters + 16)) } == u8(deterministic())
	if deterministic() { assert api.key0 == 0 && api.key1 == 0 }
	initial := new(); reference := swift_hasher_raw_seed(api.key0, api.key1)
	hasher_equal(&initial, &reference)
	for seed in [i64(0), 1, -1, i64(-9223372036854775807) - 1, i64(0x7fffffffffffffff)]! {
		initial_seed := seeded(seed)
		reference_seed := swift_hasher_raw_seed(api.key0 ^ u64(seed), api.key1)
		hasher_equal(&initial_seed, &reference_seed)
		for slot in [17, 18]! {
			hash := unsafe { HasherHashWord(voidptr(api.entries[slot])) }
			for word in [u64(0), 1, 0xffffffffffffffff, 0x8000000000000000, 0x0706050403020100]! {
				mut expected := reference_seed; swift_hasher_word(mut expected, word)
				assert hash(seed, word) == swift_hasher_finalize(mut expected)
			}
		}
		partial := unsafe { HasherHashPartial(voidptr(api.entries[19])) }
		for count in 0 .. 8 {
			word := u64(0x0706050403020100) & ((u64(1) << u32(count * 8)) - 1)
			mut expected := reference_seed; swift_hasher_partial(mut expected, word, i64(count))
			assert partial(seed, word, i64(count)) == swift_hasher_finalize(mut expected)
		}
	}
	// Compare every native state transition, including all tail occupancies,
	// partial counts and narrow integer truncation. Counts wrap modulo 256.
	for tail in 0 .. 8 {
		for slot in 3 .. 9 {
			for count in 0 .. 8 {
				mut guarded := HasherGuard{ state: constructor(0x8000000000000000, 0xffffffffffffffff) }
				mut expected := swift_hasher_raw_seed(0x8000000000000000, 0xffffffffffffffff)
				for i in 0 .. 256 + tail {
					hasher_call(api, 5, u64(i), 0, 0, u64(unsafe { &guarded.state }))
					swift_hasher_byte(mut expected, u64(i))
				}
				word := if slot == 8 { u64(0x0706050403020100) & ((u64(1) << u32(count * 8)) - 1) } else { u64(0xfedcba9876543210) }
				hasher_call(api, slot, word, u64(count), 0, u64(unsafe { &guarded.state }))
				match slot {
					3, 4 { swift_hasher_word(mut expected, word) }
					5 { swift_hasher_byte(mut expected, word) }
					6 { swift_hasher_u16(mut expected, word) }
					7 { swift_hasher_u32(mut expected, word) }
					else { swift_hasher_partial(mut expected, word, i64(count)) }
				}
				hasher_equal(&guarded.state, &expected); hasher_guard(&guarded)
				assert hasher_call(api, 10, 0, 0, 0, u64(unsafe { &guarded.state })) == swift_hasher_finalize(mut expected)
				hasher_equal(&guarded.state, &expected)
			}
		}
	}
	hash_bytes := unsafe { HasherHashBytes(voidptr(api.entries[20])) }
	for length in [0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31, 63, 64, 65, 255, 256, 257, 513]! {
		for alignment in 0 .. 8 {
			bytes := C.malloc(usize(if length + alignment == 0 { 1 } else { length + alignment }))
			assert bytes != unsafe { nil }
			start := u64(bytes) + u64(alignment)
			for i in 0 .. length { unsafe { *(&u8(start + u64(i))) = u8(i * 37 + 129) } }
			mut guarded := HasherGuard{ state: constructor(0x123456789abcdef0, 0xfedcba9876543210) }
			mut expected := swift_hasher_raw_seed(0x123456789abcdef0, 0xfedcba9876543210)
			hasher_call(api, 9, start, start + u64(length), 0, u64(unsafe { &guarded.state }))
			swift_hasher_bytes(mut expected, start, start + u64(length))
			hasher_equal(&guarded.state, &expected); hasher_guard(&guarded)
			mut seeded_expected := swift_hasher_raw_seed(api.key0 ^ u64(-1), api.key1)
			swift_hasher_bytes(mut seeded_expected, start, start + u64(length))
			assert hash_bytes(-1, start, start + u64(length)) == swift_hasher_finalize(mut seeded_expected)
			C.free(bytes)
		}
	}
	mut empty := initial
	hasher_call(api, 9, 0, 0, 0, u64(unsafe { &empty }))
	hasher_equal(&empty, &initial)
}
fn hasher_defaults(api HasherApi, length int, reenter bool) {
	bytes := C.malloc(usize(length)); assert bytes != unsafe { nil }
	defer { C.free(bytes) }
	for i in 0 .. length { unsafe { *(&u8(u64(bytes) + u64(i))) = u8(i * 19 + 7) } }
	for seed in [i64(0), 1, -1, i64(-9223372036854775807) - 1, i64(0x7fffffffffffffff)]! {
		initial := swift_hasher_raw_seed(api.key0 ^ u64(seed), api.key1)
		mut expected := initial; swift_hasher_bytes(mut expected, u64(bytes), u64(bytes) + u64(length))
		result := swift_hasher_finalize(mut expected)
		mut scenario := HasherScenario{ api: api, source: u64(bytes), length: u64(length), initial: initial, reenter: reenter }
		mut metadata := [u64(0x200), u64(unsafe { &scenario })]!
		mut table := [u64(0xdead), u64(0xbeef), u64(0), api.probe + 64, u64(0)]!
		scenario.metadata = u64(unsafe { &metadata[0] }); scenario.table = u64(unsafe { &table[0] })
		$if macos {
			if api.native {
				sign := unsafe { HasherSign(voidptr(api.probe + 96)) }
				table[3] = sign(table[3], (scenario.table + 24) | (u64(15753) << 48))
			}
		}
		for slot in [13, 14]! {
			assert hasher_call(api, slot, u64(seed), scenario.metadata, scenario.table, u64(bytes)) == result
		}
		mut guarded := HasherGuard{ state: initial }
		hasher_call(api, 12, u64(bytes), scenario.metadata, scenario.table, u64(unsafe { &guarded.state }))
		assert hasher_call(api, 11, 0, 0, 0, u64(unsafe { &guarded.state })) == result
		hasher_guard(&guarded); assert scenario.calls == 3
		for i in 0 .. length { assert unsafe { *(&u8(u64(bytes) + u64(i))) } == u8(i * 19 + 7) }
	}
}
fn hasher_resolver() {
	mut entries := [22]u64{}
	for iteration in 0 .. 50 {
		for i, symbol in hasher_symbols {
			entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
			if iteration == 0 { entries[i] = entry } else { assert entry == entries[i] }
		}
	}
}
fn hasher_run(api HasherApi) {
	hasher_vectors(api); hasher_measure(api)
	hasher_defaults(api, 1, false); hasher_defaults(api, 16, true)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn hasher_defaults(api, 17, false) }
	workers.wait()
}
fn test_swift_hasher() {
	assert sizeof(SwiftHasher) == 72 && sizeof(SwiftHashingParameters) == 24
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page) == 0 }
	hasher_probe_emit(u64(code)); C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 104) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		mut entries := [22]u64{}
		for i, symbol in hasher_symbols { entries[i] = u64(C.dlsym(lib, symbol[1..].str)); assert entries[i] != 0 }
		hasher_run(HasherApi{ native: true, entries: entries, probe: u64(code), key0: read64(entries[21]), key1: read64(entries[21] + 8) })
		println('IOS-SWIFT-HASHER-NATIVE: 72-byte layout, native SipHash-1-3 vectors/state transitions, initializer/scalar/buffer/finalizer ABI, signed seeds, tail/count wrap, generic callback/context preservation, borrowed receivers and concurrent/reentrant defaults')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut resolvers := []thread{}
		for _ in 0 .. 8 { resolvers << spawn hasher_resolver() }
		resolvers.wait()
		mut entries := [22]u64{}
		for i, symbol in hasher_symbols { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) } }
		hasher_run(HasherApi{ entries: entries, probe: u64(code), key0: read64(entries[21]), key1: read64(entries[21] + 8) })
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss6HasherVN') { assert false }
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_hash_code == 0 && ios_runtime.swift_metadata_arena == 0
		assert swift_hashing_ready && read64(entries[21]) == swift_hashing_parameters.seed0
		assert read64(entries[21] + 8) == swift_hashing_parameters.seed1
	}
	println('IOS-SWIFT-HASHER: native captured vectors, all tail/partial/narrow integer transitions, count wrap, unaligned/exact bounded buffers, signed seed boundaries, guarded 72-byte state, public copy/internal mutating finalize, process seeds, generic combine and both raw-hash defaults, borrowed one-byte/16-byte receivers, eight concurrent publication/callback workers, reentrant symbol resolution and two empty teardowns')
}
