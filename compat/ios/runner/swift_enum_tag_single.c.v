// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftEnumTagSingleFailure {}
fn (_ &SwiftEnumTagSingleFailure) msg() string { return 'iOS: unsupported Swift single-payload enum tag layout, callback or lifetime' }
fn (_ &SwiftEnumTagSingleFailure) code() int { return 1 }
__global swift_enum_tag_single_failure_value = SwiftEnumTagSingleFailure{}
fn swift_enum_tag_single_failure() IError { return unsafe { &swift_enum_tag_single_failure_value } }

struct SwiftEnumTagSingleLayout {
	size u64
	extra u32
	width u32
}
fn swift_enum_tag_single_layout(metadata u64, cases u32) !SwiftEnumTagSingleLayout {
	if metadata < 8 || metadata & 7 != 0 || metadata > ~u64(0) - 8 { return swift_enum_tag_single_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_enum_tag_single_failure() }
	// Only the borrowed VWT prefix and published layout are required. Metadata
	// kind, descriptor, generic arguments and value-witness functions are opaque.
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 { return swift_enum_tag_single_failure() }
	size := read64(witness + 64); stride := read64(witness + 72); flags := read32(witness + 80)
	align := u64(flags & 255) + 1
	if size > 1048576 || stride == 0 || stride < size || align & (align - 1) != 0
		|| stride & (align - 1) != 0 || flags & 0x400000 != 0 { return swift_enum_tag_single_failure() }
	extra := read32(witness + 84)
	return SwiftEnumTagSingleLayout{size, extra, swift_optional_extra_width(size, extra, cases)}
}
fn swift_enum_tag_single_checked(value u64, cases u32, metadata u64, callback u64) !u32 {
	layout := swift_enum_tag_single_layout(metadata, cases)!
	if layout.width != 0 {
		if value == 0 || value > ~u64(0) - layout.size - u64(layout.width) { return swift_enum_tag_single_failure() }
		tag := swift_enum_case_multi_read(value + layout.size, layout.width)
		if tag != 0 {
			high := if layout.size < 4 { (tag - u32(1)) << u32(layout.size * 8) } else { u32(0) }
			return (high | swift_enum_case_multi_read(value, layout.size)) + layout.extra + u32(1)
		}
	}
	if layout.extra == 0 { return u32(0) }
	if callback == 0 || callback & 3 != 0 || callback > ~u64(0) - 4 { return swift_enum_tag_single_failure() }
	// Scalar SwiftCC arguments use x0/w1/x2 and a UInt32 result in w0.
	// The layout helper has released the lock before calling borrowed app code.
	get := unsafe { SwiftSequenceTag(voidptr(callback)) }
	return get(value, layout.extra, metadata)
}
fn swift_enum_tag_single(value u64, cases u32, metadata u64, callback u64) u32 {
	return swift_enum_tag_single_checked(value, cases, metadata, callback) or { panic(err) }
}
