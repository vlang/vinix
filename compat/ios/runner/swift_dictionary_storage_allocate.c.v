// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Swift class static method: capacity in x0, class self in x20, owned result
// in x0. The caller initializes occupancy and entries after this empty result.
fn swift_dictionary_storage_allocate_capacity(capacity i64, metadata u64) u64 {
	return swift_dictionary_storage_for_capacity_checked(capacity, metadata) or { panic(err) }
}

fn swift_dictionary_storage_allocate_symbol(symbol string) ?u64 {
	if symbol != '_$ss18_DictionaryStorageC8allocate8capacityAByxq_GSi_tFZ'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_dictionary_metadata_retired {
		return none
	}
	return swift_dictionary_metadata_arena() + 192
}
