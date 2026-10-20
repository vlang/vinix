// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift's helper ignores original and move: NativeDictionary's caller owns
// rehashing, copying/moving initialized entries and clearing a moved source.
// In particular, neither argument grants a source read or an ARC operation.
fn swift_dictionary_storage_resize_checked(_original u64, capacity i64, _move u64, metadata u64) !u64 {
	return swift_dictionary_storage_for_capacity_checked(capacity, metadata)
}

// Both native allocate(capacity:) and resize use this fresh allocation path.
fn swift_dictionary_storage_for_capacity_checked(capacity i64, metadata u64) !u64 {
	// This matches HashTable.scale(forCapacity:) within the supported scale14
	// bound, using integer arithmetic instead of floating-point rounding. Swift
	// normalizes even negative capacities to one and always leaves a hole.
	if capacity > 12288 { return swift_dictionary_storage_failure() }
	requested := if capacity < 1 { u64(1) } else { u64(capacity) }
	mut scale := u8(1)
	mut available := u64(1)
	for available < requested {
		scale++
		buckets := u64(1) << scale
		available = buckets - buckets / 4
	}
	return swift_dictionary_storage_allocate_checked(metadata, scale, 0, 0, true)
}

fn swift_dictionary_storage_resize(original u64, capacity i64, move u64, metadata u64) u64 {
	return swift_dictionary_storage_resize_checked(original, capacity, move, metadata) or { panic(err) }
}

fn swift_dictionary_storage_resize_symbol(symbol string) ?u64 {
	if symbol != '_$ss18_DictionaryStorageC6resize8original8capacity4moveAByxq_Gs05__RawaB0C_SiSbtFZ'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_dictionary_metadata_retired {
		return none
	}
	return swift_dictionary_metadata_arena() + 160
}
