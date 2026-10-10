// SPDX-License-Identifier: GPL-2.0-or-later
module main

// CVarArg's sole requirement returns an owned [Int]. Int's encoding is one
// machine word, preserving the signed value's complete bit pattern. Build a
// typed Array so ordinary Array copies and destruction own the result.
fn swift_integer_vararg(bits u64) u64 {
	value := swift_array_allocate(1, swift_integer_metadata())
	unsafe { *(&u64(value.bytes)) = bits }
	return value.owner
}

// Keep relative protocol/conformance pointers in Int's existing sealed
// arena. These are genuine concrete records, not existential metadata or a
// claim that runtime-wide protocol discovery and va_list building exist.
fn swift_vararg_emit(code u64, data u64) {
	table := data + 528
	conformance := data + 544
	protocol := data + 560
	unsafe {
		*(&u64(table)) = conformance
		*(&u64(table + 8)) = code + 288
	}
	swift_protocol_relative(conformance, protocol)
	swift_protocol_relative(conformance + 4, data + 160)
	swift_protocol_relative(conformance + 8, table)
	write32(protocol, 0x30043) // Unique Swift protocol, unconstrained by class.
	swift_protocol_relative(protocol + 4, data + 192) // Swift module.
	swift_protocol_relative(protocol + 8, data + 592)
	write32(protocol + 16, 1)
	write32(protocol + 24, 0x95c40013) // Instance getter, native signature discriminator.
	C.memcpy(unsafe { voidptr(data + 592) }, c'CVarArg', 8)
	// Witness Self is borrowed indirectly in x20; the public getter receives
	// the Int word in x0. Generic dispatch receives metadata/table in x0/x1
	// and forwards the same borrowed Self and context to the actual witness.
	swift_integer_witness_emit(code + 288, u64(unsafe { voidptr(swift_integer_vararg) }), true)
	write32(code + 320, 0xf9400430) // ldr x16,[x1,#8]
	write32(code + 324, 0xd61f0200) // br x16
}
