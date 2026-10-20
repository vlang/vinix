// SPDX-License-Identifier: GPL-2.0-or-later
module main

// KeyedDecodingContainer<K> borrows its one-word box reference through x20.
// Forward to _KeyedDecodingContainerBase.decode(String.self, forKey:), slot
// 128. Container metadata supplies K and K:CodingKey at words 2 and 3.
// The override receives the borrowed key in x0, K in x1/x8, its conformance
// in x2 and the box in x20. It owns the String result in x0/x1 or the exact
// thrown error in x21. Restore the caller's x20 without touching that error.
// As for other Swift dispatch entries, the caller owns readable value,
// metadata and vtable spans. No box layout, key bytes, ARC or JSON is needed.
fn swift_keyed_string_decoding_emit(code u64) {
	for i, op in [u32(0xa9be7bfd), // stp x29,x30,[sp,#-32]!
		0xf9000bf4, // str x20,[sp,#16]
		0x910003fd, // mov x29,sp
		0xf9400294, // ldr x20,[x20]
		0xf9400290, // ldr x16,[x20]
		0xf9404209, // ldr x9,[x16,#128]
		0xa9410828, // ldp x8,x2,[x1,#16]
		0xaa0803e1, // mov x1,x8
		0xd63f0120, // blr x9
		0xf9400bf4, // ldr x20,[sp,#16]
		0xa8c27bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn swift_keyed_string_decoding_symbol(symbol string) ?u64 {
	if symbol != '_$ss22KeyedDecodingContainerV6decode_6forKeyS2Sm_xtKF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(1440)
}
