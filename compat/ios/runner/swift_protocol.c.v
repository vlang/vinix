// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_string_description(value u64) SwiftStringWords {
	words := unsafe { *(&SwiftStringWords(value)) }
	swift_bridge_retain(words.second)
	return words
}

fn swift_protocol_relative(field u64, destination u64) {
	offset := i64(destination) - i64(field)
	assert offset >= -2147483648 && offset <= 2147483647
	write32(field, u32(i32(offset)))
}

// Build the two concrete String conformances in its existing metadata arena.
// Each protocol has one instance requirement and no associated types or
// generic signature requirements. These records describe the supplied tables;
// runtime-wide conformance discovery/reflection remains unsupported.
fn swift_string_protocols_emit(code u64, data u64) {
	for i, name in ['TextOutputStreamable', 'CustomStringConvertible']! {
		table := data + 256 + u64(i * 16)
		conformance := data + 288 + u64(i * 16)
		protocol := data + 320 + u64(i * 32)
		text := data + 384 + u64(i * 32)
		entry := code + 64 + u64(i * 64)
		unsafe { *(&u64(table)) = conformance; *(&u64(table + 8)) = entry }
		swift_protocol_relative(conformance, protocol)
		swift_protocol_relative(conformance + 4, data + 160) // Direct nominal type descriptor.
		swift_protocol_relative(conformance + 8, table)
		// Conformance flags are zero: concrete, unconditional, no resilient witnesses.
		write32(protocol, 0x30043) // Unique Swift protocol, unconstrained by class.
		swift_protocol_relative(protocol + 4, data + 192) // Swift module.
		swift_protocol_relative(protocol + 8, text)
		write32(protocol + 16, 1) // NumRequirements, following the 24-byte header.
		write32(protocol + 24, if i == 0 { u32(0x11) } else { u32(0x8be30013) })
		C.memcpy(unsafe { voidptr(text) }, name.str, usize(name.len + 1))
	}
	// TextOutputStreamable.write: x0 = target inout, x1 = Target metadata,
	// x2 = Target TextOutputStream table, x20 = indirect borrowed String self.
	// The target's write requirement is word 3 (after descriptor, lock, unlock).
	// Call it with String in x0/x1, Target metadata/table in x2/x3 and target
	// self in x20. Preserve the caller's Swift context register across the call.
	for i, instruction in [u32(0xa9be7bfd), // stp x29,x30,[sp,#-32]!
		0xa90153f3, // stp x19,x20,[sp,#16]
		0xaa0003e9, // mov x9,x0
		0xaa0103ea, // mov x10,x1
		0xf9400c50, // ldr x16,[x2,#24]
		0xaa0203e3, // mov x3,x2
		0xa9400680, // ldp x0,x1,[x20]
		0xaa0903f4, // mov x20,x9
		0xaa0a03e2, // mov x2,x10
		0xd63f0200, // blr x16
		0xa94153f3, // ldp x19,x20,[sp,#16]
		0xa8c27bfd, // ldp x29,x30,[sp],#32
		0xd65f03c0]! { write32(code + 64 + u64(i * 4), instruction) }
	// CustomStringConvertible.description: indirect self in x20, owned String
	// result in x0/x1. Tail-call an ordinary V body after adapting self to x0.
	write32(code + 128, 0xaa1403e0) // mov x0,x20
	write32(code + 132, 0x58000070) // ldr x16,literal at +144
	write32(code + 136, 0xd61f0200) // br x16
	write32(code + 140, 0xd503201f)
	unsafe { *(&u64(code + 144)) = u64(voidptr(swift_string_description)) }
}

fn swift_string_protocol_symbol(symbol string) ?u64 {
	if symbol == '_$ss23CustomStringConvertibleMp' && (ios_runtime == unsafe { nil }
		|| ios_runtime.swift_integer_description_retired || ios_runtime.swift_concurrency_retired) {
		return none
	}
	offset := match symbol {
		'_$sSSs20TextOutputStreamablesWP' { 256 }
		'_$sSSs23CustomStringConvertiblesWP' { 272 }
		'_$sSSs20TextOutputStreamablesMc' { 288 }
		'_$sSSs23CustomStringConvertiblesMc' { 304 }
		'_$ss20TextOutputStreamableMp' { 320 }
		'_$ss23CustomStringConvertibleMp' { 352 }
		else { return none }
	}
	return swift_string_metadata() - 16 + u64(offset)
}
