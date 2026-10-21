// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftEnumCaseMultiFailure {}
fn (_ &SwiftEnumCaseMultiFailure) msg() string { return 'iOS: unsupported Swift multi-payload enum case layout or lifetime' }
fn (_ &SwiftEnumCaseMultiFailure) code() int { return 1 }
__global swift_enum_case_multi_failure_value = SwiftEnumCaseMultiFailure{}
fn swift_enum_case_multi_failure() IError { return unsafe { &swift_enum_case_multi_failure_value } }

// Unaligned little-endian discriminator bytes, truncated to UInt32. No value
// witness, generic argument, referenced payload or ownership operation runs.
fn swift_enum_case_multi_read(address u64, count u64) u32 {
	mut value := u32(0)
	for i in u64(0)..if count < 4 { count } else { u64(4) } {
		value |= u32(unsafe { *(&u8(address + i)) }) << u32(i * 8)
	}
	return value
}
struct SwiftEnumMultiLayout { payload u64 width u64 size u64 payloads u32 }
// Caller holds the runtime lock and has checked its lifetime. Both tag entries
// borrow the same initialized metadata layout; neither runs value witnesses.
fn swift_enum_multi_layout(metadata u64) !SwiftEnumMultiLayout {
	if metadata < 8 || metadata & 7 != 0 || metadata > ~u64(0) - 16 { return swift_enum_case_multi_failure() }
	if read64(metadata) != 0x201 { return swift_enum_case_multi_failure() }
	descriptor := read64(metadata + 8)
	if descriptor == 0 || descriptor & 3 != 0 || descriptor > ~u64(0) - 24 { return swift_enum_case_multi_failure() }
	// Version-zero enum descriptors retain this common header even for generic
	// contexts. The empty-case count and trailing constraints are not needed.
	if read32(descriptor) & 0xff1f != 18 { return swift_enum_case_multi_failure() }
	cases := read32(descriptor + 20)
	payloads := cases & 0xffffff
	offset := u64(cases >> 24) * 8
	if payloads < 2 || offset < 16 || metadata > ~u64(0) - offset - 8 { return swift_enum_case_multi_failure() }
	payload := read64(metadata + offset)
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 84 { return swift_enum_case_multi_failure() }
	size := read64(witness + 64); stride := read64(witness + 72); flags := read32(witness + 80)
	align := u64(flags & 255) + 1
	if payload > 1048576 || size < payload || size - payload > 4 || stride == 0 || stride < size
		|| align & (align - 1) != 0 || stride & (align - 1) != 0
		|| flags & 0x600000 != 0x200000 { return swift_enum_case_multi_failure() }
	return SwiftEnumMultiLayout{payload, size - payload, size, payloads}
}
fn swift_enum_case_multi_checked(value u64, metadata u64) !u32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_enum_case_multi_failure() }
	layout := swift_enum_multi_layout(metadata)!
	payload := layout.payload; width := layout.width; payloads := layout.payloads
	// A zero-width tag selects payload case zero without reading a value.
	if width == 0 { return u32(0) }
	if value == 0 || value > ~u64(0) - layout.size { return swift_enum_case_multi_failure() }
	tag := swift_enum_case_multi_read(value + payload, width)
	if tag < payloads { return tag }
	leading := swift_enum_case_multi_read(value, payload)
	if payload >= 4 { return payloads + leading }
	return (leading | ((tag - payloads) << u32(payload * 8))) + payloads
}
// Darwin's ordinary C entry returns a UInt32 case index in w0.
fn swift_enum_case_multi(value u64, metadata u64) u32 {
	return swift_enum_case_multi_checked(value, metadata) or { panic(err) }
}
