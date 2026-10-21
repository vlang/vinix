// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftStructMetadataFailure {}
fn (_ &SwiftStructMetadataFailure) msg() string { return 'iOS: unsupported Swift struct metadata layout, witnesses or lifetime' }
fn (_ &SwiftStructMetadataFailure) code() int { return 1 }
__global swift_struct_metadata_failure_value = SwiftStructMetadataFailure{}
fn swift_struct_metadata_failure() IError { return unsafe { &swift_struct_metadata_failure_value } }

fn swift_struct_pod_copy(destination u64, source u64, metadata u64) u64 {
	C.memmove(voidptr(destination), voidptr(source), usize(read64(read64(metadata - 8) + 64)))
	return destination
}

// Common inline scalar layouts have no extra inhabitants. Other layouts keep
// the compiler's enum witnesses, including its choice of extra-inhabitant field.
fn swift_struct_pod_tag(value u64, cases u32, metadata u64) u32 {
	size := read64(read64(metadata - 8) + 64)
	width := swift_optional_extra_width(size, 0, cases)
	if width == 0 { return 0 }
	tag := swift_enum_case_multi_read(value + size, width)
	if tag == 0 { return 0 }
	high := if size < 4 { (tag - u32(1)) << u32(size * 8) } else { u32(0) }
	return (high | swift_enum_case_multi_read(value, size)) + u32(1)
}

fn swift_struct_tag_write(value u64, width u64, bits u32) {
	for i in u64(0) .. if width < 4 { width } else { u64(4) } {
		unsafe { *(&u8(value + i)) = u8(bits >> u32(i * 8)) }
	}
}

fn swift_struct_pod_store(value u64, tag u32, cases u32, metadata u64) {
	size := read64(read64(metadata - 8) + 64)
	width := swift_optional_extra_width(size, 0, cases)
	mut high := u32(0)
	if tag != 0 {
		C.memset(voidptr(value), 0, usize(size))
		swift_struct_tag_write(value, size, tag - u32(1))
		high = if size < 4 { ((tag - u32(1)) >> u32(size * 8)) + u32(1) } else { u32(1) }
	}
	swift_struct_tag_write(value + size, u64(width), high)
}

// C ABI: five scalar arguments, no result. All storage is borrowed from the
// image and must remain accessible through runtime drain. Only Swift 5's
// mutable-table algorithm is supported; never clone or own application tables.
fn swift_struct_initialize_checked(metadata u64, algorithm u64, count u64, types u64, offsets u64) ! {
	if algorithm != 0x100 || count > 64 || metadata < 8 || metadata & 7 != 0
		|| metadata > ~u64(0) - 16 || (count != 0 && (types == 0 || types & 7 != 0
		|| types > ~u64(0) - count * 8 || offsets == 0 || offsets & 3 != 0
		|| offsets > ~u64(0) - count * 4)) { return swift_struct_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_generic_metadata_retired || ios_runtime.swift_generic_value_retired {
		return swift_struct_metadata_failure()
	}
	if read64(metadata) != 0x200 { return swift_struct_metadata_failure() }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 { return swift_struct_metadata_failure() }
	mut positions := [64]u32{}
	mut size := u64(0)
	mut mask := u64(0)
	mut extra := u32(0)
	mut traits := u32(0)
	for i in u64(0) .. count {
		layout := read64(types + i * 8)
		if layout == 0 || layout & 7 != 0 || layout > ~u64(0) - 24 { return swift_struct_metadata_failure() }
		field_size := read64(layout)
		stride := read64(layout + 8)
		flags := read32(layout + 16)
		field_mask := u64(flags & 255)
		field_extra := read32(layout + 20)
		if field_size > 1048576 || stride == 0 || stride < field_size || stride & field_mask != 0
			|| (field_mask + 1) & field_mask != 0 || flags & ~u32(0x023b00ff) != 0
			|| field_extra > 0x7fffffff { return swift_struct_metadata_failure() }
		size = (size + field_mask) & ~field_mask
		positions[int(i)] = u32(size)
		size += field_size
		if size > 1048576 { return swift_struct_metadata_failure() }
		if field_mask > mask { mask = field_mask }
		if field_extra > extra { extra = field_extra }
		traits |= flags & 0x110000
	}
	inline_storage := size <= 24 && mask <= 7 && traits & 0x100000 == 0
	pod := traits & 0x10000 == 0
	// Indirect POD buffer copies need a separate allocation/ownership path.
	if pod && !inline_storage { return swift_struct_metadata_failure() }
	common := pod && extra == 0 && size in [u64(1), 2, 4, 8]! && mask == size - 1
	// Every callback that survives initialization must be a callable image address.
	for slot in 0 .. 8 {
		if (pod && (slot < 6 || common)) || (!pod && traits & 0x100000 == 0 && slot == 4) { continue }
		callback := read64(witness + u64(slot * 8))
		if callback == 0 || callback & 3 != 0 || callback > ~u64(0) - 4 { return swift_struct_metadata_failure() }
	}
	// Validate everything before writing. Offsets are UInt32, and already-correct
	// vectors may reside in read-only image pages (Swift's assignUnlessEqual).
	for i in u64(0) .. count {
		if read32(offsets + i * 4) != positions[int(i)] { write32(offsets + i * 4, positions[int(i)]) }
	}
	copy := u64(unsafe { voidptr(swift_struct_pod_copy) })
	if pod {
		for slot in 0 .. 6 { unsafe { *(&u64(witness + u64(slot * 8))) = if slot == 1 { u64(voidptr(swift_integer_destroy)) } else { copy } } }
		if common {
			unsafe { *(&u64(witness + 48)) = u64(voidptr(swift_struct_pod_tag)); *(&u64(witness + 56)) = u64(voidptr(swift_struct_pod_store)) }
		}
	} else if traits & 0x100000 == 0 { unsafe { *(&u64(witness + 32)) = copy } }
	stride := if size == 0 { u64(1) } else { (size + mask) & ~mask }
	unsafe { *(&u64(witness + 64)) = size; *(&u64(witness + 72)) = stride }
	flags := u32(mask) | traits | if inline_storage { u32(0) } else { u32(0x20000) }
	C.ios_store_pointer(unsafe { &u64(witness + 80) }, u64(flags) | (u64(extra) << 32))
}

fn swift_struct_initialize(metadata u64, algorithm u64, count u64, types u64, offsets u64) {
	swift_struct_initialize_checked(metadata, algorithm, count, types, offsets) or { panic(err) }
}
