// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.__builtin_alloca(usize) voidptr

// Frozen ARM64 Hasher layout, measured against the installed libswiftCore.
// The last four state words are reserved and stay zero. SipHash-1-3 and the
// tail/count encoding are described in Swift's Hasher.swift and SipHash.swift.
struct SwiftHasher {
mut:
	tail u64
	v0 u64
	v1 u64
	v2 u64
	v3 u64
	reserved [4]u64
}
struct SwiftHashingParameters {
mut:
	seed0 u64
	seed1 u64
	deterministic bool
}
__global swift_hashing_parameters = SwiftHashingParameters{}
__global swift_hashing_ready bool

fn swift_hasher_initialize() {
	// Process-wide seeds also serve client-inlined Hasher initialization. They
	// survive runtime shutdown, like the native process-wide parameters.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if swift_hashing_ready { return }
	setting := C.getenv(c'SWIFT_DETERMINISTIC_HASHING')
	if setting != unsafe { nil } && unsafe { C.strcmp(setting, c'1') } == 0 {
		swift_hashing_parameters.deterministic = true
	} else if C.getentropy(unsafe { &swift_hashing_parameters.seed0 }, 16) != 0 {
		panic('iOS: cannot initialize Swift hashing seeds')
	}
	swift_hashing_ready = true
}

fn swift_hasher_raw_seed(key0 u64, key1 u64) SwiftHasher {
	return SwiftHasher{
		v0: key0 ^ u64(0x736f6d6570736575), v1: key1 ^ u64(0x646f72616e646f6d),
		v2: key0 ^ u64(0x6c7967656e657261), v3: key1 ^ u64(0x7465646279746573)
	}
}
fn swift_hasher_seed(seed i64) SwiftHasher {
	return swift_hasher_raw_seed(swift_hashing_parameters.seed0 ^ u64(seed), swift_hashing_parameters.seed1)
}
fn swift_hasher_new() SwiftHasher { return swift_hasher_seed(0) }
fn swift_hasher_seed_into(output &SwiftHasher, seed i64) {
	unsafe { *output = swift_hasher_seed(seed) }
}
fn swift_hasher_seeds() SwiftStringWords {
	return SwiftStringWords{ first: swift_hashing_parameters.seed0, second: swift_hashing_parameters.seed1 }
}
fn swift_hasher_deterministic() bool { return swift_hashing_parameters.deterministic }

