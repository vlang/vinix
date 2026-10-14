// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift protocol methods borrow indirect operands and carry Self in x20.
// Bridges below adapt that ABI to ordinary V calls; all scalar operations are
// ownership-free. Optional<Element> has an eight-byte payload and one tag byte.
fn swift_dispatch_empty(output u64) { unsafe { *(&u64(output)) = 0 } }
fn swift_dispatch_contains(member u64, receiver u64) bool { return read64(member) & ~read64(receiver) == 0 }
fn swift_dispatch_union(other u64, output u64, receiver u64) { bits := read64(receiver) | read64(other); unsafe { *(&u64(output)) = bits } }
fn swift_dispatch_intersection(other u64, output u64, receiver u64) { bits := read64(receiver) & read64(other); unsafe { *(&u64(output)) = bits } }
fn swift_dispatch_difference(other u64, output u64, receiver u64) { bits := read64(receiver) ^ read64(other); unsafe { *(&u64(output)) = bits } }
fn swift_dispatch_subtracting(other u64, output u64, receiver u64) { bits := read64(receiver) & ~read64(other); unsafe { *(&u64(output)) = bits } }
fn swift_dispatch_insert(output u64, member u64, receiver u64) bool {
	bits := read64(member); previous := read64(receiver)
	unsafe { *(&u64(output)) = bits; *(&u64(receiver)) = previous | bits }
	return bits & ~previous != 0
}
fn swift_dispatch_remove(member u64, output u64, receiver u64) {
	bits := read64(member); previous := read64(receiver); removed := previous & bits
	unsafe { *(&u64(receiver)) = previous & ~bits; *(&u64(output)) = removed; *(&u8(output + 8)) = if removed == 0 { u8(1) } else { u8(0) } }
}
fn swift_dispatch_update(member u64, output u64, receiver u64) {
	bits := read64(member); previous := read64(receiver); replaced := previous & bits
	unsafe { *(&u64(receiver)) = previous | bits; *(&u64(output)) = replaced; *(&u8(output + 8)) = if replaced == 0 { u8(1) } else { u8(0) } }
}
fn swift_dispatch_form_union(other u64, receiver u64) { swift_dispatch_union(other, receiver, receiver) }
fn swift_dispatch_form_intersection(other u64, receiver u64) { swift_dispatch_intersection(other, receiver, receiver) }
fn swift_dispatch_form_difference(other u64, receiver u64) { swift_dispatch_difference(other, receiver, receiver) }
fn swift_dispatch_subtract(other u64, receiver u64) { swift_dispatch_subtracting(other, receiver, receiver) }
fn swift_dispatch_subset(other u64, receiver u64) bool { return read64(receiver) & ~read64(other) == 0 }
fn swift_dispatch_disjoint(other u64, receiver u64) bool { return read64(receiver) & read64(other) == 0 }
fn swift_dispatch_is_empty(receiver u64) bool { return read64(receiver) == 0 }

