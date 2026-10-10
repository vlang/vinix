// SPDX-License-Identifier: GPL-2.0-or-later
module main

// ARM64 Optional<OpaquePointer> uses null for nil and otherwise preserves the
// pointer word. Int.init(bitPattern:) returns those bits as signed Swift.Int;
// it does not dereference, validate, retain or truncate the pointer. Measured
// from the installed Swift library, whose initializer is a single RET.
fn swift_integer_pointer_bits(bits u64) i64 { return i64(bits) }

fn swift_integer_symbol(symbol string) ?u64 {
	return match symbol {
		'_$sSi10bitPatternSis13OpaquePointerVSg_tcfC' { u64(unsafe { voidptr(swift_integer_pointer_bits) }) }
		else { none }
	}
}
