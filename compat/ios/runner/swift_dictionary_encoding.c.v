// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Serialization needs Dictionary iteration and keyed/unkeyed Encoder
// containers. Keep that call explicit while supporting conformance identity
// and conditional witness specialization; never report a successful encode.
fn swift_dictionary_encoding_unavailable() {
	panic('iOS: Swift Dictionary encoding is not implemented')
}

fn swift_dictionary_encoding_emit(code u64, data u64, protocol u64) {
	swift_dictionary_codable_emit(code, data, protocol, 320, 64, 128,
		u64(unsafe { voidptr(swift_dictionary_encoding_unavailable) }))
}

fn swift_dictionary_encoding_table_checked(metadata u64, arguments u64) !u64 {
	if ios_runtime == unsafe { nil } { return swift_dictionary_metadata_failure() }
	return swift_dictionary_codable_table_checked(metadata, arguments, 384,
		mut ios_runtime.swift_dictionary_encoding)
}

// After users drain, retire witnesses before their borrowed metadata and
// descriptor. Remember the descriptor address to reject stale lookups safely.
fn swift_dictionary_encoding_stop() {
	swift_dictionary_codable_stop(mut ios_runtime.swift_dictionary_encoding)
}

fn swift_dictionary_encoding_symbol(symbol string) ?u64 {
	if symbol != '_$sSDyxq_GSEsSERzSER_rlMc' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_dictionary_metadata_retired || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_dictionary_metadata_arena() + u64(C.getpagesize()) + 320
}
