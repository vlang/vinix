// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift returns this resilient struct indirectly in x8. Only its actual fields
// are initialized: QoSClass's unspecified tag is 5, relativePriority is zero.
// The seven padding bytes stay untouched, as in the installed native getter.
fn swift_dispatch_qos_unspecified(output u64) {
	unsafe { *(&u8(output)) = 5; *(&u64(output + 8)) = 0 }
}

// POD witnesses move the full 16 bytes, including padding. Load both words
// before writing so self-assignment and overlapping byte transfers match the
// native single-vector load/store. No ownership or metadata access is needed.
fn swift_dispatch_qos_copy(destination u64, source u64, _metadata u64) u64 {
	first := read64(source); second := read64(source + 8)
	unsafe { *(&u64(destination)) = first; *(&u64(destination + 8)) = second }
	return destination
}

// The six enum tags occupy 0..5, leaving 250 extra inhabitants in the first
// byte. Larger optional populations use a tag byte after the 16-byte value.
// Payload arithmetic deliberately wraps at UInt32, matching native witnesses.
fn swift_dispatch_qos_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	if empty_cases >= 251 && unsafe { *(&u8(value + 16)) } != 0 { return read32(value) + u32(251) }
	which := unsafe { *(&u8(value)) }
	return if which < 6 { u32(0) } else { u32(which - 5) }
}
fn swift_dispatch_qos_enum_store(value u64, tag u32, empty_cases u32, _metadata u64) {
	if tag <= 250 {
		if empty_cases >= 251 { unsafe { *(&u8(value + 16)) = 0 } }
		if tag != 0 { unsafe { *(&u8(value)) = u8(tag + 5) } }
	} else {
		unsafe { *(&u64(value)) = u64(tag - 251); *(&u64(value + 8)) = 0 }
		if empty_cases >= 251 { unsafe { *(&u8(value + 16)) = 1 } }
	}
}

fn swift_dispatch_qos_build(base u64, data u64) {
	metadata := data + 1040; witness := data + 1088; descriptor := data + 1184
	accessor := base + 736
	swift_dispatch_bridge(base + 704, 0xaa0803e0, 0xd503201f, u64(unsafe { voidptr(swift_dispatch_qos_unspecified) }))
	write32(accessor, 0x58000080); write32(accessor + 4, 0xd2800001); write32(accessor + 8, 0xd65f03c0)
	unsafe {
		*(&u64(accessor + 16)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = descriptor
	}
	write32(metadata + 16, 0); write32(metadata + 20, 8) // Packed u32 field offset vector.
	for i, function in [u64(unsafe { voidptr(swift_dispatch_qos_copy) }),
		u64(unsafe { voidptr(swift_integer_destroy) }), u64(unsafe { voidptr(swift_dispatch_qos_copy) }),
		u64(unsafe { voidptr(swift_dispatch_qos_copy) }), u64(unsafe { voidptr(swift_dispatch_qos_copy) }),
		u64(unsafe { voidptr(swift_dispatch_qos_copy) }), u64(unsafe { voidptr(swift_dispatch_qos_enum_get) }),
		u64(unsafe { voidptr(swift_dispatch_qos_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = function } }
	unsafe { *(&u64(witness + 64)) = 16; *(&u64(witness + 72)) = 16 }
	write32(witness + 80, 0x02000007); write32(witness + 84, 250)
	// Private unique nongeneric descriptor. Native initialization extensions,
	// reflection and QoSClass's separate metadata/conformances are unsupported.
	write32(descriptor, 0x51); swift_protocol_relative(descriptor + 4, data + 192)
	swift_protocol_relative(descriptor + 8, data + 1216); swift_protocol_relative(descriptor + 12, accessor)
	write32(descriptor + 20, 2); write32(descriptor + 24, 2)
	C.memcpy(voidptr(data + 1216), c'DispatchQoS', 12)
}
