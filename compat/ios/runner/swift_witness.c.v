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
	if ios_runtime != unsafe { nil } && ios_runtime.swift_cocoa_error_retired_arena != 0 {
		data := ios_runtime.swift_cocoa_error_retired_arena + u64(C.getpagesize())
		if conformance in [data + 608, data + 672]! { return error('iOS: CocoaError conformance outside runtime lifetime') }
	}
	if ios_runtime != unsafe { nil } && ios_runtime.swift_cocoa_error_arena != 0 {
		data := ios_runtime.swift_cocoa_error_arena + u64(C.getpagesize())
		if conformance == data + 608 { return swift_cocoa_error_table_checked(metadata) }
	}
	if ios_runtime != unsafe { nil } && ios_runtime.swift_nsobject_hashable_arena != 0 {
		data := ios_runtime.swift_nsobject_hashable_arena + u64(C.getpagesize())
		if conformance == data || conformance == data + 32 { return swift_nsobject_table_checked(metadata,conformance == data + 32) }
	}
	if ios_runtime != unsafe { nil } && ios_runtime.swift_dispatch_flags_arena != 0 {
		data := ios_runtime.swift_dispatch_flags_arena + u64(C.getpagesize())
		if conformance in [data + 256, data + 272, data + 288]! {
			swift_dispatch_algebra_table_checked(metadata)!
			return if conformance == data + 256 { data + 320 } else if conformance == data + 272 { data + 512 } else { data + 544 }
		}
	}
	if ios_runtime != unsafe { nil } && ios_runtime.swift_set_arena != 0 {
		data := ios_runtime.swift_set_arena + u64(C.getpagesize())
		if conformance == data + 32 { return swift_set_table_checked(metadata, false) }
		if conformance == data + 64 { return swift_set_table_checked(metadata, true) }
	}
	if ios_runtime != unsafe { nil } && ios_runtime.swift_collection_arena != 0 {
		data := ios_runtime.swift_collection_arena + u64(C.getpagesize())
		if conformance in [data + 32, data + 64, data + 96]! {
			kind := swift_collection_kind_checked(metadata, false)!
			if conformance != data + 32 + u64(kind * 32) { return swift_sequence_failure() }
			return swift_collection_table_checked(metadata)
		}
		if conformance in [data + 640, data + 672]! {
			kind := swift_collection_kind_checked(metadata, false)!
			if kind == 0 || conformance != data + 608 + u64(kind * 32) { return swift_sequence_failure() }
			return swift_collection_sequence_checked(metadata)
		}
		if conformance in [data + 704, data + 736]! {
			kind := swift_collection_kind_checked(metadata, true)!
			if conformance != data + 672 + u64(kind * 32) { return swift_sequence_failure() }
			return swift_collection_iterator_checked(metadata)
		}
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
