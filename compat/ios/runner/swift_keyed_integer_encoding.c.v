// SPDX-License-Identifier: GPL-2.0-or-later
module main

// KeyedEncodingContainer<K>.encode(Int, forKey:) borrows its one-word
// container in x20 and key in x1, preserving the full-width Int in x0.
// Container metadata in x2 supplies K in x2/x8 and K:CodingKey in x3.
// Call the box's class slot 136 and restore the caller's x20 on both paths.
// The override returns Void or its exact owned error in x21. Callers own
// readable container/header/metadata/slot spans. No key, box payload or
// refcount is inspected, retained or allocated by this forwarding entry.
fn swift_keyed_integer_encoding_emit(code u64) {
	for i, op in [u32(0xa9be7bfd), // stp x29,x30,[sp,#-32]!
		0xf9000bf4, // str x20,[sp,#16]
		0x910003fd, // mov x29,sp
		0xf9400294, // ldr x20,[x20]
		0xf9400290, // ldr x16,[x20]
		0xf9404609, // ldr x9,[x16,#136]
		0xa9410c48, // ldp x8,x3,[x2,#16]
		0xaa0803e2, // mov x2,x8
		0xd63f0120, // blr x9
		0xf9400bf4, // ldr x20,[sp,#16]
		0xa8c27bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn swift_keyed_integer_encoding_symbol(symbol string) ?u64 {
	if symbol != '_$ss22KeyedEncodingContainerV6encode_6forKeyySi_xtKF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(1664)
}
