// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Decoder.container<K: CodingKey>(keyedBy:) forwards to the caller's Decoder
// witness at byte 24 of x4. Keep the metatype/generic arguments in x0..x4,
// indirect result x8, borrowed Self x20 and incoming/returned error x21.
// The witness owns result initialization and throwing; no value, metadata,
// descriptor, result or reference count is read by this dispatch entry.
fn swift_decoder_keyed_dispatch_emit(code u64) {
	write32(code, 0xf9400c90) // ldr x16,[x4,#24]
	write32(code + 4, 0xd61f0200) // br x16
}

fn swift_decoder_keyed_dispatch_symbol(symbol string) ?u64 {
	if symbol != '_$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(1792)
}