@[inline]
fn swift_hash_rotate(value u64, bits u32) u64 { return (value << bits) | (value >> (64 - bits)) }
fn swift_hasher_round(mut state SwiftHasher) {
	state.v0 += state.v1
	state.v1 = swift_hash_rotate(state.v1, 13) ^ state.v0
	state.v0 = swift_hash_rotate(state.v0, 32)
	state.v2 += state.v3
	state.v3 = swift_hash_rotate(state.v3, 16) ^ state.v2
	state.v0 += state.v3
	state.v3 = swift_hash_rotate(state.v3, 21) ^ state.v0
	state.v2 += state.v1
	state.v1 = swift_hash_rotate(state.v1, 17) ^ state.v2
	state.v2 = swift_hash_rotate(state.v2, 32)
}
fn swift_hasher_compress(mut state SwiftHasher, word u64) {
	state.v3 ^= word
	swift_hasher_round(mut state)
	state.v0 ^= word
}
fn swift_hasher_word(mut state SwiftHasher, word u64) {
	count := (state.tail >> 56) & 7
	if count == 0 {
		state.tail += u64(8) << 56
		swift_hasher_compress(mut state, word)
		return
	}
	shift := u32(count * 8)
	chunk := (state.tail & u64(0x00ffffffffffffff)) | (word << shift)
	state.tail = (((state.tail >> 56) + 8) << 56) | (word >> (64 - shift))
	swift_hasher_compress(mut state, chunk)
}
fn swift_hasher_partial(mut state SwiftHasher, bytes u64, length i64) {
	if length < 0 || length > 7 { panic('iOS: invalid Swift Hasher partial byte count') }
	// Callers supply only the requested low bytes; reject invalid internal
	// inputs instead of allowing high bits to corrupt the tail count.
	if bytes >> u32(length * 8) != 0 { panic('iOS: invalid Swift Hasher partial bytes') }
	count := (state.tail >> 56) & 7
	shift := u32(count * 8)
	if count + u64(length) < 8 {
		state.tail = (state.tail | (bytes << shift)) + (u64(length) << 56)
		return
	}
	chunk := (state.tail & u64(0x00ffffffffffffff)) | (bytes << shift)
	state.tail = ((state.tail >> 56) + u64(length)) << 56
	if count + u64(length) > 8 { state.tail |= bytes >> (64 - shift) }
	swift_hasher_compress(mut state, chunk)
}
fn swift_hasher_byte(mut state SwiftHasher, value u64) { swift_hasher_partial(mut state, value & 0xff, 1) }
fn swift_hasher_u16(mut state SwiftHasher, value u64) { swift_hasher_partial(mut state, value & 0xffff, 2) }
fn swift_hasher_u32(mut state SwiftHasher, value u64) { swift_hasher_partial(mut state, value & 0xffffffff, 4) }
fn swift_hasher_bytes(mut state SwiftHasher, start u64, end u64) {
	// UnsafeRawBufferPointer's frozen representation is start/end, not a
	// pointer/count pair. Empty nil buffers require no reads.
	if start == 0 { return }
	if end < start || end - start > u64(0x7fffffffffffffff) { panic('iOS: invalid Swift hashing buffer') }
	mut address := start
	for end - address >= 8 {
		mut word := u64(0)
		// Byte loads accept every alignment and never read past the buffer.
		for i in 0 .. 8 { word |= u64(unsafe { *(&u8(address + u64(i))) }) << u32(i * 8) }
		swift_hasher_word(mut state, word)
		address += 8
	}
	mut word := u64(0)
	length := end - address
	for i in 0 .. int(length) { word |= u64(unsafe { *(&u8(address + u64(i))) }) << u32(i * 8) }
	swift_hasher_partial(mut state, word, i64(length))
}
fn swift_hasher_finalize(mut state SwiftHasher) i64 {
	swift_hasher_compress(mut state, state.tail)
	state.v2 ^= 0xff
	for _ in 0 .. 3 { swift_hasher_round(mut state) }
	return i64(state.v0 ^ state.v1 ^ state.v2 ^ state.v3)
}
fn swift_hasher_finish(state &SwiftHasher) i64 {
	// Public consuming finalize computes on a copy; the native entry does not
	// alter the passed storage. Internal _finalize mutates it in place.
	// Function-scoped stack storage avoids this V compiler's promotion of
	// locals passed to bodies also used as ABI entries. No pointer escapes.
	mut value := unsafe { &SwiftHasher(C.__builtin_alloca(sizeof(SwiftHasher))) }
	unsafe { *value = *state }
	return swift_hasher_finalize(mut value)
}
fn swift_hasher_hash_word(seed i64, word u64) i64 {
	mut state := unsafe { &SwiftHasher(C.__builtin_alloca(sizeof(SwiftHasher))) }
	unsafe { *state = swift_hasher_seed(seed) }
	swift_hasher_word(mut state, word)
	return swift_hasher_finalize(mut state)
}
fn swift_hasher_hash_partial(seed i64, word u64, count i64) i64 {
	mut state := unsafe { &SwiftHasher(C.__builtin_alloca(sizeof(SwiftHasher))) }
	unsafe { *state = swift_hasher_seed(seed) }
	swift_hasher_partial(mut state, word, count)
	return swift_hasher_finalize(mut state)
}
fn swift_hasher_hash_bytes(seed i64, start u64, end u64) i64 {
	mut state := unsafe { &SwiftHasher(C.__builtin_alloca(sizeof(SwiftHasher))) }
	unsafe { *state = swift_hasher_seed(seed) }
	swift_hasher_bytes(mut state, start, end)
	return swift_hasher_finalize(mut state)
}

