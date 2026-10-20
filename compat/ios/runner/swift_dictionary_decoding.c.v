// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Decoding needs owned Decoder/container handling and Dictionary construction.
// Until implemented, fail before consuming the Decoder or writing a result.
fn swift_dictionary_decoding_unavailable() {
	panic('iOS: Swift Dictionary decoding is not implemented')
}

fn swift_dictionary_decoding_emit(code u64, data u64, protocol u64) {
	swift_dictionary_codable_emit(code, data, protocol, 448, 96, 512,
		u64(unsafe { voidptr(swift_dictionary_decoding_unavailable) }))
}

fn swift_dictionary_decoding_table_checked(metadata u64, arguments u64) !u64 {
	if ios_runtime == unsafe { nil } { return swift_dictionary_metadata_failure() }
	return swift_dictionary_codable_table_checked(metadata, arguments, 512,
		mut ios_runtime.swift_dictionary_decoding)
}

fn swift_dictionary_decoding_stop() {
	swift_dictionary_codable_stop(mut ios_runtime.swift_dictionary_decoding)
}

fn swift_dictionary_decoding_symbol(symbol string) ?u64 {
	if symbol != '_$sSDyxq_GSesSeRzSeR_rlMc' || ios_runtime == unsafe { nil }
		|| ios_runtime.swift_dictionary_metadata_retired || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_dictionary_metadata_arena() + u64(C.getpagesize()) + 448
}
