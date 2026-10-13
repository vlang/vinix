// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Concrete, unique, unconditional tables are borrowed from the caller's image
// or our existing metadata arenas. This is the ordinary C runtime entry, not a
// Swift context call. Metadata and instantiation arguments are unused on this
// path. Resilient/generic tables must be instantiated, never returned as-is.
fn swift_witness_table_checked(conformance u64, metadata u64, _arguments u64) !u64 {
	if conformance == 0 || conformance & 3 != 0 || conformance > ~u64(0) - 15 {
		return error('iOS: invalid Swift conformance descriptor')
	}
	if ios_runtime != unsafe { nil } && ios_runtime.swift_array_sequence_arena != 0
		&& conformance == ios_runtime.swift_array_sequence_arena + u64(C.getpagesize()) + 128 {
		return swift_array_sequence_table_checked(metadata)
	}
	if ios_runtime != unsafe { nil } && ios_runtime.swift_array_sequence_arena != 0
		&& conformance == ios_runtime.swift_array_sequence_arena + u64(C.getpagesize()) + 192 {
		return swift_array_iterator_table_checked(metadata)
	}
	flags := read32(conformance + 12)
	// Only the four type-reference kinds and retroactive flag are supported.
	// Reject non-unique foreign conformances, conditional requirements, packs,
	// resilient witnesses, generic instantiation and unknown descriptor flags.
	if flags & ~u32(0x78) != 0 || (flags >> 3) & 7 > 3 {
		return error('iOS: Swift generic/resilient/foreign witness lookup is not implemented')
	}
	field := conformance + 8
	delta := i64(i32(read32(field)))
	if delta == 0 { return 0 } // Nullable relative pattern.
	if (delta > 0 && field > ~u64(0) - u64(delta)) || (delta < 0 && field < u64(-delta)) {
		return error('iOS: invalid Swift relative witness table')
	}
	table := if delta > 0 { field + u64(delta) } else { field - u64(-delta) }
	if table == 0 || table & 7 != 0 { return error('iOS: invalid Swift witness table alignment') }
	return table
}

fn swift_witness_table(conformance u64, metadata u64, arguments u64) u64 {
	return swift_witness_table_checked(conformance, metadata, arguments) or { panic(err) }
}

fn swift_witness_symbol(symbol string) ?u64 {
	if symbol == '_swift_getWitnessTable' { return u64(unsafe { voidptr(swift_witness_table) }) }
	return none
}