fn swift_dispatch_algebra_table_checked(metadata u64) !u64 {
	if ios_runtime == unsafe { nil } { return swift_dispatch_metadata_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	base := ios_runtime.swift_dispatch_flags_arena
	if ios_runtime.swift_dispatch_flags_retired || base == 0
		|| metadata != base + u64(C.getpagesize()) + 16 { return swift_dispatch_metadata_failure() }
	return base + u64(C.getpagesize()) + 320
}

fn swift_dispatch_word_span(address u64) bool { return address != 0 && address & 7 == 0 && address <= ~u64(0) - 7 }

// This profile accepts only registered native Array<Flags> storage. Validate
// identity before reading any foreign metadata, table, source or owner header.
// The caller transfers one Array reference, which is consumed exactly once.
fn swift_dispatch_array_fold_checked(owner u64, output u64) ! {
	if ios_runtime == unsafe { nil } || !swift_dispatch_word_span(output) { return swift_dispatch_metadata_failure() }
	C.ios_objc_initialize_lock()
	mut locked := true
	defer { if locked { C.ios_objc_initialize_unlock() } }
	base := ios_runtime.swift_dispatch_flags_arena
	if base == 0 || ios_runtime.swift_dispatch_flags_retired { return swift_dispatch_metadata_failure() }
	metadata := base + u64(C.getpagesize()) + 16
	mut bits := u64(0)
	if owner == 0 || owner != ios_runtime.swift_empty_array {
		storage := ios_runtime.swift_arrays[owner] or { return swift_dispatch_metadata_failure() }
		if storage.element != metadata || storage.stride != 8 || storage.destroy != 0 { return swift_dispatch_metadata_failure() }
		count := read64(owner + 16)
		if count > storage.capacity { return swift_dispatch_metadata_failure() }
		for i in u64(0)..count { bits |= read64(owner + storage.tail + i * 8) }
	}
	// Publish only after validation/folding. No callback runs under the lock.
	unsafe { *(&u64(output)) = bits }
	C.ios_objc_initialize_unlock(); locked = false
	swift_bridge_release(owner)
}
fn swift_dispatch_literal(owner u64, output u64) { swift_dispatch_array_fold_checked(owner, output) or { panic(err) } }

fn swift_dispatch_sequence_checked(source u64, metadata u64, sequence_metadata u64,
	sequence_table u64, table u64, output u64) ! {
	canonical := swift_dispatch_algebra_table_checked(metadata)!
	if table != canonical || !swift_dispatch_word_span(source) || !swift_dispatch_word_span(output) { return swift_dispatch_metadata_failure() }
	C.ios_objc_initialize_lock()
	array_metadata := ios_runtime.swift_array_metadata[metadata] or { C.ios_objc_initialize_unlock(); return swift_dispatch_metadata_failure() }
	sequence := ios_runtime.swift_array_sequence_metadata[metadata] or { C.ios_objc_initialize_unlock(); return swift_dispatch_metadata_failure() }
	valid := sequence_metadata == array_metadata && sequence_table == sequence + 256
	C.ios_objc_initialize_unlock()
	if !valid { return swift_dispatch_metadata_failure() }
	swift_dispatch_array_fold_checked(read64(source), output)!
}
fn swift_dispatch_sequence(source u64, sequence_metadata u64, sequence_table u64,
	metadata u64, table u64, output u64) {
	swift_dispatch_sequence_checked(source, metadata, sequence_metadata, sequence_table, table, output) or { panic(err) }
}

// Each bridge occupies 32 bytes: at most two argument moves, literal load,
// tail branch, and an aligned target pointer. Callee-saved x20/x21 survive V.
fn swift_dispatch_bridge(code u64, first u32, second u32, target u64) {
	write32(code, first); write32(code + 4, second)
	write32(code + 8, 0x58000090); write32(code + 12, 0xd61f0200)
	unsafe { *(&u64(code + 24)) = target }
}

fn swift_dispatch_algebra_build(base u64, data u64, swift_module u64, equal_protocol u64) {
	protocol := data + 576; literal_protocol := data + 800
	table := data + 320; literal_table := data + 512; equal_table := data + 544
	for i, proto in [protocol, literal_protocol, equal_protocol]! {
		record := data + 256 + u64(i * 16)
		pattern := [table, literal_table, equal_table]![i]
		swift_protocol_relative(record, proto); swift_protocol_relative(record + 4, data + 160)
		swift_protocol_relative(record + 8, pattern)
		unsafe { *(&u64(pattern)) = record }
	}
	write32(protocol, 0x30043); swift_protocol_relative(protocol + 4, swift_module)
	swift_protocol_relative(protocol + 8, data + 864); write32(protocol + 12, 2); write32(protocol + 16, 21)
	swift_protocol_relative(protocol + 20, data + 928)
	for i, proto in [equal_protocol, literal_protocol]! {
		requirement := protocol + 24 + u64(i * 12)
		write32(requirement, 0x80); swift_protocol_relative(requirement + 4, data + 960); swift_protocol_relative(requirement + 8, proto)
	}
	for i, flags in [u32(0),0,0xebff0007,0x3dee0002,0xcf270011,0x0c190011,0xc62c0011,0x04990011,
		0x9ca30011,0x1f350011,0x57f80011,0x776d0011,0xee870011,0xf6d40011,0x70ce0011,0x70510011,
		0x39ba0011,0x0c8c0011,0x2f130013,0xf2570002,0xeb470011]! { write32(protocol + 48 + u64(i * 8), flags) }
	write32(literal_protocol, 0x30043); swift_protocol_relative(literal_protocol + 4, swift_module)
	swift_protocol_relative(literal_protocol + 8, data + 880); write32(literal_protocol + 16, 2)
	swift_protocol_relative(literal_protocol + 20, data + 936)
	write32(literal_protocol + 24, 0xe6110007); write32(literal_protocol + 32, 0x2e6e0002)
	C.memcpy(voidptr(data + 864), c'SetAlgebra', 11); C.memcpy(voidptr(data + 880), c'ExpressibleByArrayLiteral', 26)
	C.memcpy(voidptr(data + 928), c'Element', 8); C.memcpy(voidptr(data + 936), c'ArrayLiteralElement', 20); C.memcpy(voidptr(data + 960), c'x', 2)
	unsafe {
		*(&u64(table + 8)) = equal_table; *(&u64(table + 16)) = literal_table; *(&u64(table + 24)) = data + 16
		*(&u64(equal_table + 8)) = u64(voidptr(swift_integer_equal_indirect))
		*(&u64(literal_table + 8)) = data + 16; *(&u64(literal_table + 16)) = base + 640
	}
	// Slot order follows the installed Swift SetAlgebra descriptor. Swift init
	// uses x8 output; generic init receives source, S metadata, S:Sequence,
	// Self metadata, Self:SetAlgebra in x0..x4; our bridge adds x5=x8.
	targets := [u64(unsafe { voidptr(swift_dispatch_empty) }),
		u64(unsafe { voidptr(swift_dispatch_contains) }), u64(unsafe { voidptr(swift_dispatch_union) }),
		u64(unsafe { voidptr(swift_dispatch_intersection) }), u64(unsafe { voidptr(swift_dispatch_difference) }),
		u64(unsafe { voidptr(swift_dispatch_insert) }), u64(unsafe { voidptr(swift_dispatch_remove) }),
		u64(unsafe { voidptr(swift_dispatch_update) }), u64(unsafe { voidptr(swift_dispatch_form_union) }),
		u64(unsafe { voidptr(swift_dispatch_form_intersection) }), u64(unsafe { voidptr(swift_dispatch_form_difference) }),
		u64(unsafe { voidptr(swift_dispatch_subtracting) }), u64(unsafe { voidptr(swift_dispatch_subset) }),
		u64(unsafe { voidptr(swift_dispatch_disjoint) }), u64(unsafe { voidptr(swift_dispatch_contains) }),
		u64(unsafe { voidptr(swift_dispatch_is_empty) }), u64(unsafe { voidptr(swift_dispatch_sequence) }),
		u64(unsafe { voidptr(swift_dispatch_subtract) })]!
	for i, target in targets {
		slot := i + 4; code := base + 64 + u64(i * 32)
		first := match slot {
			4 { u32(0xaa0803e0) } // x0=x8
			6,7,8,10,11,15 { u32(0xaa0803e1) } // x1=x8
			9 { u32(0xaa1403e2) } // x2=x20
			19 { u32(0xaa1403e0) } // x0=x20
			20 { u32(0xaa0803e5) } // x5=x8
			else { u32(0xaa1403e1) } // x1=x20
		}
		second := if slot in [6,7,8,10,11,15]! { u32(0xaa1403e2) } else { u32(0xd503201f) }
		swift_dispatch_bridge(code, first, second, target)
		unsafe { *(&u64(table + u64(slot * 8))) = code }
	}
	swift_dispatch_bridge(base + 640, 0xaa0803e1, 0xd503201f, u64(unsafe { voidptr(swift_dispatch_literal) }))
}