// Swift mutating methods carry self in x20. Adapt to an ordinary V body with
// the state pointer in x0, shifting the zero, one or two scalar arguments.
fn swift_hasher_bridge(code u64, body u64, arguments int) {
	write32(code, if arguments == 2 { u32(0xaa0103e2) } else { u32(0xd503201f) })
	write32(code + 4, if arguments >= 1 { u32(0xaa0003e1) } else { u32(0xd503201f) })
	write32(code + 8, 0xaa1403e0) // mov x0,x20
	write32(code + 12, 0x58000070) // ldr x16,+12
	write32(code + 16, 0xd61f0200) // br x16
	write32(code + 20, 0xd503201f)
	unsafe { *(&u64(code + 24)) = body }
}
fn swift_hasher_emit(code u64) {
	// Both Hashable and RawRepresentable defaults borrow indirect Self in
	// x20, seed x0, metadata x1 and Self Hashable table x2. A 72-byte local
	// Hasher lives at sp+48. Save metadata/table across the V initializer and
	// preserve all caller context; no registry lock crosses the witness call.
	for i, op in [u32(0xa9b87bfd), // stp fp,lr,[sp,#-128]!
		0xa90153f3, 0xa9025bf5, 0x910003fd,
		0xaa0103f3, 0xaa0203f5, // x19=metadata, x21=table
		0xaa0003e1, 0x9100c3e0, // seed x1, output sp+48 x0
		0x58000210, 0xd63f0200, // initializer literal at +96
		0xaa1303e1, 0xaa1503e2, 0x9100c3e0,
		0xf9400eb0, 0xd63f0200, // ldr x16,[x21,#24]; blr
		0x9100c3e0, 0x58000150, 0xd63f0200, // finalizer literal at +104
		0xa9425bf5, 0xa94153f3, 0xa8c87bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	unsafe {
		*(&u64(code + 96)) = u64(voidptr(swift_hasher_seed_into))
		*(&u64(code + 104)) = u64(voidptr(swift_hasher_finalize))
	}
	// Generic combine: borrowed value x0, metadata x1, table x2; Hasher self
	// x20. Use the value as witness context and restore the Hasher afterwards.
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd,
		0xaa0003e8, 0xaa1403e0, 0xaa0803f4, 0xf9400c50, 0xd63f0200,
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + 128 + u64(i * 4), op) }
	for i, body in [u64(unsafe { voidptr(swift_hasher_word) }),
		u64(unsafe { voidptr(swift_hasher_byte) }), u64(unsafe { voidptr(swift_hasher_u16) }),
		u64(unsafe { voidptr(swift_hasher_u32) }), u64(unsafe { voidptr(swift_hasher_partial) }),
		u64(unsafe { voidptr(swift_hasher_bytes) }), u64(unsafe { voidptr(swift_hasher_finalize) }),
		u64(unsafe { voidptr(swift_hasher_finish) })]! {
		swift_hasher_bridge(code + 192 + u64(i * 32), body, if i == 4 || i == 5 { 2 } else if i == 6 || i == 7 { 0 } else { 1 })
	}
}
fn swift_hasher_symbol(symbol string) ?u64 {
	// Only measured functions/data are provided. Hasher type metadata and
	// concrete standard-library Hashable conformances remain unsupported.
	offset := match symbol {
		'_$sSHsE13_rawHashValue4seedS2i_tF', '_$sSYsSHRzSH8RawValueSYRpzrlE08_rawHashB04seedS2i_tF' { 192 }
		'_$ss6HasherV7combineyyxSHRzlF' { 320 }
		'_$ss6HasherV8_combineyySuF', '_$ss6HasherV8_combineyys6UInt64VF' { 384 }
		'_$ss6HasherV8_combineyys5UInt8VF' { 416 }
		'_$ss6HasherV8_combineyys6UInt16VF' { 448 }
		'_$ss6HasherV8_combineyys6UInt32VF' { 480 }
		'_$ss6HasherV8_combine5bytes5countys6UInt64V_SitF' { 512 }
		'_$ss6HasherV7combine5bytesySW_tF' { 544 }
		'_$ss6HasherV9_finalizeSiyF' { 576 }
		'_$ss6HasherV8finalizeSiyF' { 608 }
		else { -1 }
	}
	if offset >= 0 { return swift_hash_entry(u64(offset)) }
	address := match symbol {
		'__swift_stdlib_Hashing_parameters' { u64(unsafe { &swift_hashing_parameters }) }
		'_$ss6HasherVABycfC' { u64(unsafe { voidptr(swift_hasher_new) }) }
		'_$ss6HasherV5_seedABSi_tcfC' { u64(unsafe { voidptr(swift_hasher_seed) }) }
		'_$ss6HasherV8_rawSeedABs6UInt64V_AEt_tcfC' { u64(unsafe { voidptr(swift_hasher_raw_seed) }) }
		'_$ss6HasherV14_executionSeeds6UInt64V_AEtvgZ' { u64(unsafe { voidptr(swift_hasher_seeds) }) }
		'_$ss6HasherV16_isDeterministicSbvgZ' { u64(unsafe { voidptr(swift_hasher_deterministic) }) }
		'_$ss6HasherV5_hash4seed_S2i_SutFZ', '_$ss6HasherV5_hash4seed_S2i_s6UInt64VtFZ' { u64(unsafe { voidptr(swift_hasher_hash_word) }) }
		'_$ss6HasherV5_hash4seed5bytes5countS2i_s6UInt64VSitFZ' { u64(unsafe { voidptr(swift_hasher_hash_partial) }) }
		'_$ss6HasherV5_hash4seed5bytesS2i_SWtFZ' { u64(unsafe { voidptr(swift_hasher_hash_bytes) }) }
		else { return none }
	}
	swift_hasher_initialize()
	return address
}
