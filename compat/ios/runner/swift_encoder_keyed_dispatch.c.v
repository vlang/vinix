// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Encoder.container<K: CodingKey>(keyedBy:) uses the same unsigned ARM64
// dispatch as Decoder's keyed container: witness x4+24, arguments x0..x4,
// indirect result x8 and borrowed Self x20. Reuse that sealed entry; the
// supplied nonthrowing witness initializes the result and preserves x21.
// Neither entry reads values/type metadata or performs ownership work.
fn swift_encoder_keyed_dispatch_symbol(symbol string) ?u64 {
	if symbol != '_$ss7EncoderP9container7keyedBys22KeyedEncodingContainerVyqd__Gqd__m_ts9CodingKeyRd__lFTj'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(1792)
}
