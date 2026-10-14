// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftRawEqualityFailure {}
fn (_ &SwiftRawEqualityFailure) msg() string { return 'iOS: unsupported or invalid Swift RawValue equality layout' }
fn (_ &SwiftRawEqualityFailure) code() int { return 1 }
__global swift_raw_equality_failure_value = SwiftRawEqualityFailure{}
fn swift_raw_equality_failure() IError { return unsafe { &swift_raw_equality_failure_value } }
struct SwiftRawEqualityLayout {
	metadata u64
	size u64
	getter u64
	equal u64
	destroy u64
}
type SwiftRawEqualityCall = fn (u64,u64,u64,u64,u64) u64

// ABI records and Self addresses are borrowed readable caller-owned spans.
// Check the supported dynamic layout before constructing either owned value.
fn swift_raw_equality_layout(metadata u64, raw_table u64, equal_table u64) !SwiftRawEqualityLayout {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| metadata < 8 || metadata & 7 != 0 || raw_table == 0 || equal_table == 0
		|| raw_table & 7 != 0 || equal_table & 7 != 0
		|| raw_table > ~u64(0) - 32 || equal_table > ~u64(0) - 16 { return swift_raw_equality_failure() }
	mut raw_metadata := C.ios_load_pointer(unsafe { &u64(raw_table + 8) })
	if raw_metadata == 0 { return swift_raw_equality_failure() }
	if raw_metadata & 1 != 0 {
		mut name := raw_metadata & ~u64(1)
		if name == 0 || name > ~u64(0) - 4 { return swift_raw_equality_failure() }
		if unsafe { *(&u8(name)) } == 0xff { name++ }
		if unsafe { *(&u8(name)) } != `S` || unsafe { *(&u8(name + 1)) } != `S`
			|| unsafe { *(&u8(name + 2)) } != 0 { return swift_raw_equality_failure() }
		protocol := swift_string_metadata() - 16 + 448
		raw_metadata = swift_associated_type(0,raw_table,metadata,protocol + 16,protocol + 24).metadata
	}
	if raw_metadata < 8 || raw_metadata & 7 != 0 || raw_metadata > ~u64(0) - 8 { return swift_raw_equality_failure() }
	witness := read64(raw_metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 { return swift_raw_equality_failure() }
	size := read64(witness + 64)
	stride := read64(witness + 72)
	flags := read32(witness + 80)
	alignment := u64(flags & 0xff) + 1
	if size > 65536 || stride < size || alignment > 16 || alignment & (alignment - 1) != 0
		|| stride & (alignment - 1) != 0 || flags & 0x00400000 != 0 { return swift_raw_equality_failure() }
	getter := read64(raw_table + 24)
	equal := read64(equal_table + 8)
	destroy := read64(witness + 8)
	if getter == 0 || equal == 0 || destroy == 0 { return swift_raw_equality_failure() }
	return SwiftRawEqualityLayout{raw_metadata,size,getter,equal,destroy}
}

// Measured ARM64: borrowed lhs/rhs x0/x1, Self metadata x2,
// RawRepresentable x3, RawValue Equatable x4, Bool in the low bit of w0.
fn swift_raw_equal_checked(left u64, right u64, metadata u64, raw_table u64, equal_table u64) !bool {
	if left == 0 || right == 0 { return swift_raw_equality_failure() }
	layout := swift_raw_equality_layout(metadata,raw_table,equal_table)!
	getter := unsafe { SwiftRawGetterCall(voidptr(swift_hash_entry(672))) }
	equal := unsafe { SwiftRawEqualityCall(voidptr(swift_hash_entry(800))) }
	destroy := unsafe { SwiftRawDestroy(voidptr(layout.destroy)) }
	rounded := (layout.size + 15) & ~u64(15)
	// One stack extent reproduces two 16-byte-rounded native temporaries.
	// Zero-size values can share their address; no scratch escapes this call.
	lhs := u64(C.__builtin_alloca(usize(rounded * 2)))
	rhs := lhs + rounded
	getter(layout.getter,lhs,metadata,raw_table,left)
	getter(layout.getter,rhs,metadata,raw_table,right)
	result := equal(lhs,rhs,layout.metadata,equal_table,layout.equal)
	destroy(rhs,layout.metadata)
	destroy(lhs,layout.metadata)
	return result & 1 != 0
}
fn swift_raw_equal(left u64, right u64, metadata u64, raw_table u64, equal_table u64) bool {
	return swift_raw_equal_checked(left,right,metadata,raw_table,equal_table) or { panic(err) }
}
fn swift_raw_equality_emit(code u64) {
	// Ordinary V call -> static Equatable witness; its Swift context is the
	// RawValue metadata, not either value's address. Preserve caller x20.
	for i, op in [u32(0xa9be7bfd),0xa90153f3,0x910003fd,0xaa0203f4,0xaa0403f0,
		0xd63f0200,0xa94153f3,0xa8c27bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
}
