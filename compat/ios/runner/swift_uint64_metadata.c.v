// SPDX-License-Identifier: GPL-2.0-or-later
module main

// UInt64 and Int have distinct nominal identities and the same native POD
// value-witness table. Reuse the sealed integer arena, Swift module and eight
// existing word witnesses; no unsigned arithmetic/formatting conformance is
// implied by exporting complete UInt64 metadata.
fn swift_uint64_metadata_emit(base u64, data u64) {
	metadata := data + 904
	descriptor := data + 936
	accessor := base + 416
	unsafe {
		*(&u64(metadata - 8)) = data + 64
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	// The one stored word's field offset at metadata word two remains zero.
	write32(descriptor, 0x51)
	swift_protocol_relative(descriptor + 4, data + 192)
	swift_protocol_relative(descriptor + 8, data + 976)
	swift_protocol_relative(descriptor + 12, accessor)
	write32(descriptor + 20, 1)
	write32(descriptor + 24, 2)
	C.memcpy(voidptr(data + 976), c'UInt64', 7)
	// Every request returns the same Complete MetadataResponse in x0/x1.
	write32(accessor, 0x58000080)
	write32(accessor + 4, 0xd2800001)
	write32(accessor + 8, 0xd65f03c0)
	write32(accessor + 12, 0xd503201f)
	unsafe { *(&u64(accessor + 16)) = metadata }
}

fn swift_uint64_metadata_symbol(symbol string) ?u64 {
	offset := match symbol {
		'_$ss6UInt64VN' { u64(904) }
		'_$ss6UInt64VMn' { u64(936) }
		'_$ss6UInt64VMa' { u64(0) }
		else { return none }
	}
	$if !arm64 { return none }
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_integer_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		swift_integer_metadata()
	}
	// Existing identity remains available until integer users/callbacks drain.
	base := ios_runtime.swift_integer_arena
	return if offset == 0 { base + 416 } else { base + u64(C.getpagesize()) + offset }
}
